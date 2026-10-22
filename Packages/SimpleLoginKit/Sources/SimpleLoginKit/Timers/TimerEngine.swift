import Foundation
import Observation

public enum DisableFailure: Equatable, Sendable {
    case transient(firstFailedAt: Date, attempts: Int, nextRetryAt: Date, reported: Bool)
    case unauthorized
    /// The current key may not change the alias, so retrying with it is pointless.
    case forbidden
}

public enum TimerEvent: Equatable, Sendable {
    case disabled(aliasID: Int, email: String)
    case disableKeepsFailing(aliasID: Int, email: String)
    case disableForbidden(aliasID: Int, email: String)
    case unauthorized
}

public enum TimerEngineError: Error, Equatable {
    case notSignedIn
    case storeUnavailable
    case disableInProgress
    case noTimer
}

@MainActor @Observable public final class TimerEngine {
    public var api: (any AliasAPI)? {
        didSet { keyGeneration += 1 }
    }
    public private(set) var records: [TimerRecord]
    public private(set) var failures: [Int: DisableFailure] = [:]
    public private(set) var loadError: TimerStoreError?
    /// Called once per successful disable, as soon as it succeeds, whether it came from expiry, `disableNow`, or `disableAll`.
    @ObservationIgnored public var onAliasDisabled: (@MainActor (Int) -> Void)?

    private static let retryDelays: [TimeInterval] = [5, 10, 20, 40, 60]
    private static let failureReportDelay: TimeInterval = 120

    private let store: any TimerStore
    private let now: @Sendable () -> Date
    private let retry: RetryPolicy
    /// Overlapping disables of one alias share a single attempt: two separate attempts could both
    /// read "enabled" and toggle twice, re-enabling the alias.
    @ObservationIgnored private var disablesInFlight: [Int: Task<DisableOutcome, Never>] = [:]
    /// Changes whenever the key may have changed, so a 401 answering an older key is ignored.
    @ObservationIgnored private var keyGeneration = 0

