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

    private func makeEngine(store: InMemoryTimerStore? = nil, signedIn: Bool = true) -> TimerEngine {
        let clock = clock
        let engine = TimerEngine(store: store ?? self.store, now: { clock.now })
        if signedIn {
            engine.api = api
        }
        return engine
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

    @Test func transientFailureKeepsRecordAndBacksOff() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        let expiry = t0.addingTimeInterval(300)
        api.errors = Array(repeating: APIError.transport("offline"), count: 3)
        clock.advance(by: 300)

        #expect(await engine.processDue().isEmpty)
        #expect(engine.record(for: 1) != nil)
        #expect(store.records.count == 1)
        #expect(engine.failures[1] == .transient(
            firstFailedAt: expiry, attempts: 1, nextRetryAt: expiry.addingTimeInterval(5), reported: false
        ))
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

    @Test func backoffCapsAtSixtySeconds() async throws {
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

        #expect(delays == [5, 10, 20, 40, 60, 60, 60])
    }

    @Test func persistentFailureReportedOnceAfter120Seconds() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        let expiry = t0.addingTimeInterval(300)
        api.errors = Array(repeating: APIError.transport("offline"), count: 100)
        clock.advance(by: 300)

        var reports: [(Date, TimerEvent)] = []
        while clock.now <= expiry.addingTimeInterval(200) {
            for event in await engine.processDue() {
                reports.append((clock.now, event))
            }
            clock.advance(by: 1)
        }

        // Attempts at +0, +5, +15, +35, +75, +135: the first one at least 120 s after the first failure reports.
        #expect(reports.count == 1)
        #expect(reports.first?.0 == expiry.addingTimeInterval(135))
        #expect(reports.first?.1 == .disableKeepsFailing(aliasID: 1, email: "one@example.com"))
        #expect(engine.record(for: 1) != nil)
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

    // MARK: - Disabling everything (quit, sign-out)

    @Test func disableAllDisablesEverythingWithinBudget() async throws {
        let engine = makeEngine()
        _ = try await engine.enable(aliasID: 1, for: .fiveMinutes)
        _ = try await engine.enable(aliasID: 2, for: .oneHour)

        let allDisabled = await engine.disableAll(within: .seconds(5))

        #expect(allDisabled)
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

        let allDisabled = await engine.disableAll(within: .seconds(5))

        #expect(!allDisabled)
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

        let allDisabled = await engine.disableAll(within: .milliseconds(100))

        #expect(!allDisabled)
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(engine.records.count == 1)
    }

    @Test func disableAllWithoutRecordsSucceeds() async {
        let engine = makeEngine(signedIn: false)

        #expect(await engine.disableAll(within: .seconds(5)))
    }

    @Test func disableAllWithoutAPIKeepsRecords() async throws {
        let store = InMemoryTimerStore(records: [
            TimerRecord(aliasID: 1, email: "one@example.com", enabledAt: t0, expiresAt: t0.addingTimeInterval(300)),
        ])
        let engine = makeEngine(store: store, signedIn: false)

        #expect(await engine.disableAll(within: .seconds(5)) == false)
        #expect(engine.records.count == 1)
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
