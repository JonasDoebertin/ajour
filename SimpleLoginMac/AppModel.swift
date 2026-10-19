import AppKit
import Observation
import SimpleLoginKit

enum SignOutError: Error, Equatable {
    case aliasesStillEnabled(count: Int)
    case timerDataUnreadable

    var userMessage: String {
        switch self {
        case .aliasesStillEnabled(let count):
            let aliases = count == 1 ? "1 alias is" : "\(count) aliases are"
            return "\(aliases) still enabled. Check your connection and try again."
        case .timerDataUnreadable:
            return "Timer data is unreadable. Sign-out is blocked to avoid losing track of enabled aliases."
        }
    }
}

enum AliasCreationError: Error, Equatable {
    case stillEnabledWithoutTimer(email: String)
    case accountChanged(email: String)
    case disabledAfterAccountChange(email: String)
    case stillEnabledAfterAccountChange(email: String)
}

enum AliasActionError: Error, Equatable {
    case timerAlreadyEnded(email: String)
}

@MainActor @Observable final class AppModel {
    enum Phase: Equatable {
        case loading, signedOut, signedIn(UserInfo?)
    }

    private(set) var phase: Phase = .loading
    private(set) var pinned: [Alias] = []
    private(set) var now: Date
    /// The reason the last alias action failed, until an action succeeds or the key changes.
    private(set) var lastError: String?
    private var busyAliasIDs: Set<Int> = []
    let engine: TimerEngine
    private(set) var api: SimpleLoginAPI?
    @ObservationIgnored var onTimerEvents: ([TimerEvent]) -> Void = { _ in }
    @ObservationIgnored var onMailArrivals: ([MailArrival]) -> Void = { _ in }
    @ObservationIgnored var onAliasDisabled: (Int) -> Void = { _ in }
    @ObservationIgnored var onNewAliasCopied: (String) -> Void = { _ in }
    /// Set when timed disables stop because the server rejected the key, until a new key is saved.
    private(set) var apiKeyInvalid = false

    @ObservationIgnored private let keyStore: any APIKeyStoring
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let currentDate: @Sendable () -> Date
    @ObservationIgnored private let copyToClipboard: @MainActor (String) -> Void
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
    @ObservationIgnored private var dueProcessing: Task<Void, Never>?
    @ObservationIgnored private var activityPoll: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    private static let activityPollInterval: TimeInterval = 15
    private static let aliasPageSize = 20
    private static let disableBudget: Duration = .seconds(5)
    private static let pinnedRefreshInterval: Duration = .seconds(60)

