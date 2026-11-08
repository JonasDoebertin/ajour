import Foundation
import Testing
@testable import Ajour

/// When an automatic update may relaunch Ajour without interrupting anything.
struct UpdateRestartPolicyTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func allowsRestart(
        timerStarts: [Date] = [],
        isEnabling: Bool = false,
        hasOpenWindow: Bool = false,
        isMenuOpen: Bool = false
    ) -> Bool {
        UpdateRestartPolicy.allowsRestart(
            timerStarts: timerStarts,
            now: now,
            isEnabling: isEnabling,
            hasOpenWindow: hasOpenWindow,
            isMenuOpen: isMenuOpen
        )
    }

    @Test func noTimersAndNothingOpenAllowsRestart() {
        #expect(allowsRestart())
    }

    @Test func timerStartedNineMinutesAgoBlocksRestart() {
        #expect(!allowsRestart(timerStarts: [now - 540]))
    }

    @Test func timerStartedTenMinutesAgoAllowsRestart() {
        #expect(allowsRestart(timerStarts: [now - 600]))
    }

    @Test func timerStartedInTheFutureIsFresh() {
        #expect(!allowsRestart(timerStarts: [now + 60]))
    }

    @Test func enableInFlightBlocksTheRestart() {
        #expect(!allowsRestart(isEnabling: true))
    }

    @Test func openWindowBlocksRestart() {
        #expect(!allowsRestart(hasOpenWindow: true))
    }

    @Test func openMenuBlocksRestart() {
        #expect(!allowsRestart(isMenuOpen: true))
    }

    @Test func oneFreshTimerAmongOldOnesBlocksRestart() {
        #expect(!allowsRestart(timerStarts: [now - 3600, now - 120]))
    }
}
