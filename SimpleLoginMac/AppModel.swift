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

@MainActor @Observable final class AppModel {
    enum Phase: Equatable {
        case loading, signedOut, signedIn(UserInfo?)
    }

    private(set) var phase: Phase = .loading
    private(set) var pinned: [Alias] = []
    private(set) var now: Date
    let engine: TimerEngine
    private(set) var api: SimpleLoginAPI?
    @ObservationIgnored var onTimerEvents: ([TimerEvent]) -> Void = { _ in }
    @ObservationIgnored var onMailArrivals: ([MailArrival]) -> Void = { _ in }

    @ObservationIgnored private let keyStore: any APIKeyStoring
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let currentDate: @Sendable () -> Date
    @ObservationIgnored private var lastActivityPollAt: Date?
    /// Changes whenever the API key changes or is removed.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var tickLoop: Task<Void, Never>?
    @ObservationIgnored private var dueProcessing: Task<Void, Never>?
    @ObservationIgnored private var activityPoll: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    private static let activityPollInterval: TimeInterval = 15
    private static let aliasPageSize = 20
    private static let disableBudget: Duration = .seconds(5)

    init(
        keyStore: any APIKeyStoring = KeychainAPIKeyStore(),
        timerStore: any TimerStore,
        transport: any HTTPTransport = URLSessionTransport(session: URLSession(configuration: sessionConfiguration())),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.keyStore = keyStore
        self.transport = transport
        currentDate = now
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

    func start() {
        if let key = try? keyStore.load() {
            connect(SimpleLoginAPI(apiKey: key, transport: transport))
            phase = .signedIn(nil)
            Task { await loadUserInfo() }
        } else {
            phase = .signedOut
        }
        startTickLoop()
        observeWake()
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
            if !events.isEmpty, !Task.isCancelled { onTimerEvents(events) }
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

    private func connect(_ api: SimpleLoginAPI?) {
        session += 1
        self.api = api
        engine.api = api
    }
}
