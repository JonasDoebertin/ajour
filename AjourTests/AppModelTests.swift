import Foundation
import Observation
import Testing
import SimpleLoginKit
@testable import Ajour

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

    func makeModel(signOutBudget: Duration = .seconds(30), disableBudget: Duration = .seconds(5)) -> AppModel {
        let clock = clock
        return AppModel(
            keyStore: keyStore,
            timerStore: timerStore,
            transport: transport,
            now: { clock.now },
            disableBudget: disableBudget,
            signOutBudget: signOutBudget,
            retry: .once
        )
    }

    func signedInModel(signOutBudget: Duration = .seconds(30), disableBudget: Duration = .seconds(5)) async throws -> AppModel {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = makeModel(signOutBudget: signOutBudget, disableBudget: disableBudget)
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
        await test.waitUntil { model.menuSections.pinned.first?.state == .disabled }

        #expect(model.menuSections.pinned.map(\.state) == [.disabled, .timed(remaining: 0, endsAt: start.addingTimeInterval(-60), length: 300)])

        test.transport.release()
        for task in work { await task.value }
    }

    @Test func wakingDefersFailureReportsForTwoMinutes() {
        let model = makeModel()

        model.didWake()

        #expect(model.engine.failureReportsResumeAt == clock.now.addingTimeInterval(120))
    }

    @Test func startingDefersFailureReportsForTwoMinutes() {
        let model = makeModel()

        model.start()

        #expect(model.engine.failureReportsResumeAt == clock.now.addingTimeInterval(120))
    }

    @Test func anAliasBeingDisabledAtExpiryShowsDisabling() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        let work = model.scheduleTick()
        await test.transport.waitUntilARequestIsHeld()

        #expect(model.activity(aliasID: 7) == .disabling)
        #expect(model.menuState(at: test.clock.now).activities[7] == .disabling)

        test.transport.release()
        for task in work { await task.value }

        #expect(model.activity(aliasID: 7) == nil)
        #expect(model.menuState(at: test.clock.now).activities[7] == nil)
    }

    @Test func tryAgainStartsTheNextDisableRightAway() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        await model.tick()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.retryDisable(aliasID: 7)

        #expect(test.timerStore.records.isEmpty)
    }

    @Test func tryAgainStartsRightAwayWhileAnotherAliasIsBeingDisabled() async throws {
        let start = TestClock().now
        let test = AppModelTests(records: [.expired(aliasID: 6, at: start), .expired(aliasID: 7, at: start)])
        let model = try await test.signedInModel()
        await model.tick()
        test.transport.holdNext("/api/aliases/6", json: Fixtures.aliasJSON(id: 6, enabled: true))
        model.engine.retryNow(aliasID: 6)
        let work = model.scheduleTick()
        await test.transport.waitUntilARequestIsHeld()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.retryDisable(aliasID: 7)

        #expect(test.timerStore.records.map(\.aliasID) == [6])
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

        await #expect(throws: SignOutError.aliasesStillEnabled([.shop(.unreachable)], pendingEnables: 0)) {
            try await model.signOut()
        }

        #expect(model.menuSections.pinned.map(\.state) == [.disabled, .timed(remaining: 290, endsAt: start.addingTimeInterval(290), length: 300)])
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

    @Test func quittingWhileAnExpiryDisableRunsLetsItFinishInsteadOfStartingOver() async throws {
        let test = AppModelTests(records: [.expired(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        model.scheduleTick()
        await test.transport.waitUntilARequestIsHeld()

        let quit = Task { await model.prepareForTermination() }
        for _ in 0..<20 { await Task.yield() }
        test.transport.release()
        await quit.value

        #expect(test.requestCount(path: "/api/aliases/7") == 1)
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.engine.records.isEmpty)
        #expect(test.timerStore.records.isEmpty)
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

    @Test func signOutNamesEachAliasThatStaysEnabledAndWhy() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()

        await #expect(throws: SignOutError.aliasesStillEnabled([.shop(.unreachable)], pendingEnables: 0)) {
            try await model.signOut()
        }

        #expect(test.keyStore.key == "valid-key")
        #expect(model.phase == .signedIn(Fixtures.userInfo))
        #expect(model.engine.api != nil)
    }

    @Test func aRefusedAliasBlocksSignOutWithItsReason() async throws {
        let test = AppModelTests(records: [.running(aliasID: 7, at: TestClock().now)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", status: 403, json: #"{"error":"Forbidden"}"#)

        await #expect(throws: SignOutError.aliasesStillEnabled([.shop(.refused)], pendingEnables: 0)) {
            try await model.signOut()
        }
    }

    @Test func signOutWaitsForASlowEnableBeyondFiveSeconds() async throws {
        let test = AppModelTests()
        let model = try await test.signedInModel(signOutBudget: .seconds(10), disableBudget: .milliseconds(100))
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let enabling = Task { await model.enable(aliasID: 7, for: .fiveMinutes) }
        await test.transport.waitUntilARequestIsHeld()
        let signOut = Task { try await model.signOut() }

        try await Task.sleep(for: .milliseconds(300))
        test.transport.release()

        try await signOut.value
        _ = await enabling.value
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 2)
        #expect(test.timerStore.records.isEmpty)
        #expect(model.phase == .signedOut)
    }

    @Test func signOutCountsEnablesThatDidNotFinish() async throws {
        let test = AppModelTests()
        let model = try await test.signedInModel(signOutBudget: .milliseconds(200))
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        let enabling = Task { await model.enable(aliasID: 7, for: .fiveMinutes) }
        await test.transport.waitUntilARequestIsHeld()

        await #expect(throws: SignOutError.aliasesStillEnabled([], pendingEnables: 1)) {
            try await model.signOut()
        }

        #expect(test.keyStore.key == "valid-key")
        test.transport.release()
        _ = await enabling.value
    }

    @Test func signOutAnywayDiscardsEveryTimerAndRemovesTheKey() async throws {
        let start = TestClock().now
        let test = AppModelTests(records: [.running(aliasID: 6, at: start), .running(aliasID: 7, at: start)])
        let model = try await test.signedInModel()

        try await model.signOutAnyway()

        #expect(model.engine.records.isEmpty)
        #expect(test.timerStore.records.isEmpty)
        #expect(test.keyStore.key == nil)
        #expect(model.phase == .signedOut)
        #expect(test.requestCount(path: "/api/aliases/6/toggle") + test.requestCount(path: "/api/aliases/7/toggle") == 0)
    }

    @Test func signOutAnywayKeepsTheKeyWhenTheTimersCannotBeDiscarded() async throws {
        let timerStore = InMemoryTimerStore(records: [.running(aliasID: 7, at: TestClock().now)], failsToSave: true)
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = AppModel(keyStore: keyStore, timerStore: timerStore, transport: transport, retry: .once)
        _ = try await model.signIn(apiKey: "valid-key")

        await #expect(throws: SignOutError.timerDataUnreadable) {
            try await model.signOutAnyway()
        }

        #expect(keyStore.key == "valid-key")
        #expect(model.phase == .signedIn(Fixtures.userInfo))
        #expect(model.engine.records.count == 1)
    }

    @Test func signOutAnywayKeepsEveryTimerWhenTheKeyCannotBeRemoved() async throws {
        let start = TestClock().now
        let keyStore = InMemoryAPIKeyStore(failsToDelete: true)
        let timerStore = InMemoryTimerStore(records: [.running(aliasID: 6, at: start), .running(aliasID: 7, at: start)])
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = AppModel(keyStore: keyStore, timerStore: timerStore, transport: transport, retry: .once)
        _ = try await model.signIn(apiKey: "valid-key")

        await #expect(throws: KeychainError.status(errSecInteractionNotAllowed)) {
            try await model.signOutAnyway()
        }

        #expect(keyStore.key == "valid-key")
        #expect(model.phase == .signedIn(Fixtures.userInfo))
        #expect(model.engine.records.map(\.aliasID) == [6, 7])
        #expect(timerStore.records.map(\.aliasID) == [6, 7])
    }

    @Test func disableAfterFinishingAfterSignOutStartsNoTimer() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        let timing = Task { await model.disableAfter(aliasID: 7, duration: .oneHour) }
        await transport.waitUntilARequestIsHeld()
        try await model.signOutAnyway()

        transport.release()
        let succeeded = await timing.value

        #expect(!succeeded)
        #expect(model.engine.records.isEmpty)
        #expect(timerStore.records.isEmpty)
        #expect(model.lastError == nil)
    }

    @Test func anEnableFinishingAfterSignOutShowsNoError() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let enabling = Task { await model.enable(aliasID: 7, for: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()
        try await model.signOutAnyway()

        transport.release()
        let succeeded = await enabling.value

        #expect(!succeeded)
        #expect(requestCount(path: "/api/aliases/7/toggle") == 2)
        #expect(model.engine.records.isEmpty)
        #expect(model.lastError == nil)
    }

    @Test func anEnableCutOffByAKeyReplacementSaysTheAliasWasDisabled() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let enabling = Task { await model.enable(aliasID: 7, for: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "replacement-key")

        transport.release()
        let succeeded = await enabling.value

        #expect(!succeeded)
        #expect(model.engine.records.isEmpty)
        #expect(model.lastError == "shop@example.com was enabled for the previous account and has been disabled.")
    }

    @Test func anEnableCutOffBySignOutThatCouldNotDisableAgainSaysSo() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        let enabling = Task { await model.enable(aliasID: 7, for: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()
        try await model.signOutAnyway()

        transport.release()
        let succeeded = await enabling.value

        #expect(!succeeded)
        #expect(model.lastError == "shop@example.com was enabled for the previous account and could not be disabled.")
    }

    @Test func disableAfterCutOffByAKeyReplacementSaysNoTimerStarted() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        let timing = Task { await model.disableAfter(aliasID: 7, duration: .oneHour) }
        await transport.waitUntilARequestIsHeld()
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "replacement-key")

        transport.release()
        let succeeded = await timing.value

        #expect(!succeeded)
        #expect(model.engine.records.isEmpty)
        #expect(timerStore.records.isEmpty)
        #expect(model.lastError == "shop@example.com belongs to the previous account, so no timer was started.")
    }

    @Test func signOutErrorsExplainWhichAliasesStayEnabled() {
        let one = SignOutError.aliasesStillEnabled([StillEnabledAlias(email: "a@example.com", problem: .unreachable)], pendingEnables: 0)
        #expect(one.title == "An Alias Is Still Enabled")
        #expect(one.userMessage == "a@example.com: SimpleLogin can't be reached\n\nIf you sign out anyway, it stays enabled.")

        let several = SignOutError.aliasesStillEnabled(
            [
                StillEnabledAlias(email: "a@example.com", problem: .refused),
                StillEnabledAlias(email: "b@example.com", problem: .keyRejected),
            ],
            pendingEnables: 1
        )
        #expect(several.title == "3 Aliases Are Still Enabled")
        #expect(several.userMessage == """
            a@example.com: the API key can't change it
            b@example.com: the API key was rejected
            1 alias being enabled or created right now

            If you sign out anyway, these aliases stay enabled.
            """)

        let onlyPending = SignOutError.aliasesStillEnabled([], pendingEnables: 1)
        #expect(onlyPending.title == "An Alias Is Still Enabled")
        #expect(onlyPending.userMessage == "1 alias being enabled or created right now\n\nIf you sign out anyway, it stays enabled.")

        let manyPending = SignOutError.aliasesStillEnabled([StillEnabledAlias(email: "a@example.com", problem: .notResponding(status: 503))], pendingEnables: 2)
        #expect(manyPending.userMessage.contains("a@example.com: SimpleLogin isn't responding\n2 aliases being enabled or created right now"))
        #expect(StillEnabledAlias(email: "a@example.com", problem: .other).reason == "SimpleLogin reported an error")

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
        let model = AppModel(keyStore: keyStore, timerStore: UnavailableTimerStore(reason: "test"), transport: transport, retry: .once)
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

    @Test func thePinnedListCountsAsLoadedOnceARefreshSucceeds() async throws {
        let model = try await signedInModel()
        #expect(model.menuState(at: clock.now).pinnedLoaded == false)

        await model.refreshPinned()
        #expect(model.menuState(at: clock.now).pinnedLoaded == false)

        transport.enqueue("/api/v2/aliases", json: #"{"aliases":[]}"#)
        await model.refreshPinned()
        #expect(model.menuState(at: clock.now).pinnedLoaded)
    }

    @Test func aKeyChangeForgetsThatThePinnedListLoaded() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))
        await model.refreshPinned()

        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "other-account-key")

        #expect(model.menuState(at: clock.now).pinnedLoaded == false)
    }

    @Test func signOutForgetsThatThePinnedListLoaded() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...3))
        await model.refreshPinned()

        try await model.signOut()

        #expect(model.menuState(at: clock.now).pinnedLoaded == false)
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

private extension StillEnabledAlias {
    static func shop(_ problem: DisableProblem) -> StillEnabledAlias {
        StillEnabledAlias(email: "shop@example.com", problem: problem)
    }
}
