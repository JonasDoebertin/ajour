import AppIntents

struct AjourShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EnableAliasIntent(),
            phrases: ["Enable alias in \(.applicationName)", "Enable an alias in \(.applicationName)"],
            shortTitle: "Enable Alias",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: CreateRandomAliasIntent(),
            phrases: ["Create random alias in \(.applicationName)", "Create a random alias in \(.applicationName)"],
            shortTitle: "Create Random Alias",
            systemImageName: "dice"
        )
        AppShortcut(
            intent: DisableAliasIntent(),
            phrases: ["Disable alias in \(.applicationName)", "Disable an alias in \(.applicationName)"],
            shortTitle: "Disable Alias",
            systemImageName: "poweroff"
        )
    }
}