    public init(
        store: any TimerStore,
        now: @escaping @Sendable () -> Date = Date.init,
        retry: RetryPolicy = .standard
    ) {
        self.store = store
        self.now = now
        self.retry = retry
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
        let aliasSwitch = AliasSwitch(api: try signedInAPI(), retry: retry)
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

    /// Stops tracking the alias and leaves it enabled. Refused while a disable of the alias runs instead of
    /// waiting for it: that disable may already have turned the alias off, and keeping it enabled would then
    /// need a new enable. Without a record there is nothing to keep: the timer already ended and disabled the alias.
    public func cancelTimer(aliasID: Int) throws {
        try ensureStoreAvailable()
        guard disablesInFlight[aliasID] == nil else { throw TimerEngineError.disableInProgress }
        guard recordIndex(for: aliasID) != nil else { throw TimerEngineError.noTimer }
        try removeRecord(aliasID: aliasID)
    }

    public func disableNow(aliasID: Int) async throws {
        guard api != nil else { throw TimerEngineError.notSignedIn }
        if let inFlight = disablesInFlight[aliasID], case .disabled = await outcome(of: inFlight) {
            return
        }
        switch await disable(aliasID: aliasID) {
        case .disabled: return
        case .unauthorized: throw APIError.unauthorized
        case .forbidden(_, let error): throw error
        case .cancelled: throw CancellationError()
        case .failed(let error): throw error
        }
    }

    public func processDue() async -> [TimerEvent] {
        var events: [TimerEvent] = []
        for aliasID in records.filter(isDue).map(\.aliasID) {
            guard api != nil else { break }
            guard let record = record(for: aliasID), isDue(record), disablesInFlight[aliasID] == nil else { continue }
            switch await disable(aliasID: aliasID) {
            case .disabled:
                events.append(.disabled(aliasID: aliasID, email: record.email))
            case .unauthorized(let generation):
                guard generation == keyGeneration else { continue }
                if markAllUnauthorized() {
                    events.append(.unauthorized)
                }
                return events
            case .forbidden(let generation, _):
                guard generation == keyGeneration, markForbidden(aliasID: aliasID) else { continue }
                events.append(.disableForbidden(aliasID: aliasID, email: record.email))
            case .cancelled:
                return events
            case .failed:
                if Task.isCancelled { return events }
                if registerTransientFailure(aliasID: aliasID) {
                    events.append(.disableKeepsFailing(aliasID: aliasID, email: record.email))
                }
            }
        }
        return events
    }

    /// Checks every running timer's alias for a mail forwarded since it was enabled and reports each mail once.
    /// A failed fetch is skipped; the next poll tries again. Expired timers and aliases the key can't reach
    /// aren't fetched at all.
    public func pollActivity() async -> [MailArrival] {
        var arrivals: [MailArrival] = []
        for aliasID in records.filter(isPollable).map(\.aliasID) {
            guard let api, !Task.isCancelled else { break }
            guard let alias = try? await api.alias(id: aliasID) else { continue }
            guard let index = recordIndex(for: aliasID), records[index].expiresAt > now(),
                  let arrival = MailArrivalDetector.arrival(in: alias, for: records[index])
            else { continue }
            records[index].lastNotifiedActivityTimestamp = arrival.timestamp
            try? save()
            arrivals.append(arrival)
        }
        return arrivals
    }

    public func nextDueDate() -> Date? {
        records.compactMap { record -> Date? in
            switch failures[record.aliasID] {
            case .unauthorized, .forbidden: nil
            case .transient(_, _, let nextRetryAt, _): max(nextRetryAt, record.expiresAt)
            case nil: record.expiresAt
            }
        }.min()
    }

    public func resumeAfterKeyChange() {
        keyGeneration += 1
        failures = failures.filter { $0.value != .unauthorized && $0.value != .forbidden }
    }

    /// Tries to disable every timed alias once, in parallel. Gives up when the budget runs out;
    /// records of aliases that could not be disabled stay for the next launch.
    /// Returns false when the timer file was unreadable, because aliases it lists may still be enabled.
    public func disableAll(within budget: Duration) async -> Bool {
        guard loadError == nil else { return false }
        guard api != nil else { return records.isEmpty }
        let aliasIDs = records.map(\.aliasID)

        await withTaskGroup(of: GroupResult.self) { group in
            for aliasID in aliasIDs {
                group.addTask {
                    _ = await self.disable(aliasID: aliasID)
                    return .attemptFinished
                }
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                return .budgetExhausted
            }

            var pendingAttempts = aliasIDs.count
            while pendingAttempts > 0, let result = await group.next() {
                switch result {
                case .attemptFinished: pendingAttempts -= 1
                case .budgetExhausted: pendingAttempts = 0
                }
            }
            group.cancelAll()
        }
        return records.isEmpty
    }

    /// Joins the alias's in-flight attempt, or starts one. A successful attempt drops the record.
    /// Any awaiter that is cancelled cancels the shared attempt, so an awaiter that wasn't cancelled
    /// itself starts over instead of taking on someone else's cancellation.
    private func disable(aliasID: Int) async -> DisableOutcome {
        if let inFlight = disablesInFlight[aliasID] {
            let joinedOutcome = await outcome(of: inFlight)
            guard case .cancelled = joinedOutcome, !Task.isCancelled else { return joinedOutcome }
        }
        return await outcome(of: disablesInFlight[aliasID] ?? startDisable(aliasID: aliasID))
    }

    private func outcome(of attempt: Task<DisableOutcome, Never>) async -> DisableOutcome {
        await withTaskCancellationHandler {
            await attempt.value
        } onCancel: {
            attempt.cancel()
        }
    }

    private func startDisable(aliasID: Int) -> Task<DisableOutcome, Never> {
        guard let api else {
            return Task { .failed(TimerEngineError.notSignedIn) }
        }
        let aliasSwitch = AliasSwitch(api: api, retry: retry)
        let generation = keyGeneration
        let attempt = Task {
            let outcome = await Self.attemptDisable(aliasID: aliasID, using: aliasSwitch, keyGeneration: generation)
            disablesInFlight[aliasID] = nil
            if case .disabled = outcome {
                try? removeRecord(aliasID: aliasID)
                onAliasDisabled?(aliasID)
            }
            return outcome
        }
        disablesInFlight[aliasID] = attempt
        return attempt
    }

    nonisolated private static func attemptDisable(
        aliasID: Int,
        using aliasSwitch: AliasSwitch,
        keyGeneration: Int
    ) async -> DisableOutcome {
        do {
            _ = try await aliasSwitch.ensureDisabled(aliasID: aliasID)
            return .disabled
        } catch where isCancellation(error) {
            return .cancelled
        } catch APIError.unauthorized {
            return .unauthorized(generation: keyGeneration)
        } catch APIError.server(status: 403, let message) {
            return .forbidden(generation: keyGeneration, error: .server(status: 403, message: message))
        } catch where isAliasGone(error) {
            return .disabled
        } catch {
            return .failed(error)
        }
    }

    /// SimpleLogin answers 404 or 400 "Unknown error" for aliases that don't exist. A 403 is different: the alias
    /// belongs to another account, for example after the key was replaced, and may still be enabled there.
    nonisolated private static func isAliasGone(_ error: any Error) -> Bool {
        switch error as? APIError {
        case .server(status: 404, _), .server(status: 400, message: "Unknown error"):
            true
        default:
            false
        }
    }

    private func isPollable(_ record: TimerRecord) -> Bool {
        guard record.expiresAt > now() else { return false }
        switch failures[record.aliasID] {
        case .unauthorized, .forbidden: return false
        case .transient, nil: return true
        }
    }

    private func isDue(_ record: TimerRecord) -> Bool {
        let currentDate = now()
        guard record.expiresAt <= currentDate else { return false }
        switch failures[record.aliasID] {
        case .unauthorized, .forbidden: return false
        case .transient(_, _, let nextRetryAt, _): return nextRetryAt <= currentDate
        case nil: return true
        }
    }

    /// Returns whether the key just became invalid, as opposed to already being known as invalid.
    private func markAllUnauthorized() -> Bool {
        let wasAlreadyUnauthorized = failures.values.contains(.unauthorized)
        for record in records {
            failures[record.aliasID] = .unauthorized
        }
        return !wasAlreadyUnauthorized
    }

    /// Returns whether the alias is still timed and so now waits for a new key.
    private func markForbidden(aliasID: Int) -> Bool {
        guard recordIndex(for: aliasID) != nil else { return false }
        failures[aliasID] = .forbidden
        return true
    }

    /// Returns whether the failure has now lasted long enough to be reported, which happens once.
    /// A record extended while the attempt was running is no longer due, so its failure is discarded.
    private func registerTransientFailure(aliasID: Int) -> Bool {
        let failedAt = now()
        guard let record = record(for: aliasID), record.expiresAt <= failedAt else { return false }
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

    nonisolated private static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func recordIndex(for aliasID: Int) -> Int? {
        records.firstIndex { $0.aliasID == aliasID }
    }

    /// An invalid or forbidden key stays so after extending; only a new key clears it.
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

private enum DisableOutcome: Sendable {
    case disabled
    case unauthorized(generation: Int)
    case forbidden(generation: Int, error: APIError)
    case cancelled
    case failed(any Error)
}

private enum GroupResult: Sendable {
    case attemptFinished
    case budgetExhausted
}
