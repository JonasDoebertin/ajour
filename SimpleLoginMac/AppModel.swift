import AppKit
import Observation
import SimpleLoginKit

enum SignOutError: Error, Equatable {
    case aliasesStillEnabled(count: Int)
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
    @ObservationIgnored private var tickLoop: Task<Void, Never>?
    @ObservationIgnored private var runningTick: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    private static let activityPollInterval: TimeInterval = 15
    private static let aliasPageSize = 20
    static let disableBudget: Duration = .seconds(5)

    init(
        keyStore: any APIKeyStoring = KeychainAPIKeyStore(),
        timerStore: any TimerStore,
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.keyStore = keyStore
        self.transport = transport
        currentDate = now
        self.now = now()
        engine = TimerEngine(store: timerStore, now: now)
    }

    func start() {
        if let key = try? keyStore.load() {
            connect(SimpleLoginAPI(apiKey: key, transport: transport))
            phase = .signedIn(nil)
        } else {
            phase = .signedOut
        }
        startTickLoop()
        observeWake()
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
        guard await engine.disableAll(within: Self.disableBudget) else {
            throw SignOutError.aliasesStillEnabled(count: engine.records.count)
        }
        try keyStore.delete()
        connect(nil)
        pinned = []
        phase = .signedOut
    }

    /// Replaces the list only once every page has loaded, so a failure keeps the last complete list.
    func refreshPinned() async {
        guard let api else { return }
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
        pinned = loaded
    }

    /// Disables aliases whose timers are due and, every 15 seconds while timers run, checks them for new mail.
    func tick() async {
        now = currentDate()
        if let dueDate = engine.nextDueDate(), dueDate <= now {
            let events = await engine.processDue()
            if !events.isEmpty { onTimerEvents(events) }
        }
        if engine.hasActiveTimers, isActivityPollDue {
            lastActivityPollAt = now
            let arrivals = await engine.pollActivity()
            if !arrivals.isEmpty { onMailArrivals(arrivals) }
        }
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

    /// Keeps the clock moving while a tick waits on the network, without stacking up ticks behind it.
    private func scheduleTick() {
        now = currentDate()
        guard runningTick == nil else { return }
        runningTick = Task {
            await tick()
            runningTick = nil
        }
    }

    private var isActivityPollDue: Bool {
        guard let lastActivityPollAt else { return true }
        return now.timeIntervalSince(lastActivityPollAt) >= Self.activityPollInterval
    }

    private func connect(_ api: SimpleLoginAPI?) {
        self.api = api
        engine.api = api
    }
}
