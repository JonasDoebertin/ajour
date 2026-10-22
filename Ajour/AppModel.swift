import AppKit
import Observation
import SimpleLoginKit

struct StillEnabledAlias: Equatable {
    let email: String
    let problem: DisableProblem

    var reason: String {
        switch problem {
        case .unreachable: "SimpleLogin can't be reached"
        case .notResponding: "SimpleLogin isn't responding"
        case .refused: "the API key can't change it"
        case .keyRejected: "the API key was rejected"
        case .other: "SimpleLogin reported an error"
        }
    }
}

enum SignOutError: Error, Equatable {
    /// Aliases sorted by email, plus the number of enables and creations still running when sign-out gave up waiting.
    case aliasesStillEnabled([StillEnabledAlias], pendingEnables: Int)
    case timerDataUnreadable

    var title: String {
        switch self {
        case .aliasesStillEnabled(let aliases, let pendingEnables):
            let total = aliases.count + pendingEnables
            return total == 1 ? "An Alias Is Still Enabled" : "\(total) Aliases Are Still Enabled"
        case .timerDataUnreadable:
            return "Could Not Sign Out"
        }
    }

    var userMessage: String {
        switch self {
        case .aliasesStillEnabled(let aliases, let pendingEnables):
            var lines = aliases.map { "\($0.email): \($0.reason)" }
            if pendingEnables > 0 {
                let pending = pendingEnables == 1 ? "1 alias" : "\(pendingEnables) aliases"
                lines.append("\(pending) being enabled or created right now")
            }
            let consequence = aliases.count + pendingEnables == 1 ? "it stays" : "these aliases stay"
            return lines.joined(separator: "\n") + "\n\nIf you sign out anyway, \(consequence) enabled."
        case .timerDataUnreadable:
            return "Timer data is unreadable. Sign-out is blocked to avoid losing track of enabled aliases."
        }
    }
}

enum AliasCreationError: Error, Equatable {
    case disabledWithoutTimer(email: String)
    case stillEnabledWithoutTimer(email: String)
    case accountChanged(email: String)
    case disabledAfterAccountChange(email: String)
    case stillEnabledAfterAccountChange(email: String)
}

enum AliasActionError: Error, Equatable {
    case alreadyDisabled(email: String)
    case timerAlreadyEnded(email: String)
}

@MainActor @Observable final class AppModel {
    enum Phase: Equatable {
        case loading, signedOut, signedIn(UserInfo?)
    }

    private(set) var phase: Phase = .loading
    private(set) var pinned: [Alias] = []
    /// False until a pinned refresh succeeds for the current key.
    private(set) var pinnedLoaded = false
    private(set) var now: Date
    /// The reason the last alias action failed, until an action succeeds or the key changes.
    private(set) var lastError: String? {
        didSet { if lastError == nil { lastErrorIsNetwork = false } }
    }
    private(set) var lastErrorIsNetwork = false
    private var activities: [Int: AliasActivity] = [:]
    let engine: TimerEngine
    private(set) var api: SimpleLoginAPI?
    @ObservationIgnored var onTimerEvents: ([TimerEvent]) -> Void = { _ in }
    @ObservationIgnored var onMailArrivals: ([MailArrival]) -> Void = { _ in }
    /// Called for each alias as soon as the app has disabled it.
    @ObservationIgnored var onAliasDisabled: (Int) -> Void = { _ in }
    /// Called for each alias whose failed disable stops being retried while the alias stays enabled.
    @ObservationIgnored var onDisableRetriesStopped: (Int) -> Void = { _ in }
    @ObservationIgnored var onNewAliasCopied: (String) -> Void = { _ in }
    /// Set when timed disables stop because the server rejected the key, until a new key is saved.
    private(set) var apiKeyInvalid = false

