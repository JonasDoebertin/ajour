/// Lets onboarding and settings change how updates install without touching the real updater in tests.
struct UpdatesControl {
    var installsAutomatically: () -> Bool
    var setInstallsAutomatically: (Bool) -> Void
    var canCheckForUpdates: () -> Bool
    var checkForUpdates: () -> Void
    var menuState: () -> UpdateMenuState
    var restartToUpdate: () -> Void
}
