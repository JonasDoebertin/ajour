import Foundation
import Testing
import SimpleLoginKit
@testable import SimpleLoginMac

@MainActor
struct AppModelTests {
    let keyStore: InMemoryAPIKeyStore
    let timerStore: InMemoryTimerStore
    let transport = StubTransport()
    let clock = TestClock()

    init(storedKey: String? = nil, records: [TimerRecord] = [], keyStoreFailsToLoad: Bool = false) {
        keyStore = InMemoryAPIKeyStore(key: storedKey, failsToLoad: keyStoreFailsToLoad)
        timerStore = InMemoryTimerStore(records: records)
    }

    func makeModel() -> AppModel {
        let clock = clock
        return AppModel(keyStore: keyStore, timerStore: timerStore, transport: transport, now: { clock.now })
    }

    func signedInModel() async throws -> AppModel {
        transport.enqueue(json: Fixtures.userInfoJSON)
        let model = makeModel()
        _ = try await model.signIn(apiKey: "valid-key")
        return model
    }

    func requestCount(path: String) -> Int {
        transport.requests.filter { $0.url?.path == path }.count
    }

    @Test func startWithoutStoredKeyIsSignedOut() {
        let model = makeModel()

        model.start()

        #expect(model.phase == .signedOut)
        #expect(model.api == nil)
        #expect(model.engine.api == nil)
    }

    @Test func startWithStoredKeyIsSignedInAndConnectsTheEngine() {
        let test = AppModelTests(storedKey: "stored-key")
        let model = test.makeModel()

        model.start()

        #expect(model.phase == .signedIn(nil))
        #expect(model.api != nil)
        #expect(model.engine.api != nil)
    }

    @Test func startWithUnreadableKeyStoreIsSignedOut() {
        let test = AppModelTests(keyStoreFailsToLoad: true)
        let model = test.makeModel()

        model.start()

        #expect(model.phase == .signedOut)
        #expect(model.engine.api == nil)
    }

    @Test func signInValidatesTheKeyAndSavesIt() async throws {
        transport.enqueue(json: Fixtures.userInfoJSON)
        let model = makeModel()
        model.start()

        let userInfo = try await model.signIn(apiKey: "new-key")

        #expect(userInfo == Fixtures.userInfo)
        #expect(transport.requests.first?.url?.path == "/api/user_info")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authentication") == "new-key")
        #expect(keyStore.key == "new-key")
        #expect(model.phase == .signedIn(Fixtures.userInfo))
        #expect(model.engine.api != nil)
    }

    @Test func signInWithRejectedKeyDoesNotSaveIt() async {
        transport.enqueue(status: 401, json: #"{"error":"Wrong api key"}"#)
        let model = makeModel()
        model.start()

        await #expect(throws: APIError.unauthorized) {
            try await model.signIn(apiKey: "bad-key")
        }

        #expect(keyStore.key == nil)
        #expect(model.phase == .signedOut)
        #expect(model.api == nil)
        #expect(model.engine.api == nil)
    }

    @Test func tickUpdatesTheCurrentTime() async {
        let model = makeModel()
        clock.advance(by: 30)

        await model.tick()

        #expect(model.now == clock.now)
    }

    @Test func tickDisablesDueAliasesAndForwardsTheEvents() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue(json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue(json: Fixtures.toggleJSON(enabled: false))
        var forwardedEvents: [[TimerEvent]] = []
        model.onTimerEvents = { forwardedEvents.append($0) }

        await model.tick()

        #expect(forwardedEvents == [[.disabled(aliasID: 7, email: "shop@example.com")]])
        #expect(model.engine.records.isEmpty)
    }

    @Test func tickWithoutDueAliasesForwardsNoEvents() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue(json: Fixtures.aliasJSON(id: 7))
        var forwardedEvents: [[TimerEvent]] = []
        model.onTimerEvents = { forwardedEvents.append($0) }

        await model.tick()

