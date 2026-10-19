import Foundation
import Testing
import SimpleLoginKit
@testable import SimpleLoginMac

/// The menu's alias actions: enabling for a while, extending, disabling, and copying.
@MainActor
struct AliasActionsTests {
    let keyStore = InMemoryAPIKeyStore()
    let timerStore: any TimerStore
    let transport = StubTransport()
    let clock = TestClock()

    init(records: [TimerRecord] = [], timerStore: (any TimerStore)? = nil) {
        self.timerStore = timerStore ?? InMemoryTimerStore(records: records)
    }

    func makeModel(
        copyToClipboard: @escaping @MainActor (String) -> Void = { _ in },
        disableBudget: Duration = .seconds(5)
    ) -> AppModel {
        let clock = clock
        return AppModel(
            keyStore: keyStore,
            timerStore: timerStore,
            transport: transport,
            now: { clock.now },
            copyToClipboard: copyToClipboard,
            disableBudget: disableBudget
        )
    }

    /// Signs in and loads the given aliases as the pinned list.
    func signedInModel(pinned aliases: [String] = [], disableBudget: Duration = .seconds(5)) async throws -> AppModel {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = makeModel(disableBudget: disableBudget)
        _ = try await model.signIn(apiKey: "valid-key")
        transport.enqueue("/api/v2/aliases", json: #"{"aliases":[\#(aliases.joined(separator: ","))]}"#)
        await model.refreshPinned()
        return model
    }

    func requestCount(path: String) -> Int {
        transport.requests.filter { $0.url?.path == path }.count
    }

    func runningRecord(aliasID: Int) -> TimerRecord {
        TimerRecord(aliasID: aliasID, email: "shop@example.com", enabledAt: clock.now.addingTimeInterval(-10), expiresAt: clock.now.addingTimeInterval(290))
    }

    @Test func enableTurnsOnADisabledAliasAndShowsItAsTimed() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))

        await model.enable(aliasID: 7, for: .fiveMinutes)

        #expect(requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.engine.record(for: 7)?.expiresAt == clock.now.addingTimeInterval(300))
        #expect(model.pinned.first?.enabled == true)
        #expect(model.menuSections.pinned == [MenuAliasItem(id: 7, email: "shop@example.com", state: .timed(remaining: 300))])
        #expect(model.lastError == nil)
    }

    @Test func enableShowsWhyItFailed() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])

        await model.enable(aliasID: 7, for: .fiveMinutes)

        #expect(model.lastError == "Could not reach SimpleLogin. Check your network connection.")
        #expect(model.engine.record(for: 7) == nil)
        #expect(model.menuSections.pinned.first?.state == .disabled)
    }

    @Test func enableWhileSignedOutExplainsThatSetupIsMissing() async {
        let model = makeModel()
        model.start()

        await model.enable(aliasID: 7, for: .fiveMinutes)

        #expect(model.lastError == "Not signed in. Set up your API key first.")
    }

    @Test func enableReportsAToggleThatDidNotTakeEffect() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.enable(aliasID: 7, for: .fiveMinutes)

        #expect(model.lastError == "The alias did not change. Try again.")
    }

    @Test func aSuccessfulActionClearsThePreviousError() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])
        await model.enable(aliasID: 7, for: .fiveMinutes)
        #expect(model.lastError != nil)
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))

        await model.enable(aliasID: 7, for: .fiveMinutes)

        #expect(model.lastError == nil)
    }

    @Test func aRepeatedActionOnTheSameAliasIsIgnoredWhileTheFirstRuns() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        let first = Task { await model.enable(aliasID: 7, for: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()
        #expect(model.isBusy(aliasID: 7))

        await model.enable(aliasID: 7, for: .fiveMinutes)
        await model.disableNow(aliasID: 7)
        transport.release()
        _ = await first.value

        #expect(requestCount(path: "/api/aliases/7") == 1)
        #expect(requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.isBusy(aliasID: 7) == false)
        #expect(model.menuSections.pinned.first?.state == .timed(remaining: 300))
    }

    @Test func signingInWithANewKeyClearsTheLastError() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])
        await model.enable(aliasID: 7, for: .fiveMinutes)
        #expect(model.lastError != nil)

        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "replacement-key")

        #expect(model.lastError == nil)
    }

    @Test func extendCountsTheNewDurationFromNow() async throws {
        let test = AliasActionsTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7)])
        test.clock.advance(by: 100)

        model.extend(aliasID: 7, by: .oneHour)

        #expect(model.engine.record(for: 7)?.expiresAt == test.clock.now.addingTimeInterval(3600))
        #expect(model.lastError == nil)
    }

    @Test func extendWithUnreadableTimerDataShowsWhyItFailed() async throws {
        let test = AliasActionsTests(timerStore: UnavailableTimerStore(reason: "test"))
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7)])

        model.extend(aliasID: 7, by: .oneHour)

        #expect(model.lastError == "Timer data is unreadable, so timers can't be started or changed.")
    }

    @Test func disableNowTurnsOffATimedAliasAndShowsItAsDisabled() async throws {
        let test = AliasActionsTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.disableNow(aliasID: 7)

        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.engine.record(for: 7) == nil)
        #expect(model.pinned.first?.enabled == false)
        #expect(model.menuSections.pinned == [MenuAliasItem(id: 7, email: "shop@example.com", state: .disabled)])
        #expect(model.lastError == nil)
    }

    @Test func disableNowShowsWhyItFailedAndKeepsTheAliasEnabled() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)

        await model.disableNow(aliasID: 7)

        #expect(model.lastError == "The API key was rejected. Please sign in again.")
        #expect(model.menuSections.pinned.first?.state == .enabled)
    }

    @Test func disableNowReportsTheDisabledAlias() async throws {
        let test = AliasActionsTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        var disabledAliasIDs: [Int] = []
        model.onAliasDisabled = { disabledAliasIDs.append($0) }

        await model.disableNow(aliasID: 7)

        #expect(disabledAliasIDs == [7])
    }

    @Test func aFailedDisableNowReportsNothing() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.enqueue("/api/aliases/7", status: 401, json: #"{"error":"Wrong api key"}"#)
        var disabledAliasIDs: [Int] = []
        model.onAliasDisabled = { disabledAliasIDs.append($0) }

        await model.disableNow(aliasID: 7)

        #expect(disabledAliasIDs.isEmpty)
    }

    @Test func aRefreshStartedBeforeAnActionKeepsTheActionsResult() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.holdNext("/api/v2/aliases", json: #"{"aliases":[\#(Fixtures.aliasJSON(id: 7, enabled: true))]}"#)
        let refresh = Task { await model.refreshPinned() }
        await transport.waitUntilARequestIsHeld()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.disableNow(aliasID: 7)
        transport.release()
        await refresh.value

        #expect(model.menuSections.pinned.first?.state == .disabled)
    }

    @Test func disableAfterTimesAnEnabledAliasWithoutTogglingIt() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))

        let succeeded = await model.disableAfter(aliasID: 7, duration: .oneHour)

        let record = model.engine.record(for: 7)
        #expect(succeeded)
        #expect(record?.enabledAt == clock.now)
        #expect(record?.expiresAt == clock.now.addingTimeInterval(3600))
        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(model.menuSections.pinned.first?.state == .timed(remaining: 3600))
        #expect(model.lastError == nil)
    }

    @Test func disableAfterLeavesAnAliasDisabledElsewhereDisabled() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))

        let succeeded = await model.disableAfter(aliasID: 7, duration: .oneHour)

        #expect(succeeded == false)
        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(model.engine.record(for: 7) == nil)
        #expect(model.menuSections.pinned.first?.state == .disabled)
        #expect(model.lastError == "shop@example.com is already disabled.")
    }

    @Test func disableAfterShowsWhyTheAliasCouldNotBeChecked() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])

        let succeeded = await model.disableAfter(aliasID: 7, duration: .oneHour)

        #expect(succeeded == false)
        #expect(model.engine.record(for: 7) == nil)
        #expect(model.lastError == "Could not reach SimpleLogin. Check your network connection.")
    }

    @Test func disableAfterWithAFailingSaveShowsTheSystemReason() async throws {
        let test = AliasActionsTests(timerStore: InMemoryTimerStore(failsToSave: true))
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))

        await model.disableAfter(aliasID: 7, duration: .oneHour)

        #expect(model.lastError == CocoaError(.fileWriteNoPermission).localizedDescription)
    }

    @Test func pinningSavesThePinAndReloadsTheMenusList() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", method: "PATCH", json: "{}")
        transport.enqueue("/api/v2/aliases", json: #"{"aliases":[\#(Fixtures.aliasJSON(id: 7, email: "server@example.com"))]}"#)

        let succeeded = await model.setPinned(true, alias: Fixtures.alias(id: 7))

        let patch = try #require(transport.requests.first { $0.httpMethod == "PATCH" })
        let patchBody = try #require(patch.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: patchBody) as? [String: Any])
        #expect(succeeded)
        #expect(patch.url?.path == "/api/aliases/7")
        #expect(body["pinned"] as? Bool == true)
        #expect(model.pinned.map(\.email) == ["server@example.com"])
        #expect(model.lastError == nil)
    }

    @Test func aPinnedAliasAppearsInTheMenuEvenWhenReloadingFails() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", method: "PATCH", json: "{}")

        await model.setPinned(true, alias: Fixtures.alias(id: 7))

        #expect(model.pinned.map(\.id) == [7])
        #expect(model.pinned.first?.pinned == true)
    }

    @Test func anUnpinnedAliasLeavesTheMenuEvenWhenReloadingFails() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7), Fixtures.aliasJSON(id: 8)])
        transport.enqueue("/api/aliases/7", method: "PATCH", json: "{}")

        await model.setPinned(false, alias: try #require(model.pinned.first))

        #expect(model.pinned.map(\.id) == [8])
    }

    @Test func aRejectedPinShowsWhyAndKeepsTheMenusList() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", method: "PATCH", status: 400, json: #"{"error":"Alias not found"}"#)

        let succeeded = await model.setPinned(true, alias: Fixtures.alias(id: 7))

        #expect(succeeded == false)
        #expect(model.lastError == "Alias not found")
        #expect(model.pinned.isEmpty)
        #expect(requestCount(path: "/api/v2/aliases") == 1)
    }

    @Test func pinningWhileSignedOutExplainsThatSetupIsMissing() async {
        let model = makeModel()
        model.start()

        let succeeded = await model.setPinned(true, alias: Fixtures.alias(id: 7))

        #expect(succeeded == false)
        #expect(model.lastError == "Not signed in. Set up your API key first.")
    }

    @Test func enablePermanentlyTurnsOnADisabledAliasWithoutATimer() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))

        let succeeded = await model.enablePermanently(aliasID: 7)

        #expect(succeeded)
        #expect(requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.engine.records.isEmpty)
        #expect(model.menuSections.pinned.first?.state == .enabled)
        #expect(model.lastError == nil)
    }

    @Test func enablePermanentlyLeavesAnEnabledAliasAlone() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))

        let succeeded = await model.enablePermanently(aliasID: 7)

        #expect(succeeded)
        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
    }

    @Test func enablePermanentlyShowsWhyItFailed() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])

        let succeeded = await model.enablePermanently(aliasID: 7)

        #expect(succeeded == false)
        #expect(model.lastError == "Could not reach SimpleLogin. Check your network connection.")
        #expect(model.menuSections.pinned.first?.state == .disabled)
    }

    @Test func enablePermanentlyIsIgnoredWhileAnotherActionOnTheAliasRuns() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        let enable = Task { await model.enable(aliasID: 7, for: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()

        let succeeded = await model.enablePermanently(aliasID: 7)
        transport.release()
        _ = await enable.value

        #expect(succeeded == false)
        #expect(requestCount(path: "/api/aliases/7") == 1)
    }

    @Test func keepEnabledStopsTheTimerAndLeavesTheAliasEnabled() async throws {
        let test = AliasActionsTests(records: [runningRecord(aliasID: 7)])
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])

        let succeeded = await model.keepEnabled(aliasID: 7, email: "shop@example.com")

        #expect(succeeded)
        #expect(model.engine.record(for: 7) == nil)
        #expect(test.requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(model.menuSections.pinned.first?.state == .enabled)
        #expect(model.lastError == nil)
    }

    @Test func keepEnabledAfterTheTimerEndedShowsTheAliasAsDisabled() async throws {
        let model = try await signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: true)])

        let succeeded = await model.keepEnabled(aliasID: 7, email: "shop@example.com")

        #expect(succeeded == false)
        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(model.menuSections.pinned.first?.state == .disabled)
        #expect(model.lastError == "shop@example.com was already disabled.")
    }

    @Test func keepEnabledWithUnreadableTimerDataShowsWhy() async throws {
        let test = AliasActionsTests(timerStore: UnavailableTimerStore(reason: "test"))
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7)])

        let succeeded = await model.keepEnabled(aliasID: 7, email: "shop@example.com")

        #expect(succeeded == false)
        #expect(model.lastError == "Timer data is unreadable, so timers can't be started or changed.")
    }

    @Test func keepEnabledWhileTheTimerIsExpiringShowsWhy() async throws {
        let expiring = TimerRecord(aliasID: 7, email: "shop@example.com", enabledAt: clock.now.addingTimeInterval(-300), expiresAt: clock.now)
        let test = AliasActionsTests(records: [expiring])
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7)])
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        test.transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let expiry = Task { await model.tick() }
        await test.transport.waitUntilARequestIsHeld()

        let succeeded = await model.keepEnabled(aliasID: 7, email: "shop@example.com")
        test.transport.release()
        await expiry.value

        #expect(succeeded == false)
        #expect(model.lastError == "The alias is being disabled right now. Try again in a moment.")
    }

    // MARK: Quitting or signing out while an alias is being enabled

    /// Holds the enable's first read, and answers the enable and a later disable of the alias.
    func holdEnablingAlias7ThenAllowDisablingIt() {
        transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
    }

    @Test func quittingIsDeferredWhileAnEnableRuns() async throws {
        let model = try await signedInModel()
        holdEnablingAlias7ThenAllowDisablingIt()
        let enable = Task { await model.enable(aliasID: 7, for: .oneHour) }
        await transport.waitUntilARequestIsHeld()

        #expect(model.needsToDisableBeforeQuitting)

        transport.release()
        _ = await enable.value
    }

    @Test func quittingWhileAnEnableRunsDisablesTheAliasOnceItIsEnabled() async throws {
        let model = try await signedInModel()
        holdEnablingAlias7ThenAllowDisablingIt()
        let enable = Task { await model.enable(aliasID: 7, for: .oneHour) }
        await transport.waitUntilARequestIsHeld()

        let quit = Task { await model.prepareForTermination() }
        for _ in 0..<20 { await Task.yield() }
        transport.release()
        _ = await enable.value
        await quit.value

        #expect(requestCount(path: "/api/aliases/7/toggle") == 2)
        #expect(model.engine.records.isEmpty)
    }

    @Test func signingOutWhileAnEnableRunsDisablesTheAliasOnceItIsEnabled() async throws {
        let model = try await signedInModel()
        holdEnablingAlias7ThenAllowDisablingIt()
        let enable = Task { await model.enable(aliasID: 7, for: .oneHour) }
        await transport.waitUntilARequestIsHeld()

        let signOut = Task { try await model.signOut() }
        for _ in 0..<20 { await Task.yield() }
        transport.release()
        _ = await enable.value
        try await signOut.value

        #expect(requestCount(path: "/api/aliases/7/toggle") == 2)
        #expect(model.engine.records.isEmpty)
        #expect(keyStore.key == nil)
    }

    @Test func quittingStopsWaitingForAnEnableWhenTheBudgetRunsOut() async throws {
        let model = try await signedInModel(disableBudget: .milliseconds(50))
        holdEnablingAlias7ThenAllowDisablingIt()
        let enable = Task { await model.enable(aliasID: 7, for: .oneHour) }
        await transport.waitUntilARequestIsHeld()

        await model.prepareForTermination()

        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        transport.release()
        _ = await enable.value
    }

    @Test func copyPutsTheEmailOnTheClipboard() {
        var copied: [String] = []
        let model = makeModel { copied.append($0) }

        model.copy(email: "shop@example.com")

        #expect(copied == ["shop@example.com"])
    }

    @Test func menuSectionsShowTimedUnpinnedAliasesApartFromPinnedOnes() async throws {
        let unpinnedRecord = TimerRecord(aliasID: 9, email: "temp@example.com", enabledAt: clock.now, expiresAt: clock.now.addingTimeInterval(60))
        let test = AliasActionsTests(records: [unpinnedRecord])
        let model = try await test.signedInModel(pinned: [Fixtures.aliasJSON(id: 7, enabled: false)])
        test.clock.advance(by: 20)

        await model.tick()

        #expect(model.menuSections.timedUnpinned == [MenuAliasItem(id: 9, email: "temp@example.com", state: .timed(remaining: 40))])
        #expect(model.menuSections.pinned == [MenuAliasItem(id: 7, email: "shop@example.com", state: .disabled)])
    }

    @Test func keepingPinnedFreshLoadsTheListRightAway() async throws {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = makeModel()
        _ = try await model.signIn(apiKey: "valid-key")
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...2))

        let refresh = Task { await model.keepPinnedFresh() }
        let deadline = ContinuousClock.now + .seconds(2)
        while model.pinned.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        refresh.cancel()
        await refresh.value

        #expect(model.pinned.map(\.id) == [1, 2])
    }

    @Test func keepingPinnedFreshWhileSignedOutRequestsNothing() async {
        let model = makeModel()
        model.start()

        await model.keepPinnedFresh()

        #expect(transport.requests.isEmpty)
    }
}