    init(
        keyStore: any APIKeyStoring = KeychainAPIKeyStore(),
        timerStore: any TimerStore,
        transport: any HTTPTransport = URLSessionTransport(session: URLSession(configuration: sessionConfiguration())),
        now: @escaping @Sendable () -> Date = Date.init,
        copyToClipboard: @escaping @MainActor (String) -> Void = Clipboard.copy
    ) {
        self.keyStore = keyStore
        self.transport = transport
        currentDate = now
        self.copyToClipboard = copyToClipboard
        self.now = now()
        engine = TimerEngine(store: timerStore, now: now)
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
            connect(SimpleLoginAPI(apiKey: key, transport: transport))
            phase = .signedIn(nil)
            accountLoad = Task { await loadUserInfo() }
        } else {
            phase = .signedOut
        }
        startTickLoop()
        observeWake()
        return accountLoad
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
        let candidate = SimpleLoginAPI(apiKey: apiKey, transport: transport)
        let userInfo = try await candidate.userInfo()
        try keyStore.save(apiKey)
        connect(candidate)
        engine.resumeAfterKeyChange()
        phase = .signedIn(userInfo)
        return userInfo
    }

    /// Timed aliases are disabled first: without the key, nothing could disable them later.
    func signOut() async throws {
        guard engine.loadError == nil else { throw SignOutError.timerDataUnreadable }
        guard await engine.disableAll(within: Self.disableBudget) else {
            throw SignOutError.aliasesStillEnabled(count: engine.records.count)
        }
        try keyStore.delete()
        connect(nil)
        pinned = []
        phase = .signedOut
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
    }

    var menuSections: MenuSections {
        MenuSections.make(pinned: pinned, records: engine.records, now: now)
    }

    @discardableResult
    func enable(aliasID: Int, for duration: AliasDuration) async -> Bool {
        await perform(on: aliasID) {
            _ = try await engine.enable(aliasID: aliasID, for: duration)
            recordEnabled(true, aliasID: aliasID)
        }
    }

    func extend(aliasID: Int, by duration: AliasDuration) {
        perform { try engine.extend(aliasID: aliasID, by: duration) }
    }

    @discardableResult
    func disableNow(aliasID: Int) async -> Bool {
        await perform(on: aliasID) {
            try await engine.disableNow(aliasID: aliasID)
            recordEnabled(false, aliasID: aliasID)
            onAliasDisabled(aliasID)
        }
    }

    /// Times an already enabled alias, so it is disabled later without changing it now.
    func disableAfter(alias: Alias, duration: AliasDuration) {
        perform { _ = try engine.startTimer(for: alias, duration: duration) }
    }

    /// A random alias uses the account's default domain and mailbox.
    func createRandomAlias(expiringAfter duration: AliasDuration?) async {
        let session = self.session
        do {
            _ = try await createAlias(expiringAfter: duration) { try await $0.createRandomAlias() }
            lastError = nil
        } catch {
            guard session == self.session || error is AliasCreationError else { return }
            lastError = Self.userMessage(for: error)
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
        let succeeded = await perform(on: alias.id) {
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
        await perform(on: aliasID) {
            guard let api else { throw TimerEngineError.notSignedIn }
            _ = try await AliasSwitch(api: api).ensureEnabled(aliasID: aliasID)
            recordEnabled(true, aliasID: aliasID)
        }
    }

    /// Stops the alias's timer and leaves the alias enabled. A timer that already ended has disabled the alias.
    @discardableResult
    func keepEnabled(aliasID: Int, email: String) async -> Bool {
        await perform(on: aliasID) {
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

    func isBusy(aliasID: Int) -> Bool {
        busyAliasIDs.contains(aliasID)
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
    /// the budget. Records of aliases that stay enabled remain on disk for the next launch.
    func prepareForTermination() async {
        tickLoop?.cancel()
        dueProcessing?.cancel()
        activityPoll?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        _ = await engine.disableAll(within: Self.disableBudget)
    }

    /// Disables aliases whose timers are due and, every 15 seconds while timers run, checks them for new mail.
    /// Waits only for the work this call started.
    func tick() async {
        for work in scheduleTick() {
            await work.value
        }
    }

    /// Entry point for the tick loop and wake. Expiry processing and activity polling each run at most once
    /// at a time and independently, so a slow poll never holds back a due disable.
    @discardableResult
    func scheduleTick() -> [Task<Void, Never>] {
        now = currentDate()
        return [startDueProcessingIfNeeded(), startActivityPollIfNeeded()].compactMap { $0 }
    }

    private func startDueProcessingIfNeeded() -> Task<Void, Never>? {
        guard dueProcessing == nil, let dueDate = engine.nextDueDate(), dueDate <= now else { return nil }
        let work = Task {
            let events = await engine.processDue()
            dueProcessing = nil
            for case .disabled(let aliasID, _) in events {
                recordEnabled(false, aliasID: aliasID)
            }
            guard !events.isEmpty, !Task.isCancelled else { return }
            if events.contains(.unauthorized) { apiKeyInvalid = true }
            onTimerEvents(events)
        }
        dueProcessing = work
        return work
    }

    private func startActivityPollIfNeeded() -> Task<Void, Never>? {
        guard activityPoll == nil, engine.hasActiveTimers, isActivityPollDue else { return nil }
        lastActivityPollAt = now
        let work = Task {
            let arrivals = await engine.pollActivity()
            activityPoll = nil
            if !arrivals.isEmpty, !Task.isCancelled { onMailArrivals(arrivals) }
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
            Task { @MainActor in self?.scheduleTick() }
        }
    }

    private var isActivityPollDue: Bool {
        guard let lastActivityPollAt else { return true }
        return now.timeIntervalSince(lastActivityPollAt) >= Self.activityPollInterval
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            lastError = nil
        } catch {
            lastError = Self.userMessage(for: error)
        }
    }

    /// Ignores a second action on the alias while one runs: two enables could both read "disabled"
    /// and toggle twice, leaving the alias disabled. Returns whether the action ran and succeeded.
    private func perform(on aliasID: Int, _ action: () async throws -> Void) async -> Bool {
        guard busyAliasIDs.insert(aliasID).inserted else { return false }
        defer { busyAliasIDs.remove(aliasID) }
        do {
            try await action()
            lastError = nil
            return true
        } catch {
            lastError = Self.userMessage(for: error)
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

    /// An alias meant to expire must not stay enabled untracked, so it is disabled with the key it was created with.
    private func abandonAfterAccountChange(_ alias: Alias, using api: SimpleLoginAPI, wasToExpire: Bool) async -> AliasCreationError {
        guard wasToExpire else { return .accountChanged(email: alias.email) }
        do {
            _ = try await AliasSwitch(api: api).ensureDisabled(aliasID: alias.id)
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
            throw error
        }
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
        case AliasCreationError.stillEnabledWithoutTimer(let email):
            "\(email) was created, but its timer could not start and it is still enabled."
        case AliasCreationError.accountChanged(let email):
            "\(email) was created for the previous account."
        case AliasCreationError.disabledAfterAccountChange(let email):
            "\(email) was created for the previous account and has been disabled."
        case AliasCreationError.stillEnabledAfterAccountChange(let email):
            "\(email) was created for the previous account and could not be disabled."
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
