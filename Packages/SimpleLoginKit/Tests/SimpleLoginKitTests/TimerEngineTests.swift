import Foundation
import Testing
@testable import SimpleLoginKit

final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor @Suite struct TimerEngineTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let clock: TestClock
    private let store = InMemoryTimerStore()
    private let api: FakeAliasAPI

    init() {
        clock = TestClock(t0)
        api = FakeAliasAPI(aliases: [
            .fixture(id: 1, email: "one@example.com", enabled: false),
            .fixture(id: 2, email: "two@example.com", enabled: false),
        ])
    }

    private func makeEngine(
        store: InMemoryTimerStore? = nil,
        signedIn: Bool = true,
        retry: RetryPolicy = .once
    ) -> TimerEngine {
        let clock = clock
        let engine = TimerEngine(store: store ?? self.store, now: { clock.now }, retry: retry)
        if signedIn {
            engine.api = api
        }
        return engine
    }

    private func makeEngineWithGatedAPI() async throws -> (TimerEngine, GatedAliasAPI) {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        let gated = GatedAliasAPI(base: api)
        engine.api = gated
        return (engine, gated)
    }

    private func yieldRepeatedly() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    // MARK: - Enabling and extending

    @Test func enableCreatesRecordWithExpiry() async throws {
        let engine = makeEngine()

        let record = try await engine.enable(aliasID: 1, for: .fiveMinutes)

        #expect(record == TimerRecord(
            aliasID: 1,
            email: "one@example.com",
            enabledAt: t0,
            expiresAt: t0.addingTimeInterval(300)
        ))
        #expect(api.aliases[1]?.enabled == true)
        #expect(store.records == [record])
        #expect(engine.records == [record])
        #expect(engine.record(for: 1) == record)
        #expect(engine.hasActiveTimers)
    }

    @Test func enableExistingRecordExtendsInsteadOfDuplicating() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        clock.advance(by: 60)

        let record = try await engine.enable(aliasID: 1, for: .oneHour)

        #expect(record.enabledAt == t0)
        #expect(record.expiresAt == t0.addingTimeInterval(60 + 3600))
        #expect(engine.records == [record])
        #expect(store.records == [record])
        #expect(api.toggleCalls == [1])
    }

    @Test func extendKeepsEnabledAtAndLastNotified() throws {
        let lastNotified = t0.addingTimeInterval(30)
        let existing = TimerRecord(
            aliasID: 1,
            email: "one@example.com",
            enabledAt: t0,
            expiresAt: t0.addingTimeInterval(300),
            lastNotifiedActivityTimestamp: lastNotified
        )
        let store = InMemoryTimerStore(records: [existing])
        let engine = makeEngine(store: store)
        clock.advance(by: 120)

        try engine.extend(aliasID: 1, by: .twentyFourHours)

        let expected = TimerRecord(
            aliasID: 1,
            email: "one@example.com",
            enabledAt: t0,
            expiresAt: t0.addingTimeInterval(120 + 86400),
            lastNotifiedActivityTimestamp: lastNotified
        )
        #expect(engine.record(for: 1) == expected)
        #expect(store.records == [expected])
    }

    @Test func startTimerTracksAlreadyEnabledAliasWithoutAPICall() throws {
        let engine = makeEngine(signedIn: false)

        let record = try engine.startTimer(for: .fixture(id: 9, email: "new@example.com", enabled: true), duration: .oneHour)

        #expect(record == TimerRecord(
            aliasID: 9,
            email: "new@example.com",
            enabledAt: t0,
            expiresAt: t0.addingTimeInterval(3600)
        ))
        #expect(store.records == [record])
        #expect(api.toggleCalls.isEmpty)
    }

    // MARK: - Disabling manually

    @Test func disableNowDisablesAliasAndRemovesRecord() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)

        try await engine.disableNow(aliasID: 1)

        #expect(api.aliases[1]?.enabled == false)
        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
        #expect(!engine.hasActiveTimers)
    }

    @Test func disableNowFailureKeepsRecord() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.transport("offline")]

        await #expect(throws: APIError.transport("offline")) {
            try await engine.disableNow(aliasID: 1)
        }

        #expect(engine.record(for: 1) != nil)
        #expect(store.records.count == 1)
    }

    // MARK: - Keeping enabled

    @Test func cancelTimerStopsTrackingAndLeavesTheAliasEnabled() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)

        try engine.cancelTimer(aliasID: 1)

        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
        #expect(api.aliases[1]?.enabled == true)
        #expect(api.toggleCalls == [1])
    }

    @Test func cancelTimerForgetsAFailedDisable() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)
        _ = await engine.processDue()
        #expect(engine.failures[1] != nil)

        try engine.cancelTimer(aliasID: 1)

        #expect(engine.failures.isEmpty)
        #expect(engine.nextDueDate() == nil)
    }

    @Test func cancelTimerWithUnreadableTimerDataIsRefused() {
        let engine = makeEngine(store: InMemoryTimerStore(records: [], failLoad: true))

        #expect(throws: TimerEngineError.storeUnavailable) {
            try engine.cancelTimer(aliasID: 1)
        }
    }

    @Test func cancelTimerIsRefusedWhileTheAliasIsBeingDisabled() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        clock.advance(by: 300)
        async let events = engine.processDue()
        await gated.waitUntilHolding(1)

        #expect(throws: TimerEngineError.disableInProgress) {
            try engine.cancelTimer(aliasID: 1)
        }
        #expect(engine.record(for: 1) != nil)
        gated.open()

        #expect(await events == [.disabled(aliasID: 1, email: "one@example.com")])
    }

    @Test func cancelTimerWithoutATimerReportsThatThereIsNone() throws {
        let engine = makeEngine()

        #expect(throws: TimerEngineError.noTimer) {
            try engine.cancelTimer(aliasID: 1)
        }

        #expect(engine.records.isEmpty)
        #expect(api.toggleCalls.isEmpty)
    }

    @Test func cancelTimerAfterTheTimerEndedReportsThatThereIsNone() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        clock.advance(by: 300)
        _ = await engine.processDue()

        #expect(throws: TimerEngineError.noTimer) {
            try engine.cancelTimer(aliasID: 1)
        }
    }

    // MARK: - Persistence

    @Test func recordsSurviveRestart() async throws {
        let engine = makeEngine()
        let record = try await engine.enable(aliasID: 1, for: .fiveMinutes)

        let restarted = makeEngine()

        #expect(restarted.records == [record])
        #expect(restarted.loadError == nil)
    }

    @Test func loadFailureRefusesToSaveAndReportsError() async throws {
        let failing = InMemoryTimerStore(records: [], failLoad: true)
        let engine = makeEngine(store: failing)

        #expect(engine.loadError == .unreadable("test"))
        #expect(engine.records.isEmpty)
        await #expect(throws: TimerEngineError.storeUnavailable) {
            try await engine.enable(aliasID: 1, for: .fiveMinutes)
        }
        #expect(throws: TimerEngineError.storeUnavailable) {
            try engine.startTimer(for: .fixture(id: 9, enabled: true), duration: .oneHour)
        }
        #expect(throws: TimerEngineError.storeUnavailable) {
            try engine.extend(aliasID: 1, by: .oneHour)
        }
        #expect(api.aliases[1]?.enabled == false)
        #expect(api.toggleCalls.isEmpty)
        #expect(failing.records.isEmpty)
    }

    @Test func nonStoreLoadErrorIsReportedAsUnreadable() {
        struct BrokenStore: TimerStore {
            struct Failure: Error {}
            func load() throws -> [TimerRecord] { throw Failure() }
            func save(_ records: [TimerRecord]) throws {}
        }

        let engine = TimerEngine(store: BrokenStore())

        #expect(engine.loadError == .unreadable("Failure()"))
    }

    // MARK: - Expiry

    @Test func processDueDisablesExpired() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        clock.advance(by: 301)

        let events = await engine.processDue()

        #expect(events == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
        #expect(api.aliases[1]?.enabled == false)
    }

    @Test func anExpiryDisableSurvivesTwoFailedToggles() async throws {
        let engine = makeEngine(retry: RetryPolicy(attempts: 3, delay: .zero))
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.toggleErrors = [APIError.transport("offline"), APIError.transport("offline")]
        clock.advance(by: 301)

        let events = await engine.processDue()

        #expect(events == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(api.aliases[1]?.enabled == false)
    }

    @Test func processDueIgnoresNotYetExpired() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        clock.advance(by: 299)

        let events = await engine.processDue()

        #expect(events.isEmpty)
        #expect(engine.record(for: 1) != nil)
        #expect(api.aliases[1]?.enabled == true)
        #expect(api.toggleCalls == [1])
    }

    @Test func expiredButAlreadyDisabledDropsRecordWithoutToggle() async {
        let store = InMemoryTimerStore(records: [
            TimerRecord(aliasID: 1, email: "one@example.com", enabledAt: t0, expiresAt: t0.addingTimeInterval(300)),
        ])
        let engine = makeEngine(store: store)
        clock.advance(by: 400)

        let events = await engine.processDue()

        #expect(events == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
        #expect(api.toggleCalls.isEmpty)
    }

    @Test func nextDueDateIsEarliestExpiry() async throws {
        let engine = makeEngine()
        #expect(engine.nextDueDate() == nil)

        _ = try await engine.enable(aliasID: 1, for: .oneHour)
        _ = try await engine.enable(aliasID: 2, for: .fiveMinutes)

        #expect(engine.nextDueDate() == t0.addingTimeInterval(300))
    }

    @Test func processDueWithoutAPIDoesNothing() async {
        let store = InMemoryTimerStore(records: [
            TimerRecord(aliasID: 1, email: "one@example.com", enabledAt: t0, expiresAt: t0.addingTimeInterval(300)),
        ])
        let engine = makeEngine(store: store, signedIn: false)
        clock.advance(by: 400)

        let events = await engine.processDue()

        #expect(events.isEmpty)
        #expect(engine.records.count == 1)
        #expect(engine.failures.isEmpty)
    }

    // MARK: - Retrying failed disables

    @Test func aFailedExpiryDisableIsReportedRightAwayWithItsReason() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        let expiry = t0.addingTimeInterval(300)
        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)

        #expect(await engine.processDue() == [
            .disableKeepsFailing(aliasID: 1, email: "one@example.com", problem: .unreachable),
        ])
        #expect(engine.failures[1] == .transient(
            problem: .unreachable, attempts: 1, nextRetryAt: expiry.addingTimeInterval(5), reported: true
        ))
    }

    @Test func transientFailureKeepsRecordAndBacksOff() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        let expiry = t0.addingTimeInterval(300)
        api.errors = Array(repeating: APIError.transport("offline"), count: 3)
        clock.advance(by: 300)

        _ = await engine.processDue()
        #expect(engine.record(for: 1) != nil)
        #expect(store.records.count == 1)
        #expect(engine.nextDueDate() == expiry.addingTimeInterval(5))

        clock.advance(by: 4)
        #expect(await engine.processDue().isEmpty)
        #expect(api.errors.count == 2)

        clock.advance(by: 1)
        #expect(await engine.processDue().isEmpty)
        #expect(api.errors.count == 1)
        #expect(engine.nextDueDate() == expiry.addingTimeInterval(5 + 10))

        clock.advance(by: 10)
        #expect(await engine.processDue().isEmpty)
        #expect(engine.nextDueDate() == expiry.addingTimeInterval(5 + 10 + 20))

        clock.advance(by: 20)
        #expect(await engine.processDue() == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(engine.records.isEmpty)
        #expect(engine.failures.isEmpty)
        #expect(api.aliases[1]?.enabled == false)
    }

    @Test func backoffCapsAtTwoMinutes() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = Array(repeating: APIError.transport("offline"), count: 7)
        clock.advance(by: 300)

        var delays: [TimeInterval] = []
        for _ in 0..<7 {
            _ = await engine.processDue()
            let next = try #require(engine.nextDueDate())
            delays.append(next.timeIntervalSince(clock.now))
            clock.now = next
        }

        #expect(delays == [5, 10, 20, 40, 60, 120, 120])
    }

    @Test func aFailingDisableIsReportedOnlyOnce() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        let expiry = t0.addingTimeInterval(300)
        api.errors = Array(repeating: APIError.transport("offline"), count: 100)
        clock.advance(by: 300)

        let reports = await reportsWhileFailing(engine, until: expiry.addingTimeInterval(200))

        #expect(reports.count == 1)
        #expect(reports.first?.0 == expiry)
        #expect(reports.first?.1 == .disableKeepsFailing(aliasID: 1, email: "one@example.com", problem: .unreachable))
        #expect(engine.record(for: 1) != nil)
    }

    @Test func aServerErrorIsReportedWithItsStatus() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.server(status: 503, message: nil)]
        clock.advance(by: 300)

        #expect(await engine.processDue() == [
            .disableKeepsFailing(aliasID: 1, email: "one@example.com", problem: .notResponding(status: 503)),
        ])
    }

    @Test func failuresDuringTheQuietPeriodAreReportedAfterIt() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        let expiry = t0.addingTimeInterval(300)
        engine.failureReportsResumeAt = expiry.addingTimeInterval(120)
        api.errors = Array(repeating: APIError.transport("offline"), count: 100)
        clock.advance(by: 300)

        let reports = await reportsWhileFailing(engine, until: expiry.addingTimeInterval(200))

        // Attempts at +0, +5, +15, +35, +75, +135: the first one at or after the resume date reports.
        #expect(reports.count == 1)
        #expect(reports.first?.0 == expiry.addingTimeInterval(135))
    }

    @Test func retryNowMakesAFailedDisableDueRightAway() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)
        _ = await engine.processDue()

        engine.retryNow(aliasID: 1)

        #expect(engine.nextDueDate() == clock.now)
        #expect(await engine.processDue() == [.disabled(aliasID: 1, email: "one@example.com")])
    }

    @Test func retryNowWithoutAFailureChangesNothing() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)

        engine.retryNow(aliasID: 1)

        #expect(engine.nextDueDate() == t0.addingTimeInterval(300))
        #expect(engine.failures.isEmpty)
    }

    /// Runs `processDue` once per second until `end` and collects when each event came.
    private func reportsWhileFailing(_ engine: TimerEngine, until end: Date) async -> [(Date, TimerEvent)] {
        var reports: [(Date, TimerEvent)] = []
        while clock.now <= end {
            for event in await engine.processDue() {
                reports.append((clock.now, event))
            }
            clock.advance(by: 1)
        }
        return reports
    }

    @Test func extendAfterFailureResetsBackoff() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)
        _ = await engine.processDue()

        try engine.extend(aliasID: 1, by: .fiveMinutes)

        #expect(engine.failures[1] == nil)
        #expect(engine.nextDueDate() == t0.addingTimeInterval(600))
    }

    @Test func disableNowClearsFailure() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)
        _ = await engine.processDue()

        try await engine.disableNow(aliasID: 1)

        #expect(engine.failures.isEmpty)
        #expect(engine.records.isEmpty)
    }

    @Test func unauthorizedStopsRetriesUntilKeyChange() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)
        api.errors = [APIError.unauthorized]
        clock.advance(by: 300)

        #expect(await engine.processDue() == [.unauthorized])
        #expect(engine.failures == [1: .unauthorized, 2: .unauthorized])
        #expect(engine.nextDueDate() == nil)
        #expect(engine.records.count == 2)

        api.errors = [APIError.unauthorized]
        clock.advance(by: 3600)
        #expect(await engine.processDue().isEmpty)
        #expect(await engine.processDue().isEmpty)
        #expect(api.errors.count == 1)

        api.errors = []
        engine.resumeAfterKeyChange()
        #expect(engine.failures.isEmpty)

        let events = await engine.processDue()
        #expect(events == [
            .disabled(aliasID: 1, email: "one@example.com"),
            .disabled(aliasID: 2, email: "two@example.com"),
        ])
        #expect(engine.records.isEmpty)
    }

    @Test func extendKeepsInvalidKeyState() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.unauthorized]
        clock.advance(by: 300)
        _ = await engine.processDue()

        try engine.extend(aliasID: 1, by: .fiveMinutes)

        #expect(engine.failures[1] == .unauthorized)
        #expect(engine.nextDueDate() == nil)
    }

    @Test func resumeAfterKeyChangeKeepsTransientFailures() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)
        _ = await engine.processDue()

        engine.resumeAfterKeyChange()

        #expect(engine.nextDueDate() == t0.addingTimeInterval(305))
    }

    @Test func cancellationIsNotCountedAsFailedAttempt() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [CancellationError()]
        clock.advance(by: 300)

        #expect(await engine.processDue().isEmpty)

        #expect(engine.failures.isEmpty)
        #expect(engine.record(for: 1) != nil)
        #expect(engine.nextDueDate() == t0.addingTimeInterval(300))
    }

    @Test func transportErrorInCancelledTaskIsNotCountedAsFailedAttempt() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.transport("cancelled")]
        clock.advance(by: 300)

        let task = Task { await engine.processDue() }
        task.cancel()
        #expect(await task.value.isEmpty)

        #expect(engine.failures.isEmpty)
        #expect(engine.record(for: 1) != nil)
    }

    @Test func overlappingProcessingDisablesOnlyOnce() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        clock.advance(by: 300)

        async let first = engine.processDue()
        async let second = engine.processDue()
        let events = await first + second

        #expect(events == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(api.toggleCalls == [1, 1])
        #expect(api.aliases[1]?.enabled == false)
    }

    @Test func disableNowWhileExpiryIsProcessingDisablesOnlyOnce() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        clock.advance(by: 300)

        async let events = engine.processDue()
        async let manualDisable: Void = engine.disableNow(aliasID: 1)
        _ = try await (events, manualDisable)

        #expect(api.toggleCalls == [1, 1])
        #expect(api.aliases[1]?.enabled == false)
        #expect(engine.records.isEmpty)
    }

    @Test func overlappingUnauthorizedResponsesReportInvalidKeyOnce() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .fiveMinutes)
        let gated = GatedAliasAPI(base: api)
        engine.api = gated
        api.errors = [APIError.unauthorized, APIError.unauthorized]
        clock.advance(by: 300)

        async let first = engine.processDue()
        await gated.waitUntilHolding(1)
        async let second = engine.processDue()
        await gated.waitUntilHolding(2)
        gated.open()

        #expect(await first + second == [.unauthorized])
        #expect(engine.failures == [1: .unauthorized, 2: .unauthorized])
    }

    @Test func unauthorizedFromReplacedKeyIsIgnored() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        api.errors = [APIError.unauthorized]
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        engine.api = api
        gated.open()

        #expect(await events.isEmpty)
        #expect(engine.failures.isEmpty)
        #expect(await engine.processDue() == [.disabled(aliasID: 1, email: "one@example.com")])
    }

    @Test func unauthorizedFromBeforeKeyChangeIsIgnored() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        api.errors = [APIError.unauthorized]
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        engine.resumeAfterKeyChange()
        gated.open()

        #expect(await events.isEmpty)
        #expect(engine.failures.isEmpty)
        #expect(await engine.processDue() == [.disabled(aliasID: 1, email: "one@example.com")])
    }

    @Test(arguments: [
        (APIError.transport("offline") as any Error, DisableProblem.unreachable),
        (URLError(.notConnectedToInternet), .unreachable),
        (APIError.server(status: 429, message: nil), .notResponding(status: 429)),
        (APIError.server(status: 500, message: nil), .notResponding(status: 500)),
        (APIError.server(status: 599, message: nil), .notResponding(status: 599)),
        (APIError.unauthorized, .keyRejected),
        (APIError.server(status: 403, message: "Forbidden"), .refused),
        (APIError.server(status: 400, message: "Invalid request"), .other),
        (APIError.decoding("bad"), .other),
    ])
    func disableProblemsFollowTheError(error: any Error, expected: DisableProblem) {
        #expect(DisableProblem(error: error) == expected)
    }

    // MARK: - Aliases that no longer exist

    @Test(arguments: [
        APIError.server(status: 404, message: nil),
        APIError.server(status: 400, message: "Unknown error"),
    ])
    func processDueDropsRecordOfAliasThatIsGone(error: APIError) async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [error]
        clock.advance(by: 300)

        #expect(await engine.processDue() == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
        #expect(engine.failures.isEmpty)
    }

    @Test(arguments: [
        APIError.server(status: 400, message: "Invalid request"),
        APIError.server(status: 500, message: nil),
    ])
    func processDueRetriesOtherServerErrors(error: APIError) async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [error]
        clock.advance(by: 300)

        _ = await engine.processDue()
        #expect(engine.record(for: 1) != nil)
        #expect(engine.failures[1] == .transient(
            problem: DisableProblem(error: error),
            attempts: 1,
            nextRetryAt: t0.addingTimeInterval(305),
            reported: true
        ))
    }

    @Test func disableNowTreatsGoneAliasAsDisabled() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.server(status: 404, message: nil)]

        try await engine.disableNow(aliasID: 1)

        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
    }

    @Test func disableAllTreatsGoneAliasAsDisabled() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.server(status: 404, message: nil)]

        #expect(await engine.disableAll(within: .seconds(5)) == .allDisabled)
        #expect(engine.records.isEmpty)
    }

    // MARK: - Aliases the key may not disable

    private let forbidden = APIError.server(status: 403, message: "Forbidden")

    @Test func forbiddenDisableKeepsTheRecordAndReportsItOnce() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [forbidden, forbidden]
        clock.advance(by: 300)

        #expect(await engine.processDue() == [.disableForbidden(aliasID: 1, email: "one@example.com")])
        #expect(engine.record(for: 1) != nil)
        #expect(store.records.count == 1)
        #expect(engine.failures[1] == .forbidden)
        #expect(engine.nextDueDate() == nil)

        clock.advance(by: 3600)
        #expect(await engine.processDue().isEmpty)
        #expect(api.errors.count == 1)
    }

    @Test func aRefusalIsReportedOncePerTimerEvenAfterRelaunch() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        let expiry = t0.addingTimeInterval(300)
        api.errors = [forbidden, forbidden]
        clock.advance(by: 300)
        #expect(await engine.processDue() == [.disableForbidden(aliasID: 1, email: "one@example.com")])

        let relaunchedEngine = makeEngine()

        #expect(await relaunchedEngine.processDue().isEmpty)
        #expect(relaunchedEngine.failures[1] == .forbidden)
        #expect(store.records[0].refusalReportedAt == expiry)
    }

    @Test func aRefusalAfterAKeyChangeStaysSilent() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [forbidden, forbidden]
        clock.advance(by: 300)
        _ = await engine.processDue()

        engine.resumeAfterKeyChange()

        #expect(await engine.processDue().isEmpty)
        #expect(engine.failures[1] == .forbidden)
    }

    @Test func forbiddenDisableOfOneAliasLeavesOthersDue() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .fiveMinutes)
        api.errors = [forbidden]
        clock.advance(by: 300)

        let events = await engine.processDue()

        #expect(events == [
            .disableForbidden(aliasID: 1, email: "one@example.com"),
            .disabled(aliasID: 2, email: "two@example.com"),
        ])
        #expect(engine.records.map(\.aliasID) == [1])
    }

    @Test func forbiddenDisableIsRetriedAfterKeyChange() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [forbidden]
        clock.advance(by: 300)
        _ = await engine.processDue()

        engine.resumeAfterKeyChange()

        #expect(engine.failures.isEmpty)
        #expect(await engine.processDue() == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(engine.records.isEmpty)
    }

    @Test func forbiddenFromBeforeKeyChangeIsIgnored() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        api.errors = [forbidden]
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        engine.resumeAfterKeyChange()
        gated.open()

        #expect(await events.isEmpty)
        #expect(engine.failures.isEmpty)
        #expect(await engine.processDue() == [.disabled(aliasID: 1, email: "one@example.com")])
    }

    @Test func extendKeepsForbiddenState() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [forbidden]
        clock.advance(by: 300)
        _ = await engine.processDue()

        try engine.extend(aliasID: 1, by: .fiveMinutes)

        #expect(engine.failures[1] == .forbidden)
        #expect(engine.nextDueDate() == nil)
    }

    @Test func cancelTimerDropsAForbiddenRecord() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [forbidden]
        clock.advance(by: 300)
        _ = await engine.processDue()

        try engine.cancelTimer(aliasID: 1)

        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
        #expect(engine.failures.isEmpty)
    }

    @Test func disableNowOfAForbiddenAliasKeepsTheRecord() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [forbidden]

        await #expect(throws: forbidden) {
            try await engine.disableNow(aliasID: 1)
        }

        #expect(engine.record(for: 1) != nil)
    }

    @Test func disableAllKeepsTheRecordOfAForbiddenAlias() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [forbidden]

        #expect(await engine.disableAll(within: .seconds(5)) == .stillEnabled([1: .refused]))
        #expect(engine.records.count == 1)
        #expect(store.records.count == 1)
    }

    // MARK: - Operations overlapping an in-flight disable

    @Test func extendDuringFailingDisableDiscardsTheFailure() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        try engine.extend(aliasID: 1, by: .fiveMinutes)
        gated.open()

        #expect(await events.isEmpty)
        #expect(engine.failures[1] == nil)
        #expect(engine.nextDueDate() == t0.addingTimeInterval(600))

        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)
        _ = await engine.processDue()
        #expect(engine.failures[1] == .transient(
            problem: .unreachable,
            attempts: 1,
            nextRetryAt: t0.addingTimeInterval(605),
            reported: true
        ))
    }

    @Test func anAliasIsDisablingWhileItsDisableRuns() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        #expect(engine.disablingAliasIDs == [1])
        gated.open()

        _ = await events
        #expect(engine.disablingAliasIDs.isEmpty)
    }

    @Test func disableNowWaitsForInFlightDisable() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        let manualDisable = TrackedTask { try await engine.disableNow(aliasID: 1) }
        await yieldRepeatedly()
        #expect(!manualDisable.isFinished)
        gated.open()

        try await manualDisable.value
        #expect(engine.record(for: 1) == nil)
        #expect(await events == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(api.toggleCalls == [1, 1])
    }

    @Test func disableNowRetriesWhenInFlightDisableFails() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        api.errors = [APIError.transport("offline")]
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        let manualDisable = TrackedTask { try await engine.disableNow(aliasID: 1) }
        await yieldRepeatedly()
        gated.open()

        try await manualDisable.value
        _ = await events
        #expect(engine.records.isEmpty)
        #expect(engine.failures.isEmpty)
        #expect(api.aliases[1]?.enabled == false)
    }

    @Test func disableAllWaitsForInFlightDisable() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        let quit = TrackedTask { await engine.disableAll(within: .seconds(5)) }
        await yieldRepeatedly()
        #expect(!quit.isFinished)
        gated.open()

        #expect(try await quit.value == .allDisabled)
        #expect(await events == [.disabled(aliasID: 1, email: "one@example.com")])
        #expect(engine.records.isEmpty)
    }

    // MARK: - Disabling everything (quit, sign-out)

    @Test func disableAllDisablesEverythingWithinBudget() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)

        let outcome = await engine.disableAll(within: .seconds(5))

        #expect(outcome == .allDisabled)
        #expect(api.aliases[1]?.enabled == false)
        #expect(api.aliases[2]?.enabled == false)
        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
    }

    @Test func disableAllReturnsFalseWhenSomeFail() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)
        api.errors = [APIError.transport("offline")]

        let outcome = await engine.disableAll(within: .seconds(5))

        #expect(outcome == .stillEnabled([1: .unreachable]))
        #expect(engine.records.count == 1)
        #expect(store.records.count == 1)
    }

    @Test func disableAllGivesUpWhenBudgetIsExhausted() async throws {
        let store = InMemoryTimerStore(records: [
            TimerRecord(aliasID: 1, email: "one@example.com", enabledAt: t0, expiresAt: t0.addingTimeInterval(300)),
        ])
        let engine = TimerEngine(store: store, now: { [clock] in clock.now })
        engine.api = UnresponsiveAliasAPI()
        let started = ContinuousClock.now

        let outcome = await engine.disableAll(within: .milliseconds(100))

        #expect(outcome == .stillEnabled([1: .unreachable]))
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(engine.records.count == 1)
    }

    @Test func disableAllWithoutRecordsSucceeds() async {
        let engine = makeEngine(signedIn: false)

        #expect(await engine.disableAll(within: .seconds(5)) == .allDisabled)
    }

    @Test func disableAllWithoutAPIKeepsRecords() async throws {
        let store = InMemoryTimerStore(records: [
            TimerRecord(aliasID: 1, email: "one@example.com", enabledAt: t0, expiresAt: t0.addingTimeInterval(300)),
        ])
        let engine = makeEngine(store: store, signedIn: false)

        #expect(await engine.disableAll(within: .seconds(5)) == .stillEnabled([1: .unreachable]))
        #expect(engine.records.count == 1)
    }

    @Test func disableAllRetriesWhenJoinedDisableWasCancelled() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        clock.advance(by: 300)

        let tick = Task { await engine.processDue() }
        await gated.waitUntilHolding(1)
        tick.cancel()
        let quit = TrackedTask { await engine.disableAll(within: .seconds(5)) }
        await yieldRepeatedly()
        gated.open()

        #expect(try await quit.value == .allDisabled)
        #expect(api.aliases[1]?.enabled == false)
        #expect(engine.records.isEmpty)
        #expect(await tick.value.isEmpty)
    }

    @Test func disableAllWithUnreadableTimerData() async {
        let engine = makeEngine(store: InMemoryTimerStore(failLoad: true))

        #expect(await engine.disableAll(within: .seconds(5)) == .timerDataUnreadable)
    }

    @Test func disableAllReportsWhyAliasesStayEnabled() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.transport("offline")]

        #expect(await engine.disableAll(within: .seconds(5)) == .stillEnabled([1: .unreachable]))
    }

    @Test func disableAllReportsARefusedAlias() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [forbidden]

        #expect(await engine.disableAll(within: .seconds(5)) == .stillEnabled([1: .refused]))
    }

    @Test func disableAllReportsARejectedKey() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.unauthorized]

        #expect(await engine.disableAll(within: .seconds(5)) == .stillEnabled([1: .keyRejected]))
    }

    @Test func disableAllReportsEveryAliasItLeavesEnabled() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)
        api.errors = [APIError.server(status: 503, message: nil), APIError.server(status: 503, message: nil)]

        #expect(await engine.disableAll(within: .seconds(5)) == .stillEnabled([
            1: .notResponding(status: 503),
            2: .notResponding(status: 503),
        ]))
    }

    @Test func disableAllCountsAnUnfinishedDisableAsUnreachable() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()

        let quit = TrackedTask { await engine.disableAll(within: .milliseconds(50)) }
        await gated.waitUntilHolding(1)
        try await Task.sleep(for: .milliseconds(200))
        gated.open()

        #expect(try await quit.value == .stillEnabled([1: .unreachable]))
    }

    // MARK: - Forgetting timers

    @Test func discardAllForgetsEveryTimer() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)
        clock.advance(by: 300)
        api.errors = [APIError.transport("offline")]
        _ = await engine.processDue()
        #expect(!engine.failures.isEmpty)

        try engine.discardAll()

        #expect(engine.records.isEmpty)
        #expect(engine.failures.isEmpty)
        #expect(store.records.isEmpty)
        #expect(api.aliases[1]?.enabled == true)
        #expect(api.aliases[2]?.enabled == true)
    }

    @Test func discardAllIsRefusedWhenTimerDataIsUnreadable() {
        let engine = makeEngine(store: InMemoryTimerStore(failLoad: true))

        #expect(throws: TimerEngineError.storeUnavailable) {
            try engine.discardAll()
        }
    }

    // MARK: - An account change while enabling

    @Test func anEnableFinishingAfterSignOutStartsNoTimerAndDisablesTheAliasAgain() async throws {
        let engine = makeEngine()
        let gated = GatedAliasAPI(base: api)
        engine.api = gated

        let enabling = Task { try await engine.enable(aliasID: 1, for: .fiveMinutes) }
        await gated.waitUntilHolding(1)
        engine.api = nil
        gated.open()

        await #expect(throws: TimerEngineError.accountChanged) {
            try await enabling.value
        }
        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
        #expect(api.aliases[1]?.enabled == false)
    }

    // MARK: - Reporting each disabled alias

    /// Collects the aliases the engine reports as disabled.
    private func recordingDisabledAliases(of engine: TimerEngine) -> DisabledAliasLog {
        let log = DisabledAliasLog()
        engine.onAliasDisabled = { log.aliasIDs.append($0) }
        return log
    }

    @Test func anExpiredAliasIsReportedAsDisabled() async throws {
        let engine = makeEngine()
        let log = recordingDisabledAliases(of: engine)
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        clock.advance(by: 300)

        _ = await engine.processDue()

        #expect(log.aliasIDs == [1])
    }

    @Test func aManuallyDisabledAliasIsReportedAsDisabled() async throws {
        let engine = makeEngine()
        let log = recordingDisabledAliases(of: engine)
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)

        try await engine.disableNow(aliasID: 1)

        #expect(log.aliasIDs == [1])
    }

    @Test func disableAllReportsOnlyTheAliasesItDisabled() async throws {
        let engine = makeEngine()
        let log = recordingDisabledAliases(of: engine)
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)
        api.errors = [APIError.transport("offline")]

        _ = await engine.disableAll(within: .seconds(5))

        #expect(log.aliasIDs.count == 1)
        #expect(log.aliasIDs.first.map { engine.record(for: $0) == nil } == true)
    }

    @Test func aJoinedDisableIsReportedOnce() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        let log = recordingDisabledAliases(of: engine)
        clock.advance(by: 300)

        async let events = engine.processDue()
        await gated.waitUntilHolding(1)
        let manualDisable = TrackedTask { try await engine.disableNow(aliasID: 1) }
        await yieldRepeatedly()
        gated.open()

        try await manualDisable.value
        _ = await events
        #expect(log.aliasIDs == [1])
    }

    @Test(arguments: [
        APIError.transport("offline"),
        APIError.unauthorized,
        APIError.server(status: 403, message: nil),
    ])
    func aFailedDisableIsNotReported(error: APIError) async throws {
        let engine = makeEngine()
        let log = recordingDisabledAliases(of: engine)
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [error]
        clock.advance(by: 300)

        _ = await engine.processDue()

        #expect(log.aliasIDs.isEmpty)
    }

    // MARK: - Mail arrival

    private func forwardActivity(at timestamp: Date) -> AliasActivity {
        AliasActivity(action: .forward, timestamp: timestamp, contact: AliasContact(email: "login@shop.com", name: nil))
    }

    private func arrival(of aliasID: Int, email: String, at timestamp: Date) -> MailArrival {
        MailArrival(aliasID: aliasID, aliasEmail: email, sender: "login@shop.com", timestamp: timestamp)
    }

    private func receiveMail(forAliasID aliasID: Int, email: String, at timestamp: Date) {
        api.aliases[aliasID] = .fixture(
            id: aliasID,
            email: email,
            enabled: true,
            latestActivity: forwardActivity(at: timestamp)
        )
    }

    @Test func pollReportsArrivalOnceThenNotAgain() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .oneHour)
        let mailTime = t0.addingTimeInterval(30)
        receiveMail(forAliasID: 1, email: "one@example.com", at: mailTime)

        let first = await engine.pollActivity()
        let second = await engine.pollActivity()

        #expect(first == [arrival(of: 1, email: "one@example.com", at: mailTime)])
        #expect(second.isEmpty)
        #expect(engine.record(for: 1)?.lastNotifiedActivityTimestamp == mailTime)
        #expect(store.records.first?.lastNotifiedActivityTimestamp == mailTime)
    }

    @Test func pollAfterExtendDoesNotRenotify() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(30))
        #expect(await engine.pollActivity().count == 1)
        clock.advance(by: 60)

        try engine.extend(aliasID: 1, by: .oneHour)

        #expect(await engine.pollActivity().isEmpty)
    }

    @Test func pollIgnoresMailForwardedBeforeEnabling() async throws {
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(-3600))
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .oneHour)

        #expect(await engine.pollActivity().isEmpty)
        #expect(engine.record(for: 1)?.lastNotifiedActivityTimestamp == nil)
    }

    @Test func pollReportsNewerMailAfterEarlierOne() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .oneHour)
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(30))
        _ = await engine.pollActivity()
        let laterMail = t0.addingTimeInterval(90)
        receiveMail(forAliasID: 1, email: "one@example.com", at: laterMail)

        #expect(await engine.pollActivity() == [arrival(of: 1, email: "one@example.com", at: laterMail)])
    }

    @Test func pollCoversEveryTimedAlias() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .oneHour)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(30))
        receiveMail(forAliasID: 2, email: "two@example.com", at: t0.addingTimeInterval(40))

        let arrivals = await engine.pollActivity()

        #expect(arrivals.map(\.aliasID) == [1, 2])
    }

    @Test func pollSkipsExpiredRecords() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(30))
        clock.advance(by: 301)

        #expect(await engine.pollActivity().isEmpty)
        #expect(engine.record(for: 1)?.lastNotifiedActivityTimestamp == nil)
    }

    @Test func pollFetchesOnlyAliasesWhoseTimersRun() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)
        clock.advance(by: 300)
        let fetchesBefore = api.aliasCalls

        _ = await engine.pollActivity()

        #expect(api.aliasCalls == fetchesBefore + [2])
    }

    @Test func pollFetchesNoAliasWhileTheKeyIsInvalid() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)
        api.errors = [APIError.unauthorized]
        clock.advance(by: 300)
        _ = await engine.processDue()
        let fetchesBefore = api.aliasCalls

        _ = await engine.pollActivity()

        #expect(api.aliasCalls == fetchesBefore)
    }

    @Test func pollFetchesNoAliasTheKeyMayNotDisable() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        api.errors = [APIError.server(status: 403, message: nil)]
        clock.advance(by: 300)
        _ = await engine.processDue()
        try engine.extend(aliasID: 1, by: .oneHour)
        let fetchesBefore = api.aliasCalls

        _ = await engine.pollActivity()

        #expect(api.aliasCalls == fetchesBefore)
    }

    @Test func pollRetriesAfterFetchError() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .oneHour)
        let mailTime = t0.addingTimeInterval(30)
        receiveMail(forAliasID: 1, email: "one@example.com", at: mailTime)
        api.errors = [URLError(.notConnectedToInternet)]

        let failed = await engine.pollActivity()
        let retried = await engine.pollActivity()

        #expect(failed.isEmpty)
        #expect(retried == [arrival(of: 1, email: "one@example.com", at: mailTime)])
    }

    @Test func pollWithoutAPIReportsNothing() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .oneHour)
        engine.api = nil

        #expect(await engine.pollActivity().isEmpty)
    }

    @Test func pollRemovedDuringFetchDoesNotResurrectRecord() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(30))
        let polling = Task { await engine.pollActivity() }
        await gated.waitUntilHolding(1)
        engine.api = api
        try await engine.disableNow(aliasID: 1)

        gated.open()

        #expect(await polling.value.isEmpty)
        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
    }

    @Test func pollExpiredDuringFetchReportsNothing() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(30))
        let polling = Task { await engine.pollActivity() }
        await gated.waitUntilHolding(1)
        clock.advance(by: 301)

        gated.open()

        #expect(await polling.value.isEmpty)
        #expect(engine.record(for: 1)?.lastNotifiedActivityTimestamp == nil)
    }

    @Test func overlappingPollsReportOneArrival() async throws {
        let (engine, gated) = try await makeEngineWithGatedAPI()
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(30))
        let firstPoll = Task { await engine.pollActivity() }
        let secondPoll = Task { await engine.pollActivity() }
        await gated.waitUntilHolding(2)

        gated.open()

        let arrivals = await firstPoll.value + secondPoll.value
        #expect(arrivals.count == 1)
    }

    @Test func reloadedRecordDoesNotRenotifySameActivity() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("timers.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let fileStore = FileTimerStore(fileURL: fileURL)
        let clock = clock
        let engine = TimerEngine(store: fileStore, now: { clock.now })
        engine.api = api
        _ = try await engine.enable(aliasID: 1, for: .oneHour)
        receiveMail(forAliasID: 1, email: "one@example.com", at: t0.addingTimeInterval(30.7))
        #expect(await engine.pollActivity().count == 1)

        let relaunched = TimerEngine(store: fileStore, now: { clock.now })
        relaunched.api = api

        #expect(await relaunched.pollActivity().isEmpty)
    }

    // MARK: - Signed out

    @Test func operationsWithoutAPIThrowNotSignedIn() async throws {
        let engine = makeEngine(signedIn: false)

        await #expect(throws: TimerEngineError.notSignedIn) {
            try await engine.enable(aliasID: 1, for: .fiveMinutes)
        }
        await #expect(throws: TimerEngineError.notSignedIn) {
            try await engine.disableNow(aliasID: 1)
        }
        #expect(engine.records.isEmpty)
        #expect(store.records.isEmpty)
    }
}

@MainActor private final class DisabledAliasLog {
    var aliasIDs: [Int] = []
}

/// A main-actor task that remembers whether its operation has returned.
@MainActor private final class TrackedTask<Success: Sendable> {
    private(set) var isFinished = false
    private var task: Task<Success, any Error>!

    init(_ operation: @escaping @MainActor () async throws -> Success) {
        task = Task { [weak self] in
            defer { self?.isFinished = true }
            return try await operation()
        }
    }

    var value: Success {
        get async throws { try await task.value }
    }
}

private struct UnresponsiveAliasAPI: AliasAPI {
    func alias(id: Int) async throws -> Alias {
        try await Task.sleep(for: .seconds(30))
        return .fixture(id: id, enabled: true)
    }

    func toggle(aliasID: Int) async throws -> Bool {
        try await Task.sleep(for: .seconds(30))
        return false
    }
}