    @ObservationIgnored private let keyStore: any APIKeyStoring
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let retry: RetryPolicy
    @ObservationIgnored private let currentDate: @Sendable () -> Date
    @ObservationIgnored private let copyToClipboard: @MainActor (String) -> Void
    /// How long quit tries to disable aliases before giving up.
    @ObservationIgnored private let disableBudget: Duration
    /// How long sign-out waits for enables and tries to disable aliases before giving up. Longer than quit's,
    /// because the person is watching it and giving up keeps them signed in.
    @ObservationIgnored private let signOutBudget: Duration
    @ObservationIgnored private var lastActivityPollAt: Date?
    /// Changes whenever the API key changes or is removed, so work bound to one key can restart.
    private(set) var session = 0
    /// Changes when a pinned refresh starts or the pinned list is patched locally, so an older refresh
    /// never overwrites newer data.
    @ObservationIgnored private var pinnedRevision = 0
    /// The enabled state this app last gave each alias, so lists loaded earlier don't show an outdated one.
    private var enabledChanges: [Int: EnabledChange] = [:]
    /// Counts enabled changes; a list remembers it when it loads, to tell older changes from newer ones.
    @ObservationIgnored private(set) var enabledChangeSequence = 0
    @ObservationIgnored private var tickLoop: Task<Void, Never>?
    @ObservationIgnored private var activityPoll: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    /// Set once quitting starts, so no tick work starts and nothing more is forwarded.
    @ObservationIgnored private var isShuttingDown = false
    /// Enables and creations that can leave an alias enabled before its timer is saved.
    @ObservationIgnored private var enablesInFlight = 0
    @ObservationIgnored private var enablesFinishedWaiters: [AsyncStream<Never>.Continuation] = []

    private static let activityPollInterval: TimeInterval = 15
    private static let aliasPageSize = 20
    private static let pinnedRefreshInterval: Duration = .seconds(60)
    /// How long after launch or wake failed disables stay unreported, while the network settles.
    private static let quietPeriodAfterLaunchOrWake: TimeInterval = 120

    init(
        keyStore: any APIKeyStoring = KeychainAPIKeyStore(),
        timerStore: any TimerStore,
        transport: any HTTPTransport = URLSessionTransport(session: URLSession(configuration: sessionConfiguration())),
        now: @escaping @Sendable () -> Date = Date.init,
        copyToClipboard: @escaping @MainActor (String) -> Void = Clipboard.copy,
        disableBudget: Duration = .seconds(5),
        signOutBudget: Duration = .seconds(30),
        retry: RetryPolicy = .standard
    ) {
        self.keyStore = keyStore
        self.transport = transport
        self.retry = retry
        currentDate = now
        self.copyToClipboard = copyToClipboard
        self.disableBudget = disableBudget
        self.signOutBudget = signOutBudget
        self.now = now()
        engine = TimerEngine(store: timerStore, now: now, retry: retry)
        engine.onAliasDisabled = { [weak self] in self?.aliasWasDisabled($0) }
        engine.onDisableRetriesStopped = { [weak self] in self?.onDisableRetriesStopped($0) }
    }

