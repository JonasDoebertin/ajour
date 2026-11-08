/// What has to happen before Ajour quits. A relaunch for an update keeps every timer, so its aliases stay enabled
/// across the restart; it still prepares, so enables in flight save their timers. Any other quit disables timed
/// aliases first.
enum TerminationPlan: Equatable {
    case terminateNow
    case prepare(disablingTimedAliases: Bool)

    init(isRelaunchingForUpdate: Bool, needsToDisableBeforeQuitting: Bool) {
        if isRelaunchingForUpdate {
            self = .prepare(disablingTimedAliases: false)
        } else if needsToDisableBeforeQuitting {
            self = .prepare(disablingTimedAliases: true)
        } else {
            self = .terminateNow
        }
    }
}
