/// Lets onboarding and settings change how updates install without touching the real updater in tests.
struct UpdatesControl {
    var installsAutomatically: () -> Bool
    var setInstallsAutomatically: (Bool) -> Void
    var checkForUpdates: () -> Void
}
