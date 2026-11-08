import Foundation

/// Decides whether an automatic update may relaunch Ajour without cutting into something the user is doing.
///
/// A fresh timer counts as activity because the user has just asked for an alias to be enabled.
enum UpdateRestartPolicy {
    static let freshTimerInterval: TimeInterval = 600

    static func allowsRestart(
        timerStarts: [Date],
        now: Date,
        isEnabling: Bool,
        hasOpenWindow: Bool,
        isMenuOpen: Bool
    ) -> Bool {
        let hasFreshTimer = timerStarts.contains { now.timeIntervalSince($0) < freshTimerInterval }
        return !hasFreshTimer && !isEnabling && !hasOpenWindow && !isMenuOpen
    }
}
