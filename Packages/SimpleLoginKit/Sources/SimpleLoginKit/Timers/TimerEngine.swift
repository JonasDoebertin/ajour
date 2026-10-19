import Foundation
import Observation

public enum DisableFailure: Equatable, Sendable {
    case transient(firstFailedAt: Date, attempts: Int, nextRetryAt: Date, reported: Bool)
    case unauthorized
}

public enum TimerEvent: Equatable, Sendable {
    case disabled(aliasID: Int, email: String)
    case disableKeepsFailing(aliasID: Int, email: String)
    case unauthorized
}

public enum TimerEngineError: Error, Equatable {
    case notSignedIn
    case storeUnavailable
}

@MainActor @Observable public final class TimerEngine {
    public var api: (any AliasAPI)?
    public private(set) var records: [TimerRecord]
    public private(set) var failures: [Int: DisableFailure] = [:]
    public private(set) var loadError: TimerStoreError?

    private static let retryDelays: [TimeInterval] = [5, 10, 20, 40, 60]
    private static let failureReportDelay: TimeInterval = 120

    private let store: any TimerStore
    private let now: @Sendable () -> Date
    /// Two overlapping disables could both read "enabled" and toggle twice, re-enabling the alias.
    @ObservationIgnored private var aliasesBeingDisabled: Set<Int> = []

    public init(store: any TimerStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
        do {
            records = try store.load()
        } catch let error as TimerStoreError {
            records = []
            loadError = error
        } catch {
            records = []
            loadError = .unreadable(String(describing: error))
        }
    }

    public var hasActiveTimers: Bool {
        !records.isEmpty
    }

    public func record(for aliasID: Int) -> TimerRecord? {
        records.first { $0.aliasID == aliasID }
    }

    public func enable(aliasID: Int, for duration: AliasDuration) async throws -> TimerRecord {
        try ensureStoreAvailable()
        if let index = recordIndex(for: aliasID) {
            return try extendRecord(at: index, by: duration)
        }
        let aliasSwitch = AliasSwitch(api: try signedInAPI())
        let alias = try await aliasSwitch.ensureEnabled(aliasID: aliasID)
        return try startTimer(for: alias, duration: duration)
    }

    public func startTimer(for alias: Alias, duration: AliasDuration) throws -> TimerRecord {
        try ensureStoreAvailable()
        if let index = recordIndex(for: alias.id) {
            return try extendRecord(at: index, by: duration)
        }
        let startedAt = now()
        let record = TimerRecord(
            aliasID: alias.id,
            email: alias.email,
            enabledAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(duration.seconds)
        )
        records.append(record)
        try save()
        return record
    }

    public func extend(aliasID: Int, by duration: AliasDuration) throws {
        try ensureStoreAvailable()
        guard let index = recordIndex(for: aliasID) else { return }
        _ = try extendRecord(at: index, by: duration)
    }

    public func disableNow(aliasID: Int) async throws {
        let aliasSwitch = AliasSwitch(api: try signedInAPI())
        guard claimDisable(of: aliasID) else { return }
        defer { aliasesBeingDisabled.remove(aliasID) }
        _ = try await aliasSwitch.ensureDisabled(aliasID: aliasID)
        try removeRecord(aliasID: aliasID)
    }

    public func processDue() async -> [TimerEvent] {
        guard let api else { return [] }
        let aliasSwitch = AliasSwitch(api: api)
        var events: [TimerEvent] = []
        for aliasID in records.filter(isDue).map(\.aliasID) {
            guard let record = record(for: aliasID), isDue(record), claimDisable(of: aliasID) else { continue }
            defer { aliasesBeingDisabled.remove(aliasID) }
            do {
                _ = try await aliasSwitch.ensureDisabled(aliasID: aliasID)
                try? removeRecord(aliasID: aliasID)
                events.append(.disabled(aliasID: aliasID, email: record.email))
            } catch APIError.unauthorized {
                markAllUnauthorized()
                events.append(.unauthorized)
                break
            } catch where Self.isCancellation(error) {
                break
            } catch {
                if registerTransientFailure(aliasID: aliasID) {
                    events.append(.disableKeepsFailing(aliasID: aliasID, email: record.email))
                }
            }
        }
        return events
    }

    public func nextDueDate() -> Date? {
        records.compactMap { record -> Date? in
            switch failures[record.aliasID] {
            case .unauthorized: nil
            case .transient(_, _, let nextRetryAt, _): nextRetryAt
            case nil: record.expiresAt
            }
        }.min()
    }

