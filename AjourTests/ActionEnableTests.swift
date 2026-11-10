import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

/// Enabling an alias from outside the menu: timing it, copying it, and failing without touching the menu's error.
@MainActor
final class ActionEnableTests {
    let timerStore: any TimerStore
    let transport = StubTransport()
    let clock = TestClock()
    private(set) var copied: [String] = []

    init(records: [TimerRecord] = [], timerStore: (any TimerStore)? = nil) {
        self.timerStore = timerStore ?? InMemoryTimerStore(records: records)
    }

    func makeModel() -> AppModel {
        let clock = clock
        return AppModel(
            keyStore: InMemoryAPIKeyStore(),
            timerStore: timerStore,
            transport: transport,
            now: { clock.now },
            copyToClipboard: { [weak self] in self?.copied.append($0) },
            retry: .once
        )
    }

    func signedInModel() async throws -> AppModel {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = makeModel()
        _ = try await model.signIn(apiKey: "valid-key")
        return model
    }

    func requestCount(path: String) -> Int {
        transport.requests.filter { $0.url?.path == path }.count
    }

    func runningRecord(aliasID: Int) -> TimerRecord {
        TimerRecord(aliasID: aliasID, email: "shop@example.com", enabledAt: clock.now.addingTimeInterval(-10), expiresAt: clock.now.addingTimeInterval(290))
    }

    func expiredRecord(aliasID: Int) -> TimerRecord {
        TimerRecord(aliasID: aliasID, email: "shop@example.com", enabledAt: clock.now.addingTimeInterval(-360), expiresAt: clock.now.addingTimeInterval(-60))
    }

    func enqueueDisabledAliasThatTurnsOn() {
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
    }

    @Test func enablingADisabledAliasStartsATimerAndCopies() async throws {
        let model = try await signedInModel()
        enqueueDisabledAliasThatTurnsOn()

        let enabled = try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)

