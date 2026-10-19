import SwiftUI

@main
struct SimpleLoginMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Set Up", id: OnboardingView.windowID) {
            OnboardingView(model: appDelegate.onboarding)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(appModel: model, settings: appDelegate.settings, onboarding: appDelegate.onboarding)
        }
    }
}

/// Opens onboarding whenever there is no API key: at launch and after signing out.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.engine.hasActiveTimers ? "envelope.badge.fill" : "envelope")
            .onChange(of: model.phase, initial: true) { _, phase in
                if phase == .signedOut { openWindow.frontmost(id: OnboardingView.windowID) }
            }
    }
}

extension OpenWindowAction {
    /// A menu bar app isn't active by itself, so without activating, the window opens behind other apps.
    func frontmost(id: String) {
        self(id: id)
        NSApp.activate()
    }
}
