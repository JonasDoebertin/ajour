import Foundation

/// Decides whether an automatic update may relaunch Ajour without cutting into something the user is doing.
///
/// A fresh timer counts as activity because the user has just asked for an alias to be enabled. A menu or window
/// that closed moments ago counts too: the action chosen there may not have started yet.
enum UpdateRestartPolicy {
    static let freshTimerInterval: TimeInterval = 600
    static let interactionGracePeriod: TimeInterval = 60

    static func allowsRestart(
        timerStarts: [Date],
        now: Date,
        isEnabling: Bool,
        hasOpenWindow: Bool,
        isMenuOpen: Bool,
        lastInteractionAt: Date?
    ) -> Bool {
        let hasFreshTimer = timerStarts.contains { now.timeIntervalSince($0) < freshTimerInterval }
        let hasRecentInteraction = lastInteractionAt.map { now.timeIntervalSince($0) < interactionGracePeriod } ?? false
        return !hasFreshTimer && !hasRecentInteraction && !isEnabling && !hasOpenWindow && !isMenuOpen
    }
}