        #expect(enabled == EnabledAlias(email: "shop@example.com", outcome: .enabled))
        #expect(copied == ["shop@example.com"])
        #expect(model.engine.record(for: 7)?.expiresAt == clock.now.addingTimeInterval(3600))
        #expect(requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.knownEnabled(aliasID: 7, since: 0) == true)
        #expect(model.change(aliasID: 7) == nil)
        #expect(!model.isEnabling)
    }

    @Test func enablingATimedAliasExtendsWithoutToggling() async throws {
        let test = ActionEnableTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))

        let enabled = try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)

        #expect(enabled.outcome == .extended)
        #expect(model.engine.record(for: 7)?.expiresAt == test.clock.now.addingTimeInterval(3600))
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(test.copied == ["shop@example.com"])
    }

    @Test func enablingATimedAliasDisabledElsewhereTurnsItBackOn() async throws {
        let test = ActionEnableTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.enqueueDisabledAliasThatTurnsOn()

        let enabled = try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)

        #expect(enabled.outcome == .enabled)
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.engine.record(for: 7)?.expiresAt == test.clock.now.addingTimeInterval(3600))
        #expect(test.copied == ["shop@example.com"])
    }

    @Test func enablingAPermanentlyEnabledAliasLeavesItUntimed() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))

        let enabled = try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)

        #expect(enabled.outcome == .alreadyEnabled)
        #expect(model.engine.record(for: 7) == nil)
        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(copied == ["shop@example.com"])
    }

    @Test func theCopiedAddressIsTheCurrentOne() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, email: "renamed@example.com", enabled: true))

        let enabled = try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)

        #expect(enabled.email == "renamed@example.com")
        #expect(copied == ["renamed@example.com"])
    }

    @Test func enableFailsAsBusyWhileTheAliasChanges() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.holdNext("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let disabling = Task { await model.disableNow(aliasID: 7) }
        await transport.waitUntilARequestIsHeld()

        await #expect(throws: AliasActionError.busy(email: "shop@example.com")) {
            try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)
        }
        transport.release()
        _ = await disabling.value

        #expect(copied.isEmpty)
    }

    @Test func enableFailsAsBusyDuringAnExpiryDisable() async throws {
        let test = ActionEnableTests(records: [expiredRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.holdNext("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let expiry = Task { await model.tick() }
        await test.transport.waitUntilARequestIsHeld()

        await #expect(throws: AliasActionError.busy(email: "shop@example.com")) {
            try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)
        }
        test.transport.release()
        await expiry.value

        #expect(model.engine.record(for: 7) == nil)
        #expect(test.copied.isEmpty)
    }

    @Test func enableFailsAsBusyWhenAnExpiryDisableStartsDuringTheRead() async throws {
        let test = ActionEnableTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.holdNext("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let enabling = Task { try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour) }
        await test.transport.waitUntilARequestIsHeld()
        test.clock.advance(by: 300)
        let expiry = Task { await model.tick() }
        while test.transport.heldRequestCount < 2 { await Task.yield() }

        test.transport.release()

        await #expect(throws: AliasActionError.busy(email: "shop@example.com")) { try await enabling.value }
        await expiry.value
        #expect(model.engine.record(for: 7) == nil)
        #expect(test.copied.isEmpty)
    }

    @Test func enableFailsAsBusyWhenAnExpiryDisableEndsDuringTheRead() async throws {
        let test = ActionEnableTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let enabling = Task { try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour) }
        await test.transport.waitUntilARequestIsHeld()
        test.clock.advance(by: 300)
        await model.tick()

        test.transport.release()

        await #expect(throws: AliasActionError.busy(email: "shop@example.com")) { try await enabling.value }
        #expect(model.engine.record(for: 7) == nil)
        #expect(test.copied.isEmpty)
    }

    @Test func enablingADeletedAliasSaysItIsGone() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", status: 404, json: #"{"error":"Alias not found"}"#)

        await #expect(throws: AliasActionError.gone(email: "shop@example.com")) {
            try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)
        }
        #expect(copied.isEmpty)
    }

    @Test func enableWithUnreadableTimersChangesNothing() async throws {
        let test = ActionEnableTests(timerStore: UnavailableTimerStore(reason: "test"))
        let model = try await test.signedInModel()
        test.enqueueDisabledAliasThatTurnsOn()

        await #expect(throws: TimerEngineError.storeUnavailable) {
            try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)
        }
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(test.copied.isEmpty)
    }

    @Test func enableSignedOutFails() async {
        let model = makeModel()
        model.start()

        await #expect(throws: TimerEngineError.notSignedIn) {
            try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)
        }
    }

    @Test func enableForAnAccountReplacedMeanwhileStartsNoTimer() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        let enabling = Task { try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour) }
        await transport.waitUntilARequestIsHeld()
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "replacement-key")

        transport.release()

        await #expect(throws: AliasActionError.timerNotStartedForPreviousAccount(email: "shop@example.com")) {
            try await enabling.value
        }
        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(model.engine.record(for: 7) == nil)
        #expect(copied.isEmpty)
    }

    @Test func enableLeavesTheMenuErrorAlone() async throws {
        let model = try await signedInModel()
        await model.enable(aliasID: 7, for: .fiveMinutes)
        let menuError = try #require(model.lastError)
        enqueueDisabledAliasThatTurnsOn()

        _ = try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)

        #expect(model.lastError == menuError)

        let freshTest = ActionEnableTests()
        let fresh = try await freshTest.signedInModel()
        await #expect(throws: (any Error).self) {
            try await fresh.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour)
        }
        #expect(fresh.lastError == nil)
    }

    @Test func cancellingTheCallerStillFinishesTheEnable() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.holdNext("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        let enabling = Task { try await model.enableAndCopy(aliasID: 7, email: "shop@example.com", for: .oneHour) }
        await transport.waitUntilARequestIsHeld()

        enabling.cancel()
        transport.release()
        _ = await enabling.result

        #expect(model.engine.record(for: 7) != nil)
        #expect(copied == ["shop@example.com"])
    }

    @Test func enableIsRefusedOnceQuittingStarts() async throws {
        let test = ActionEnableTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.holdNext("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let quit = Task { await model.prepareForTermination() }
        await test.transport.waitUntilARequestIsHeld()
        test.transport.enqueue("/api/aliases/9", json: Fixtures.aliasJSON(id: 9, enabled: false))
        test.transport.enqueue("/api/aliases/9", json: Fixtures.aliasJSON(id: 9, enabled: false))
        test.transport.enqueue("/api/aliases/9/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))

        await #expect(throws: AliasActionError.quitting) {
            try await model.enableAndCopy(aliasID: 9, email: "later@example.com", for: .oneHour)
        }
        test.transport.release()
        await quit.value

        #expect(test.requestCount(path: "/api/aliases/9/toggle") == 0)
        #expect(model.engine.record(for: 9) == nil)
        #expect(test.copied.isEmpty)
    }

    @Test func waitingForLaunchReturnsOnceStarted() async throws {
        let model = makeModel()
        let waiting = Task { try await model.waitUntilLoaded() }
        await Task.yield()

        model.start()

        try await waiting.value
        #expect(model.phase == .signedOut)
    }

    @Test func waitingForLaunchGivesUp() async {
        let model = makeModel()

        await #expect(throws: AliasActionError.notReady) {
            try await model.waitUntilLoaded(within: .milliseconds(50))
        }
    }

    @Test func newActionErrorsHaveMessages() {
        #expect(AppModel.userMessage(for: AliasActionError.busy(email: "shop@example.com")) == "shop@example.com is busy. Try again in a moment.")
        #expect(AppModel.userMessage(for: AliasActionError.gone(email: "shop@example.com")) == "shop@example.com no longer exists.")
        #expect(AppModel.userMessage(for: AliasActionError.notReady) == "Ajour isn't ready yet. Try again in a moment.")
        #expect(AppModel.userMessage(for: AliasActionError.quitting) == "Ajour is quitting.")
    }
}
