import SwiftUI

@main
struct SimpleLoginMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.engine.hasActiveTimers ? "envelope.badge.fill" : "envelope")
        }
        .menuBarExtraStyle(.menu)
    }
}
