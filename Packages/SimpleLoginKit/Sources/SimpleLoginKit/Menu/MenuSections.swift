import Foundation

public enum AliasMenuState: Equatable, Sendable {
    case disabled
    case enabled
    case timed(remaining: TimeInterval, endsAt: Date, length: TimeInterval)
    /// The timer ran out, but switching the alias off keeps failing and Ajour keeps trying.
    case disableFailing
    /// The timer ran out, but the current API key may not switch the alias off.
    case disableRefused
}

public struct MenuAliasItem: Equatable, Sendable, Identifiable {
    public let id: Int
    public let email: String
    public let state: AliasMenuState

    public init(id: Int, email: String, state: AliasMenuState) {
        self.id = id
        self.email = email
        self.state = state
    }
}

public struct MenuSections: Equatable, Sendable {
    public let timedUnpinned: [MenuAliasItem]
    public let pinned: [MenuAliasItem]

    public init(timedUnpinned: [MenuAliasItem], pinned: [MenuAliasItem]) {
        self.timedUnpinned = timedUnpinned
        self.pinned = pinned
    }

    public static func make(pinned: [Alias], records: [TimerRecord], failures: [Int: DisableFailure], now: Date) -> MenuSections {
        let recordsByAliasID = Dictionary(records.map { ($0.aliasID, $0) }, uniquingKeysWith: { first, _ in first })
        let pinnedIDs = Set(pinned.map(\.id))

        let pinnedItems = pinned.map { alias in
            let timerState = recordsByAliasID[alias.id].map { state(of: $0, failure: failures[alias.id], now: now) }
            return MenuAliasItem(id: alias.id, email: alias.email, state: timerState ?? (alias.enabled ? .enabled : .disabled))
        }
        let timedUnpinnedItems = records
            .filter { !pinnedIDs.contains($0.aliasID) }
            .sorted { $0.expiresAt < $1.expiresAt }
            .map { MenuAliasItem(id: $0.aliasID, email: $0.email, state: state(of: $0, failure: failures[$0.aliasID], now: now)) }

        return MenuSections(timedUnpinned: timedUnpinnedItems, pinned: pinnedItems)
    }

    /// A rejected key leaves the alias timed, because the app-wide key notice already says what to do.
    public static func state(of record: TimerRecord, failure: DisableFailure?, now: Date) -> AliasMenuState {
        switch failure {
        case .transient: .disableFailing
        case .forbidden: .disableRefused
        case .unauthorized, nil:
            .timed(
                remaining: max(0, record.expiresAt.timeIntervalSince(now)),
                endsAt: record.expiresAt,
                length: record.expiresAt.timeIntervalSince(record.enabledAt)
            )
        }
    }
}

public enum RemainingTime {
    public static func format(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds).rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secondsPart = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secondsPart)
        }
        return String(format: "%d:%02d", minutes, secondsPart)
    }
}
