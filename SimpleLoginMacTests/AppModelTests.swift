import Foundation
import Observation
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
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = makeModel()
        _ = try await model.signIn(apiKey: "valid-key")
        return model
    }

    /// Gives background work a bounded time to reach the expected state.
    func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
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

    @Test func startWithStoredKeyLoadsTheAccount() async {
        let test = AppModelTests(storedKey: "stored-key")
        test.transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = test.makeModel()

        await model.start()?.value

        #expect(model.phase == .signedIn(Fixtures.userInfo))
        #expect(model.userInfo == Fixtures.userInfo)
    }

    @Test func startWithARejectedStoredKeyStaysSignedInWithoutAccount() async {
        let test = AppModelTests(storedKey: "revoked-key")
        test.transport.enqueue("/api/user_info", status: 401, json: #"{"error":"Wrong api key"}"#)
        let model = test.makeModel()

        await model.start()?.value

        #expect(test.requestCount(path: "/api/user_info") == 1)
        #expect(model.phase == .signedIn(nil))
    }

    @Test func startWithoutStoredKeyLoadsNoAccount() {
        let model = makeModel()

        #expect(model.start() == nil)
    }

    @Test func loadingTheAccountFailsWithoutLeavingTheSignedInPhase() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/user_info", status: 401, json: #"{"error":"Wrong api key"}"#)

        await model.loadUserInfo()

        #expect(model.phase == .signedIn(Fixtures.userInfo))
    }

    @Test func loadingTheAccountWhileSignedOutRequestsNothing() async {
        let model = makeModel()
        model.start()

        await model.loadUserInfo()

        #expect(model.phase == .signedOut)
        #expect(transport.requests.isEmpty)
    }

    @Test func loadingTheAccountDiscardsAResultArrivingAfterSignOut() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/user_info", json: Fixtures.userInfoJSON)
        let load = Task { await model.loadUserInfo() }
        await transport.waitUntilARequestIsHeld()

        try await model.signOut()
        transport.release()
        await load.value

        #expect(model.phase == .signedOut)
        #expect(model.userInfo == nil)
    }

    @Test func signInValidatesTheKeyAndSavesIt() async throws {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
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
        transport.enqueue("/api/user_info", status: 401, json: #"{"error":"Wrong api key"}"#)
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
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        var forwardedEvents: [[TimerEvent]] = []
        model.onTimerEvents = { forwardedEvents.append($0) }

        await model.tick()

        #expect(forwardedEvents == [[.disabled(aliasID: 7, email: "shop@example.com")]])
        #expect(model.engine.records.isEmpty)
    }

    @Test func anExpiredAliasShowsAsDisabledBeforeOtherDueAliasesFinish() async throws {
        let start = TestClock().now
        let test = AppModelTests(records: [.expired(aliasID: 6, at: start), .expired(aliasID: 7, at: start)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/v2/aliases", json: #"{"aliases":[\#(Fixtures.aliasJSON(id: 6)),\#(Fixtures.aliasJSON(id: 7))]}"#)
        await model.refreshPinned()
        test.transport.enqueue("/api/aliases/6", json: Fixtures.aliasJSON(id: 6, enabled: true))
        test.transport.enqueue("/api/aliases/6/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        let work = model.scheduleTick()
        await test.transport.waitUntilARequestIsHeld()

        #expect(model.menuSections.pinned.map(\.state) == [.disabled, .timed(remaining: 0)])

        test.transport.release()
        for task in work { await task.value }
    }

    @Test func aPartlyFailedSignOutShowsTheAliasesItDisabled() async throws {
        let start = TestClock().now
        let test = AppModelTests(records: [.running(aliasID: 6, at: start), .running(aliasID: 7, at: start)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/v2/aliases", json: #"{"aliases":[\#(Fixtures.aliasJSON(id: 6)),\#(Fixtures.aliasJSON(id: 7))]}"#)
        await model.refreshPinned()
        test.transport.enqueue("/api/aliases/6", json: Fixtures.aliasJSON(id: 6, enabled: true))
        test.transport.enqueue("/api/aliases/6/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await #expect(throws: SignOutError.aliasesStillEnabled(count: 1)) {
            try await model.signOut()
        }

        #expect(model.menuSections.pinned.map(\.state) == [.disabled, .timed(remaining: 290)])
    }

    @Test func tickWithoutDueAliasesForwardsNoEvents() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7))
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
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, forwardedAt: forwardedAt))
        var forwardedArrivals: [[MailArrival]] = []
        model.onMailArrivals = { forwardedArrivals.append($0) }

        await model.tick()

        let expected = MailArrival(aliasID: 7, aliasEmail: "shop@example.com", sender: "login@shop.com", timestamp: forwardedAt)
        #expect(forwardedArrivals == [[expected]])
    }

    @Test func tickPollsActivityAtMostEvery15Seconds() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7))
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7))

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

    @Test func aStalledActivityPollDoesNotDelayDueDisables() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7))
        model.scheduleTick()
        await test.transport.waitUntilARequestIsHeld()

        test.clock.advance(by: 300)
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        var forwardedEvents: [[TimerEvent]] = []
        model.onTimerEvents = { forwardedEvents.append($0) }
        model.scheduleTick()
        await test.waitUntil { !forwardedEvents.isEmpty }

        #expect(forwardedEvents == [[.disabled(aliasID: 7, email: "shop@example.com")]])
        test.transport.release()
    }

    @Test func preparingForTerminationStopsTickWorkSoNothingIsForwarded() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        let forwardedAt = test.clock.now.addingTimeInterval(-5)
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, forwardedAt: forwardedAt))
        var forwardedArrivals: [[MailArrival]] = []
        model.onMailArrivals = { forwardedArrivals.append($0) }
        model.scheduleTick()
        await test.transport.waitUntilARequestIsHeld()

        await model.prepareForTermination()
        test.transport.release()
        try await Task.sleep(for: .milliseconds(100))

        #expect(forwardedArrivals.isEmpty)
    }

    @Test func preparingForTerminationDropsEventsOfInterruptedExpiryProcessing() async throws {
        let start = TestClock().now
        let records = [6, 7].map {
            TimerRecord(aliasID: $0, email: "alias\($0)@example.com", enabledAt: start.addingTimeInterval(-10), expiresAt: start.addingTimeInterval(10))
        }
        let test = AppModelTests(records: records)
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/6", json: Fixtures.aliasJSON(id: 6, enabled: true))
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        await model.tick()
        test.clock.advance(by: 12)
        test.transport.enqueue("/api/aliases/6", json: Fixtures.aliasJSON(id: 6, enabled: true))
        test.transport.enqueue("/api/aliases/6/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        var forwardedEvents: [[TimerEvent]] = []
        model.onTimerEvents = { forwardedEvents.append($0) }
        model.scheduleTick()
        await test.transport.waitUntilARequestIsHeld()

        test.transport.release()
        await model.prepareForTermination()
        try await Task.sleep(for: .milliseconds(100))

        #expect(forwardedEvents.isEmpty)
        #expect(test.requestCount(path: "/api/aliases/6/toggle") == 1)
    }

    @Test func preparingForTerminationDisablesTimedAliases() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.prepareForTermination()

        #expect(test.timerStore.records.isEmpty)
    }

    @Test func signInResumesDisablesStoppedByARevokedKey() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        test.transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        await model.tick()
        #expect(model.engine.nextDueDate() == nil)

        test.transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "replacement-key")

        #expect(model.engine.nextDueDate() != nil)
    }

    @Test func aRevokedKeyDuringExpiryMarksTheAPIKeyInvalid() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        test.transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        #expect(model.apiKeyInvalid == false)

        await model.tick()

        #expect(model.apiKeyInvalid)
    }

    @Test func savingANewKeyClearsTheInvalidAPIKeyMark() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        test.transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        await model.tick()

        test.transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "replacement-key")

        #expect(model.apiKeyInvalid == false)
    }

    @Test func aRejectedReplacementKeyKeepsTheInvalidAPIKeyMark() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        test.transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        await model.tick()

        test.transport.enqueue("/api/user_info", status: 401, json: #"{"error":"Wrong api key"}"#)
        _ = try? await model.signIn(apiKey: "another-revoked-key")

        #expect(model.apiKeyInvalid)
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
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

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

    @Test func signOutErrorsExplainWhySignOutIsBlocked() {
        #expect(SignOutError.aliasesStillEnabled(count: 2).userMessage == "2 aliases are still enabled. Check your connection and try again.")
        #expect(SignOutError.aliasesStillEnabled(count: 1).userMessage == "1 alias is still enabled. Check your connection and try again.")
        #expect(SignOutError.timerDataUnreadable.userMessage == "Timer data is unreadable. Sign-out is blocked to avoid losing track of enabled aliases.")
    }

    @Test func refreshPinnedLoadsPagesUntilAPageIsNotFull() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...20))
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 21...23))

        await model.refreshPinned()

        #expect(model.pinned.map(\.id) == Array(1...23))
        let pageRequests = transport.requests.filter { $0.url?.path == "/api/v2/aliases" }
        let queries = pageRequests.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] }
        #expect(queries.map { $0.first { $0.name == "page_id" }?.value } == ["0", "1"])
        #expect(queries.allSatisfy { $0.contains { $0.name == "pinned" } })
    }

    @Test func refreshPinnedKeepsTheLastListWhenAPageFails() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))
        await model.refreshPinned()
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...20))

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

    @Test func signOutWithUnreadableTimerDataKeepsTheKey() async throws {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = AppModel(keyStore: keyStore, timerStore: UnavailableTimerStore(reason: "test"), transport: transport)
        _ = try await model.signIn(apiKey: "valid-key")

        await #expect(throws: SignOutError.timerDataUnreadable) {
            try await model.signOut()
        }

        #expect(keyStore.key == "valid-key")
        #expect(model.phase == .signedIn(Fixtures.userInfo))
    }

    @Test func refreshPinnedDiscardsAResultArrivingAfterSignOut() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))
        let refresh = Task { await model.refreshPinned() }
        await transport.waitUntilARequestIsHeld()

        try await model.signOut()
        transport.release()
        await refresh.value

        #expect(model.pinned.isEmpty)
    }

    @Test func refreshPinnedDiscardsAResultArrivingAfterAKeyChange() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))
        let refresh = Task { await model.refreshPinned() }
        await transport.waitUntilARequestIsHeld()

        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "other-account-key")
        transport.release()
        await refresh.value

        #expect(model.pinned.isEmpty)
    }

    @Test func aRefreshFinishingAfterANewerOneIsDiscarded() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))
        let olderRefresh = Task { await model.refreshPinned() }
        await transport.waitUntilARequestIsHeld()
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 4...5))

        await model.refreshPinned()
        transport.release()
        await olderRefresh.value

        #expect(model.pinned.map(\.id) == [4, 5])
    }

    @Test func refreshingAnUnchangedListLeavesThePinnedListUntouched() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))
        await model.refreshPinned()
        let pinnedChanged = ChangeFlag()
        withObservationTracking { _ = model.pinned } onChange: { pinnedChanged.set() }
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))

        await model.refreshPinned()

        #expect(pinnedChanged.isSet == false)
    }

    @Test func signOutForgetsPinnedAliases() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))
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
