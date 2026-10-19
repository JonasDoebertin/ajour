import SwiftUI

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if model.engine.loadError != nil {
            Button("Timer data unreadable") {}
                .disabled(true)
            Divider()
        }
        if model.phase == .signedOut {
            Button("Set Up…") { openWindow.frontmost(id: OnboardingView.windowID) }
            Divider()
        }
        if case .signedIn = model.phase {
            Button("Settings…") {
                openSettings()
                NSApp.activate()
            }
            .keyboardShortcut(",")
            Divider()
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
