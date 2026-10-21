import SwiftUI

@main
struct AjourApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item and the windows come from AppKit; this scene only routes the Settings shortcut there.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.windows.show(.settings) }
                    .keyboardShortcut(",")
            }
        }
    }
}
