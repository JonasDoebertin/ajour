import Testing
@testable import Ajour

struct TerminationPlanTests {
    @Test func aRelaunchForAnUpdateKeepsRunningTimers() {
        let plan = TerminationPlan(isRelaunchingForUpdate: true, needsToDisableBeforeQuitting: true)

        #expect(plan == .prepare(disablingTimedAliases: false))
    }

    @Test func aRelaunchForAnUpdateWithoutTimersStillPreparesSoEnablesInFlightAreSaved() {
        let plan = TerminationPlan(isRelaunchingForUpdate: true, needsToDisableBeforeQuitting: false)

        #expect(plan == .prepare(disablingTimedAliases: false))
    }

    @Test func aRegularQuitDisablesTimedAliases() {
        let plan = TerminationPlan(isRelaunchingForUpdate: false, needsToDisableBeforeQuitting: true)

        #expect(plan == .prepare(disablingTimedAliases: true))
    }

    @Test func aRegularQuitWithoutTimersQuitsAtOnce() {
        let plan = TerminationPlan(isRelaunchingForUpdate: false, needsToDisableBeforeQuitting: false)

        #expect(plan == .terminateNow)
    }
}