        #expect(forwardedEvents.isEmpty)
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 0)
    }

    @Test func tickForwardsMailArrivingWhileATimerRuns() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        let forwardedAt = test.clock.now.addingTimeInterval(-5)
        test.transport.enqueue(json: Fixtures.aliasJSON(id: 7, forwardedAt: forwardedAt))
        var forwardedArrivals: [[MailArrival]] = []
        model.onMailArrivals = { forwardedArrivals.append($0) }

        await model.tick()

        let expected = MailArrival(aliasID: 7, aliasEmail: "shop@example.com", sender: "login@shop.com", timestamp: forwardedAt)
        #expect(forwardedArrivals == [[expected]])
    }

    @Test func tickPollsActivityAtMostEvery15Seconds() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue(json: Fixtures.aliasJSON(id: 7))
        test.transport.enqueue(json: Fixtures.aliasJSON(id: 7))

        await model.tick()
        test.clock.advance(by: 14)
        await model.tick()
        #expect(test.requestCount(path: "/api/aliases/7") == 1)

        test.clock.advance(by: 1)
        await model.tick()
        #expect(test.requestCount(path: "/api/aliases/7") == 2)
    }

    @Test func tickDoesNotPollWithoutRunningTimers() async throws {
        let model = try await signedInModel()

        await model.tick()

        #expect(transport.requests.count == 1)
    }

    @Test func signInResumesDisablesStoppedByARevokedKey() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue(status: 401, json: #"{"error":"Wrong api key"}"#)
        await model.tick()
        #expect(model.engine.nextDueDate() == nil)

        test.transport.enqueue(json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "replacement-key")

        #expect(model.engine.nextDueDate() != nil)
    }

    @Test func signOutWithoutTimersRemovesTheKey() async throws {
        let model = try await signedInModel()

        try await model.signOut()

        #expect(keyStore.key == nil)
        #expect(model.phase == .signedOut)
        #expect(model.api == nil)
        #expect(model.engine.api == nil)
    }

    @Test func signOutDisablesTimedAliasesBeforeRemovingTheKey() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue(json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue(json: Fixtures.toggleJSON(enabled: false))

        try await model.signOut()

        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(test.timerStore.records.isEmpty)
        #expect(test.keyStore.key == nil)
        #expect(model.phase == .signedOut)
    }

    @Test func signOutKeepsTheKeyWhenTimedAliasesStayEnabled() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()

        await #expect(throws: SignOutError.aliasesStillEnabled(count: 1)) {
            try await model.signOut()
        }

        #expect(test.keyStore.key == "valid-key")
        #expect(model.phase == .signedIn(Fixtures.userInfo))
        #expect(model.engine.api != nil)
    }

    @Test func refreshPinnedLoadsPagesUntilAPageIsNotFull() async throws {
        let model = try await signedInModel()
        transport.enqueue(json: Fixtures.aliasPageJSON(ids: 1...20))
        transport.enqueue(json: Fixtures.aliasPageJSON(ids: 21...23))

        await model.refreshPinned()

        #expect(model.pinned.map(\.id) == Array(1...23))
        let pageRequests = transport.requests.filter { $0.url?.path == "/api/v2/aliases" }
        let queries = pageRequests.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] }
        #expect(queries.map { $0.first { $0.name == "page_id" }?.value } == ["0", "1"])
        #expect(queries.allSatisfy { $0.contains { $0.name == "pinned" } })
    }

    @Test func refreshPinnedKeepsTheLastListWhenAPageFails() async throws {
        let model = try await signedInModel()
        transport.enqueue(json: Fixtures.aliasPageJSON(ids: 1...3))
        await model.refreshPinned()
        transport.enqueue(json: Fixtures.aliasPageJSON(ids: 1...20))

        await model.refreshPinned()

        #expect(model.pinned.map(\.id) == [1, 2, 3])
    }

    @Test func refreshPinnedWhileSignedOutLoadsNothing() async {
        let model = makeModel()
        model.start()

        await model.refreshPinned()

        #expect(model.pinned.isEmpty)
        #expect(transport.requests.isEmpty)
    }

    @Test func signOutForgetsPinnedAliases() async throws {
        let model = try await signedInModel()
        transport.enqueue(json: Fixtures.aliasPageJSON(ids: 1...3))
        await model.refreshPinned()

        try await model.signOut()

        #expect(model.pinned.isEmpty)
    }
}

private extension TimerRecord {
    static func expired(aliasID: Int, at now: Date) -> TimerRecord {
        TimerRecord(aliasID: aliasID, email: "shop@example.com", enabledAt: now.addingTimeInterval(-360), expiresAt: now.addingTimeInterval(-60))
    }

    static func running(aliasID: Int, at now: Date) -> TimerRecord {
        TimerRecord(aliasID: aliasID, email: "shop@example.com", enabledAt: now.addingTimeInterval(-10), expiresAt: now.addingTimeInterval(290))
    }
}