    /// A request on a dead connection, for example right after wake, gives up after 15 seconds instead of
    /// URLSession's default 60. Polls then stay on schedule, and failed disables reach their retry sooner.
    nonisolated static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        return configuration
    }

    /// Returns the account load started for a stored key, so callers can wait for it.
    @discardableResult
    func start() -> Task<Void, Never>? {
        var accountLoad: Task<Void, Never>?
        if let key = try? keyStore.load() {
            connect(SimpleLoginAPI(apiKey: key, transport: transport, retry: retry))
            phase = .signedIn(nil)
            accountLoad = Task { await loadUserInfo() }
        } else {
            phase = .signedOut
        }
        deferFailureReports()
        startTickLoop()
        observeWake()
        return accountLoad
    }

    /// Whether quitting has to wait for aliases to be disabled first, including ones still being enabled.
    var needsToDisableBeforeQuitting: Bool {
        engine.hasActiveTimers || enablesInFlight > 0
    }

    var userInfo: UserInfo? {
        guard case .signedIn(let userInfo) = phase else { return nil }
        return userInfo
    }

    /// The account shown in Settings. A failure keeps the signed-in phase without account details.
    func loadUserInfo() async {
        guard let api else { return }
        let session = self.session
        guard let userInfo = try? await api.userInfo(), session == self.session else { return }
        phase = .signedIn(userInfo)
    }

    /// Only a key the server accepts is saved, so a typo never replaces a working key.
    func signIn(apiKey: String) async throws -> UserInfo {
        let candidate = SimpleLoginAPI(apiKey: apiKey, transport: transport, retry: retry)
        let userInfo = try await candidate.userInfo()
        try keyStore.save(apiKey)
        connect(candidate)
        engine.resumeAfterKeyChange()
        phase = .signedIn(userInfo)
        return userInfo
    }

    /// Timed aliases are disabled first: without the key, nothing could disable them later.
    /// Throws what stays enabled, so the person can sign out anyway.
    func signOut() async throws {
        guard engine.loadError == nil else { throw SignOutError.timerDataUnreadable }
        switch await disableEverything(within: signOutBudget) {
        case .timerDataUnreadable:
            throw SignOutError.timerDataUnreadable
        case .allDisabled where enablesInFlight == 0:
            break
        case .allDisabled:
            throw SignOutError.aliasesStillEnabled([], pendingEnables: enablesInFlight)
        case .stillEnabled(let problems):
            throw SignOutError.aliasesStillEnabled(stillEnabledAliases(problems), pendingEnables: enablesInFlight)
        }
        try removeAccount()
    }

    /// Leaves aliases that stay enabled as they are: their timers are forgotten, because without the key
    /// nothing could disable them. Stops before removing the key if the timers can't be forgotten, and tracks
    /// the timers again if the key can't be removed, so a person who stays signed in keeps every timer.
    func signOutAnyway() async throws {
        let discarded: DiscardedTimers
        do {
            discarded = try engine.discardAll()
        } catch {
            throw SignOutError.timerDataUnreadable
        }
        do {
            try removeAccount()
        } catch {
            try? engine.restore(discarded)
            throw error
        }
    }

    private func removeAccount() throws {
        try keyStore.delete()
        connect(nil)
        pinned = []
        phase = .signedOut
    }

    private func stillEnabledAliases(_ problems: [Int: DisableProblem]) -> [StillEnabledAlias] {
        problems
            .compactMap { aliasID, problem in
                engine.record(for: aliasID).map { StillEnabledAlias(email: $0.email, problem: problem) }
            }
            .sorted { $0.email.localizedStandardCompare($1.email) == .orderedAscending }
    }

    /// Replaces the list only once every page has loaded, so a failure keeps the last complete list.
    /// A result that arrives after sign-out or a key change belongs to the old session and is dropped,
    /// as is one overtaken by a newer refresh or a local change.
    func refreshPinned() async {
        guard let api else { return }
        let session = self.session
        pinnedRevision += 1
        let revision = pinnedRevision
        var loaded: [Alias] = []
        var page = 0
        do {
            while true {
                let aliases = try await api.aliases(page: page, filter: .pinned)
                loaded += aliases
                guard aliases.count == Self.aliasPageSize else { break }
                page += 1
            }
        } catch {
            return
        }
        guard session == self.session, revision == pinnedRevision else { return }
        pinned = loaded
        pinnedLoaded = true
    }

    var menuSections: MenuSections {
        MenuSections.make(pinned: pinned, records: engine.records, failures: engine.failures, now: now)
    }

    func menuState(at date: Date) -> MenuState {
        MenuState(
            phase: phase,
            lastError: lastError,
            apiKeyInvalid: apiKeyInvalid,
            timerDataUnreadable: engine.loadError != nil,
            sections: MenuSections.make(pinned: pinned, records: engine.records, failures: engine.failures, now: date),
            pinnedLoaded: pinnedLoaded,
            activities: activities.merging(engine.disablingAliasIDs.map { ($0, .disabling) }) { own, _ in own },
            lastErrorIsNetwork: lastErrorIsNetwork,
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    @discardableResult
    func enable(aliasID: Int, for duration: AliasDuration) async -> Bool {
        await whileEnabling {
            await perform(on: aliasID, activity: .enabling) {
                _ = try await engine.enable(aliasID: aliasID, for: duration)
                recordEnabled(true, aliasID: aliasID)
            }
        }
    }

    func extend(aliasID: Int, by duration: AliasDuration) {
        perform { try engine.extend(aliasID: aliasID, by: duration) }
    }

    @discardableResult
    func disableNow(aliasID: Int) async -> Bool {
        await perform(on: aliasID, activity: .disabling) {
            try await engine.disableNow(aliasID: aliasID)
        }
    }

    /// Times an enabled alias, so it is disabled later without changing it now. The alias is read first, because
    /// one shown as enabled may have been disabled elsewhere meanwhile; such an alias is never turned on.
    @discardableResult
    func disableAfter(aliasID: Int, duration: AliasDuration) async -> Bool {
        await whileEnabling {
            await perform(on: aliasID, activity: .updating) {
                guard let api else { throw TimerEngineError.notSignedIn }
                let session = self.session
                let alias = try await api.alias(id: aliasID)
                guard session == self.session else { throw TimerEngineError.accountChanged }
                guard alias.enabled else {
                    recordEnabled(false, aliasID: aliasID)
                    throw AliasActionError.alreadyDisabled(email: alias.email)
                }
                _ = try engine.startTimer(for: alias, duration: duration)
                recordEnabled(true, aliasID: aliasID)
            }
        }
    }

    /// A random alias uses the account's default domain and mailbox.
    func createRandomAlias(expiringAfter duration: AliasDuration?) async {
        let session = self.session
        do {
            _ = try await createAlias(expiringAfter: duration) { try await $0.createRandomAlias() }
            lastError = nil
        } catch {
            guard session == self.session || error is AliasCreationError else { return }
            fail(with: error)
        }
    }

    func createCustomAlias(prefix: String, suffix: AliasSuffix, mailboxID: Int, expiringAfter duration: AliasDuration?) async throws -> Alias {
        try await createAlias(expiringAfter: duration) {
            try await $0.createCustomAlias(prefix: prefix, signedSuffix: suffix.signedSuffix, mailboxIDs: [mailboxID])
        }
    }

    /// Pinned aliases are listed in the menu. The menu's list changes right away and is then reloaded.
    @discardableResult
    func setPinned(_ isPinned: Bool, alias: Alias) async -> Bool {
        let succeeded = await perform(on: alias.id, activity: .updating) {
            guard let api else { throw TimerEngineError.notSignedIn }
            try await api.setPinned(isPinned, aliasID: alias.id)
            patchPinnedList(with: alias.settingPinned(isPinned))
        }
        if succeeded { await refreshPinned() }
        return succeeded
    }

    /// Keeps the alias enabled until the user disables it, so no timer starts.
    @discardableResult
    func enablePermanently(aliasID: Int) async -> Bool {
        await perform(on: aliasID, activity: .enabling) {
            guard let api else { throw TimerEngineError.notSignedIn }
            _ = try await AliasSwitch(api: api, retry: retry).ensureEnabled(aliasID: aliasID)
            recordEnabled(true, aliasID: aliasID)
        }
    }

    /// Stops the alias's timer and leaves the alias enabled. A timer that already ended has disabled the alias.
    @discardableResult
    func keepEnabled(aliasID: Int, email: String) async -> Bool {
        await perform(on: aliasID, activity: .updating) {
            do {
                try engine.cancelTimer(aliasID: aliasID)
            } catch TimerEngineError.noTimer {
                recordEnabled(false, aliasID: aliasID)
                throw AliasActionError.timerAlreadyEnded(email: email)
            }
            recordEnabled(true, aliasID: aliasID)
        }
    }

    /// The state this app gave the alias after `sequence`, if it changed it since.
    func knownEnabled(aliasID: Int, since sequence: Int) -> Bool? {
        guard let change = enabledChanges[aliasID], change.sequence > sequence else { return nil }
        return change.enabled
    }

    func activity(aliasID: Int) -> AliasActivity? {
        activities[aliasID] ?? (engine.disablingAliasIDs.contains(aliasID) ? .disabling : nil)
    }

    /// Retries a failed disable now instead of at its next scheduled attempt.
    func retryDisable(aliasID: Int) async {
        engine.retryNow(aliasID: aliasID)
        await tick()
    }

    func isBusy(aliasID: Int) -> Bool {
        activity(aliasID: aliasID) != nil
    }

    func copy(email: String) {
        copyToClipboard(email)
        lastError = nil
    }

    /// Refreshes the pinned list right away and then every 60 seconds, until cancelled or signed out.
    func keepPinnedFresh() async {
        while api != nil, !Task.isCancelled {
            await refreshPinned()
            try? await Task.sleep(for: Self.pinnedRefreshInterval)
        }
    }

    /// Stops ticking so no poll or event fires during shutdown, then tries to disable timed aliases within
    /// the budget, including aliases still being enabled. Records of aliases that stay enabled remain on disk
    /// for the next launch. A running expiry pass is left alone: `disableAll` joins its attempts, and
    /// cancelling it would start them over.
    func prepareForTermination() async {
        isShuttingDown = true
        tickLoop?.cancel()
        activityPoll?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        _ = await disableEverything(within: disableBudget)
    }

    /// Lets enables in flight save their timers first, so the aliases they enable are disabled too.
    /// Waiting and disabling share one budget.
    private func disableEverything(within budget: Duration) async -> DisableAllOutcome {
        let deadline = ContinuousClock.now + budget
        await waitForEnablesInFlight(until: deadline)
        return await engine.disableAll(within: max(.zero, deadline - ContinuousClock.now))
    }

    /// Runs an action that can enable an alias before its timer is saved, so quit and sign-out wait for it.
    private func whileEnabling<Result>(_ action: () async throws -> Result) async rethrows -> Result {
        enablesInFlight += 1
        defer { finishEnable() }
        return try await action()
    }

    private func finishEnable() {
        enablesInFlight -= 1
        guard enablesInFlight == 0 else { return }
        enablesFinishedWaiters.forEach { $0.finish() }
        enablesFinishedWaiters = []
    }

    private func waitForEnablesInFlight(until deadline: ContinuousClock.Instant) async {
        guard enablesInFlight > 0 else { return }
        let (enablesFinished, waiter) = AsyncStream<Never>.makeStream()
        enablesFinishedWaiters.append(waiter)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in enablesFinished {} }
            group.addTask { try? await Task.sleep(until: deadline) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Disables aliases whose timers are due and, every 15 seconds while timers run, checks them for new mail.
    /// Waits only for the work this call started.
    func tick() async {
        for work in scheduleTick() {
            await work.value
        }
    }

    /// Entry point for the tick loop and wake. Expiry processing and activity polling run independently, so a slow
    /// poll never holds back a due disable. Activity polling runs at most once at a time. Expiry processing starts
    /// whenever an alias is due, even while earlier disables still run, so a slow disable never holds back another.
    @discardableResult
    func scheduleTick() -> [Task<Void, Never>] {
        guard !isShuttingDown else { return [] }
        now = currentDate()
        return [startDueProcessingIfNeeded(), startActivityPollIfNeeded()].compactMap { $0 }
    }

    private func startDueProcessingIfNeeded() -> Task<Void, Never>? {
        guard let dueDate = engine.nextDueDate(), dueDate <= now else { return nil }
        return Task {
            let events = await engine.processDue()
            guard !events.isEmpty, !isShuttingDown else { return }
            if events.contains(.unauthorized) { apiKeyInvalid = true }
            onTimerEvents(events)
        }
    }

    private func startActivityPollIfNeeded() -> Task<Void, Never>? {
        guard activityPoll == nil, engine.hasActiveTimers, isActivityPollDue else { return nil }
        lastActivityPollAt = now
        let work = Task {
            let arrivals = await engine.pollActivity()
            activityPoll = nil
            if !arrivals.isEmpty, !Task.isCancelled, !isShuttingDown { onMailArrivals(arrivals) }
        }
        activityPoll = work
        return work
    }

    private func startTickLoop() {
        guard tickLoop == nil else { return }
        tickLoop = Task { [weak self] in
            while !Task.isCancelled, let self {
                scheduleTick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// A wake right after sleep must not wait for the next loop iteration.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.didWake() }
        }
    }

    func didWake() {
        deferFailureReports()
        scheduleTick()
    }

    private func deferFailureReports() {
        engine.failureReportsResumeAt = currentDate().addingTimeInterval(Self.quietPeriodAfterLaunchOrWake)
    }

    private var isActivityPollDue: Bool {
        guard let lastActivityPollAt else { return true }
        return now.timeIntervalSince(lastActivityPollAt) >= Self.activityPollInterval
    }

    private func fail(with error: any Error) {
        lastError = Self.userMessage(for: error)
        if case APIError.transport = error {
            lastErrorIsNetwork = true
        } else {
            lastErrorIsNetwork = false
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            lastError = nil
        } catch {
            fail(with: error)
        }
    }

    /// Ignores a second action on the alias while one runs: two enables could both read "disabled"
    /// and toggle twice, leaving the alias disabled. Returns whether the action ran and succeeded.
    private func perform(on aliasID: Int, activity: AliasActivity, _ action: () async throws -> Void) async -> Bool {
        guard activities[aliasID] == nil else { return false }
        activities[aliasID] = activity
        defer { activities[aliasID] = nil }
        do {
            try await action()
            lastError = nil
            return true
        } catch TimerEngineError.accountChanged {
            return false
        } catch {
            fail(with: error)
            return false
        }
    }

    /// A new alias is created enabled. It is only copied once its timer, if any, runs.
    /// An alias created for an account that was signed out or replaced meanwhile isn't timed or copied.
    private func createAlias(
        expiringAfter duration: AliasDuration?,
        _ create: (SimpleLoginAPI) async throws -> Alias
    ) async throws -> Alias {
        guard let api else { throw TimerEngineError.notSignedIn }
        let session = self.session
        return try await whileEnabling {
            let alias = try await create(api)
            guard session == self.session else {
                throw await abandonAfterAccountChange(alias, using: api, wasToExpire: duration != nil)
            }
            if let duration {
                try await startTimer(forNewAlias: alias, duration: duration)
            }
            copyToClipboard(alias.email)
            onNewAliasCopied(alias.email)
            return alias
        }
    }

    /// An alias meant to expire must not stay enabled untracked, so it is disabled with the key it was created with.
    private func abandonAfterAccountChange(_ alias: Alias, using api: SimpleLoginAPI, wasToExpire: Bool) async -> AliasCreationError {
        guard wasToExpire else { return .accountChanged(email: alias.email) }
        do {
            _ = try await AliasSwitch(api: api, retry: retry).ensureDisabled(aliasID: alias.id)
            return .disabledAfterAccountChange(email: alias.email)
        } catch {
            return .stillEnabledAfterAccountChange(email: alias.email)
        }
    }

    /// A new alias whose timer can't start is disabled again right away, so it never stays enabled untracked.
    private func startTimer(forNewAlias alias: Alias, duration: AliasDuration) async throws {
        do {
            _ = try engine.startTimer(for: alias, duration: duration)
        } catch {
            do {
                try await engine.disableNow(aliasID: alias.id)
            } catch {
                throw AliasCreationError.stillEnabledWithoutTimer(email: alias.email)
            }
            throw AliasCreationError.disabledWithoutTimer(email: alias.email)
        }
    }

    /// Every disable the engine completes, whether from expiry, a manual action, quit, or sign-out, shows right away.
    private func aliasWasDisabled(_ aliasID: Int) {
        recordEnabled(false, aliasID: aliasID)
        onAliasDisabled(aliasID)
    }

    /// Shows the new state right away in the menu and in lists loaded before, instead of waiting for a reload.
    private func recordEnabled(_ enabled: Bool, aliasID: Int) {
        enabledChangeSequence += 1
        enabledChanges[aliasID] = EnabledChange(enabled: enabled, sequence: enabledChangeSequence)
        markPinned(aliasID: aliasID, enabled: enabled)
    }

    private func markPinned(aliasID: Int, enabled: Bool) {
        pinnedRevision += 1
        guard let index = pinned.firstIndex(where: { $0.id == aliasID }) else { return }
        pinned[index] = pinned[index].settingEnabled(enabled)
    }

    private func patchPinnedList(with alias: Alias) {
        pinnedRevision += 1
        if alias.pinned {
            guard !pinned.contains(where: { $0.id == alias.id }) else { return }
            pinned.append(alias)
        } else {
            pinned.removeAll { $0.id == alias.id }
        }
    }

    static func userMessage(for error: any Error) -> String {
        switch error {
        case let error as APIError:
            error.userMessage
        case AliasCreationError.disabledWithoutTimer(let email):
            "\(email) was created, but its timer could not start, so it was disabled again."
        case AliasCreationError.stillEnabledWithoutTimer(let email):
            "\(email) was created, but its timer could not start and it is still enabled."
        case AliasCreationError.accountChanged(let email):
            "\(email) was created for the previous account."
        case AliasCreationError.disabledAfterAccountChange(let email):
            "\(email) was created for the previous account and has been disabled."
        case AliasCreationError.stillEnabledAfterAccountChange(let email):
            "\(email) was created for the previous account and could not be disabled."
        case AliasActionError.alreadyDisabled(let email):
            "\(email) is already disabled."
        case AliasActionError.timerAlreadyEnded(let email):
            "\(email) was already disabled."
        case TimerEngineError.notSignedIn:
            "Not signed in. Set up your API key first."
        case TimerEngineError.disableInProgress:
            "The alias is being disabled right now. Try again in a moment."
        case TimerEngineError.storeUnavailable:
            "Timer data is unreadable, so timers can't be started or changed."
        case is AliasSwitchError:
            "The alias did not change. Try again."
        default:
            error.localizedDescription
        }
    }

    private func connect(_ api: SimpleLoginAPI?) {
        session += 1
        pinnedLoaded = false
        enabledChanges = [:]
        lastError = nil
        apiKeyInvalid = false
        self.api = api
        engine.api = api
    }
}

struct EnabledChange: Equatable {
    let enabled: Bool
    let sequence: Int
}

extension Alias {
    func settingPinned(_ pinned: Bool) -> Alias {
        Alias(
            id: id,
            email: email,
            name: name,
            enabled: enabled,
            note: note,
            pinned: pinned,
            nbBlock: nbBlock,
            nbForward: nbForward,
            latestActivity: latestActivity,
            mailboxes: mailboxes
        )
    }
}