    public func resumeAfterKeyChange() {
        failures = failures.filter { $0.value != .unauthorized }
    }

    /// Tries to disable every timed alias once, in parallel. Gives up when the budget runs out;
    /// records of aliases that could not be disabled stay for the next launch.
    public func disableAll(within budget: Duration) async -> Bool {
        guard let api else { return records.isEmpty }
        let aliasSwitch = AliasSwitch(api: api)
        let claimedAliasIDs = records.map(\.aliasID).filter(claimDisable)
        defer { aliasesBeingDisabled.subtract(claimedAliasIDs) }

        await withTaskGroup(of: DisableAttempt.self) { group in
            for aliasID in claimedAliasIDs {
                group.addTask {
                    do {
                        _ = try await aliasSwitch.ensureDisabled(aliasID: aliasID)
                        return .disabled(aliasID: aliasID)
                    } catch {
                        return .failed
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                return .budgetExhausted
            }

            var pendingAttempts = claimedAliasIDs.count
            while pendingAttempts > 0, let attempt = await group.next() {
                switch attempt {
                case .disabled(let aliasID):
                    try? removeRecord(aliasID: aliasID)
                    pendingAttempts -= 1
                case .failed:
                    pendingAttempts -= 1
                case .budgetExhausted:
                    pendingAttempts = 0
                }
            }
            group.cancelAll()
        }
        return records.isEmpty
    }

    private func isDue(_ record: TimerRecord) -> Bool {
        let currentDate = now()
        guard record.expiresAt <= currentDate else { return false }
        switch failures[record.aliasID] {
        case .unauthorized: return false
        case .transient(_, _, let nextRetryAt, _): return nextRetryAt <= currentDate
        case nil: return true
        }
    }

    private func claimDisable(of aliasID: Int) -> Bool {
        aliasesBeingDisabled.insert(aliasID).inserted
    }

    private func markAllUnauthorized() {
        for record in records {
            failures[record.aliasID] = .unauthorized
        }
    }

    /// Returns whether the failure has now lasted long enough to be reported, which happens once.
    private func registerTransientFailure(aliasID: Int) -> Bool {
        guard record(for: aliasID) != nil else { return false }
        let failedAt = now()
        var firstFailedAt = failedAt
        var attempts = 1
        var reported = false
        if case .transient(let previousFirstFailedAt, let previousAttempts, _, let previousReported) = failures[aliasID] {
            firstFailedAt = previousFirstFailedAt
            attempts = previousAttempts + 1
            reported = previousReported
        }
        let delay = Self.retryDelays[min(attempts, Self.retryDelays.count) - 1]
        let shouldReport = !reported && failedAt.timeIntervalSince(firstFailedAt) >= Self.failureReportDelay
        failures[aliasID] = .transient(
            firstFailedAt: firstFailedAt,
            attempts: attempts,
            nextRetryAt: failedAt.addingTimeInterval(delay),
            reported: reported || shouldReport
        )
        return shouldReport
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func recordIndex(for aliasID: Int) -> Int? {
        records.firstIndex { $0.aliasID == aliasID }
    }

    /// An invalid key stays invalid after extending; only a new key clears it.
    private func extendRecord(at index: Int, by duration: AliasDuration) throws -> TimerRecord {
        records[index].expiresAt = now().addingTimeInterval(duration.seconds)
        let aliasID = records[index].aliasID
        if case .transient = failures[aliasID] {
            failures[aliasID] = nil
        }
        try save()
        return records[index]
    }

    private func removeRecord(aliasID: Int) throws {
        failures[aliasID] = nil
        guard records.contains(where: { $0.aliasID == aliasID }) else { return }
        records.removeAll { $0.aliasID == aliasID }
        try save()
    }

    private func signedInAPI() throws -> any AliasAPI {
        guard let api else { throw TimerEngineError.notSignedIn }
        return api
    }

    private func ensureStoreAvailable() throws {
        guard loadError == nil else { throw TimerEngineError.storeUnavailable }
    }

    /// Records change in memory first, so a failed save never loses track of an enabled alias
    /// while the app runs.
    private func save() throws {
        try ensureStoreAvailable()
        try store.save(records)
    }
}

private enum DisableAttempt: Sendable {
    case disabled(aliasID: Int)
    case failed
    case budgetExhausted
}
