import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        if model.engine.loadError != nil {
            Button("Timer data unreadable") {}
                .disabled(true)
            Divider()
        }
        if model.phase == .signedOut {
            Button("Set Up…") {}
            Divider()
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
