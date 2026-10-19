import Foundation

public enum AliasMenuState: Equatable, Sendable {
    case disabled
    case enabled
    case timed(remaining: TimeInterval)
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

    public static func make(pinned: [Alias], records: [TimerRecord], now: Date) -> MenuSections {
        let recordsByAliasID = Dictionary(records.map { ($0.aliasID, $0) }, uniquingKeysWith: { first, _ in first })
        let pinnedIDs = Set(pinned.map(\.id))

        let pinnedItems = pinned.map { alias in
            MenuAliasItem(id: alias.id, email: alias.email, state: state(of: alias, record: recordsByAliasID[alias.id], now: now))
        }
        let timedUnpinnedItems = records
            .filter { !pinnedIDs.contains($0.aliasID) }
            .sorted { $0.expiresAt < $1.expiresAt }
            .map { MenuAliasItem(id: $0.aliasID, email: $0.email, state: timedState(of: $0, now: now)) }

        return MenuSections(timedUnpinned: timedUnpinnedItems, pinned: pinnedItems)
    }

    private static func state(of alias: Alias, record: TimerRecord?, now: Date) -> AliasMenuState {
        if let record { return timedState(of: record, now: now) }
        return alias.enabled ? .enabled : .disabled
    }

    private static func timedState(of record: TimerRecord, now: Date) -> AliasMenuState {
        .timed(remaining: max(0, record.expiresAt.timeIntervalSince(now)))
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
