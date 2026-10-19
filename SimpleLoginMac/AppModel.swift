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
    /// A result that arrives after sign-out or a key change belongs to the old session and is dropped.
    func refreshPinned() async {
        guard let api else { return }
        let session = self.session
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
        guard session == self.session else { return }
        pinned = loaded
    }

    var menuSections: MenuSections {
        MenuSections.make(pinned: pinned, records: engine.records, now: now)
    }

    func enable(aliasID: Int, for duration: AliasDuration) async {
        await perform(on: aliasID) {
            _ = try await engine.enable(aliasID: aliasID, for: duration)
            markPinned(aliasID: aliasID, enabled: true)
        }
    }

    func extend(aliasID: Int, by duration: AliasDuration) {
        perform { try engine.extend(aliasID: aliasID, by: duration) }
    }

    func disableNow(aliasID: Int) async {
        await perform(on: aliasID) {
            try await engine.disableNow(aliasID: aliasID)
            markPinned(aliasID: aliasID, enabled: false)
            onAliasDisabled(aliasID)
        }
    }

    /// Times an already enabled alias, so it is disabled later without changing it now.
    func disableAfter(alias: Alias, duration: AliasDuration) {
        perform { _ = try engine.startTimer(for: alias, duration: duration) }
    }

    /// A random alias uses the account's default domain and mailbox.
    func createRandomAlias(expiringAfter duration: AliasDuration?) async {
        do {
            _ = try await createAlias(expiringAfter: duration) { try await $0.createRandomAlias() }
            lastError = nil
        } catch {
            lastError = Self.userMessage(for: error)
        }
    }

    func createCustomAlias(prefix: String, suffix: AliasSuffix, mailboxID: Int, expiringAfter duration: AliasDuration?) async throws -> Alias {
        try await createAlias(expiringAfter: duration) {
            try await $0.createCustomAlias(prefix: prefix, signedSuffix: suffix.signedSuffix, mailboxIDs: [mailboxID])
        }
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
    /// and toggle twice, leaving the alias disabled.
    private func perform(on aliasID: Int, _ action: () async throws -> Void) async {
        guard busyAliasIDs.insert(aliasID).inserted else { return }
        defer { busyAliasIDs.remove(aliasID) }
        do {
            try await action()
            lastError = nil
        } catch {
            lastError = Self.userMessage(for: error)
        }
    }

    /// A new alias is created enabled. It is only copied once its timer, if any, runs.
    private func createAlias(
        expiringAfter duration: AliasDuration?,
        _ create: (SimpleLoginAPI) async throws -> Alias
    ) async throws -> Alias {
        guard let api else { throw TimerEngineError.notSignedIn }
        let alias = try await create(api)
        if let duration {
            try await startTimer(forNewAlias: alias, duration: duration)
        }
        copyToClipboard(alias.email)
        onNewAliasCopied(alias.email)
        return alias
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

    /// Shows the new state right away instead of waiting for the next refresh.
    private func markPinned(aliasID: Int, enabled: Bool) {
        guard let index = pinned.firstIndex(where: { $0.id == aliasID }) else { return }
        pinned[index] = pinned[index].settingEnabled(enabled)
    }

    static func userMessage(for error: any Error) -> String {
        switch error {
        case let error as APIError:
            error.userMessage
        case AliasCreationError.stillEnabledWithoutTimer(let email):
            "\(email) was created, but its timer could not start and it is still enabled."
        case TimerEngineError.notSignedIn:
            "Not signed in. Set up your API key first."
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
        lastError = nil
        apiKeyInvalid = false
        self.api = api
        engine.api = api
    }
}
