/// What the menu offers about updates: nothing, an update to look at, or a downloaded update waiting for a restart.
enum UpdateMenuState: Equatable {
    case idle
    case available(version: String)
    case readyToInstall(version: String)
}
