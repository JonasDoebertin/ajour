import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

/// Creating and disabling aliases from outside the menu: copying without announcing, joining expiry, and failing quietly.
@MainActor
final class ActionCreateAndDisableTests {
    let timerStore: any TimerStore
    let transport = StubTransport()
    let clock = TestClock()
    private(set) var copied: [String] = []
    private(set) var announced: [String] = []

    init(records: [TimerRecord] = []) {
        timerStore = InMemoryTimerStore(records: records)
    }

    func makeModel() -> AppModel {
        let clock = clock
        let model = AppModel(
            keyStore: InMemoryAPIKeyStore(),
            timerStore: timerStore,
            transport: transport,
            now: { clock.now },
            copyToClipboard: { [weak self] in self?.copied.append($0) },
            retry: .once
        )
        model.onNewAliasCopied = { [weak self] in self?.announced.append($0) }
        return model
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

    func enqueueRandomAlias() {
        transport.enqueue("/api/alias/random/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
    }

    func runningRecord(aliasID: Int) -> TimerRecord {
        TimerRecord(aliasID: aliasID, email: "shop@example.com", enabledAt: clock.now.addingTimeInterval(-10), expiresAt: clock.now.addingTimeInterval(290))
    }

    func expiredRecord(aliasID: Int) -> TimerRecord {
        TimerRecord(aliasID: aliasID, email: "shop@example.com", enabledAt: clock.now.addingTimeInterval(-360), expiresAt: clock.now.addingTimeInterval(-60))
    }

    @Test func actionCreationCopiesWithoutAnnouncing() async throws {
        let model = try await signedInModel()
        enqueueRandomAlias()

        let alias = try await model.createRandomAliasAndCopy(expiringAfter: nil)

        #expect(alias.email == "random@example.com")
        #expect(copied == ["random@example.com"])
        #expect(announced == [])
        #expect(model.engine.records.isEmpty)
        #expect(!model.isEnabling)
    }

    @Test func menuCreationStillAnnounces() async throws {
        let model = try await signedInModel()
        enqueueRandomAlias()

        await model.createRandomAlias(expiringAfter: nil)

        #expect(copied == ["random@example.com"])
        #expect(announced == ["random@example.com"])
    }

    @Test func actionCreationWithExpiryStartsTheTimerFirst() async throws {
        let model = try await signedInModel()
        enqueueRandomAlias()

        _ = try await model.createRandomAliasAndCopy(expiringAfter: .oneHour)

        #expect(model.engine.record(for: 42)?.expiresAt == clock.now.addingTimeInterval(3600))
        #expect(copied == ["random@example.com"])
        #expect(announced == [])
    }

    @Test func actionCreationLeavesTheMenuErrorAlone() async throws {
        let model = try await signedInModel()

        let error = await #expect(throws: APIError.self) {
            try await model.createRandomAliasAndCopy(expiringAfter: nil)
        }

        guard case .transport = error else {
            Issue.record("Expected a transport error, got \(String(describing: error))")
            return
        }
        #expect(model.lastError == nil)
        #expect(copied.isEmpty)
    }

    @Test func cancellingTheCallerStillFinishesTheCreation() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/alias/random/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        let creating = Task { try await model.createRandomAliasAndCopy(expiringAfter: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()

        creating.cancel()
        transport.release()
        _ = await creating.result

        #expect(model.engine.record(for: 42) != nil)
        #expect(copied == ["random@example.com"])
    }

    @Test func creationIsRefusedOnceQuittingStarts() async throws {
        let test = ActionCreateAndDisableTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.holdNext("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let quit = Task { await model.prepareForTermination() }
        await test.transport.waitUntilARequestIsHeld()
        test.enqueueRandomAlias()

        await #expect(throws: AliasActionError.quitting) {
            try await model.createRandomAliasAndCopy(expiringAfter: .oneHour)
        }
        test.transport.release()
        await quit.value

        #expect(test.requestCount(path: "/api/alias/random/new") == 0)
        #expect(test.copied.isEmpty)
        #expect(test.announced.isEmpty)
    }

    @Test func aCreationCountsAsInFlightUntilItEnds() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/alias/random/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        let creating = Task { try await model.createRandomAliasAndCopy(expiringAfter: nil) }
        await transport.waitUntilARequestIsHeld()

        #expect(model.isEnabling)
        #expect(model.needsToDisableBeforeQuitting)

        transport.release()
        _ = try await creating.value

        #expect(!model.isEnabling)
        #expect(!model.needsToDisableBeforeQuitting)
    }

    @Test func disableTurnsOffATimedAlias() async throws {
        let test = ActionCreateAndDisableTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        try await model.disable(aliasID: 7, email: "shop@example.com")

        #expect(model.engine.record(for: 7) == nil)
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.knownEnabled(aliasID: 7, since: 0) == false)
        #expect(model.change(aliasID: 7) == nil)
        #expect(test.copied.isEmpty)
    }

    @Test func disablingADisabledAliasSucceeds() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))

        try await model.disable(aliasID: 7, email: "shop@example.com")

        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(model.lastError == nil)
    }

    @Test func disableJoinsARunningExpiryDisable() async throws {
        let test = ActionCreateAndDisableTests(records: [expiredRecord(aliasID: 7)])
        let model = try await test.signedInModel()
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.holdNext("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let expiry = Task { await model.tick() }
        await test.transport.waitUntilARequestIsHeld()

        let disabling = Task { try await model.disable(aliasID: 7, email: "shop@example.com") }
        for _ in 0..<20 { await Task.yield() }
        test.transport.release()

        try await disabling.value
        await expiry.value
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.engine.record(for: 7) == nil)
    }

    @Test func disableFailsAsBusyDuringAMenuAction() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.holdNext("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        let enabling = Task { await model.enable(aliasID: 7, for: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()

        await #expect(throws: AliasActionError.busy(email: "shop@example.com")) {
            try await model.disable(aliasID: 7, email: "shop@example.com")
        }
        transport.release()
        _ = await enabling.value

        #expect(requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.engine.record(for: 7) != nil)
    }
}
