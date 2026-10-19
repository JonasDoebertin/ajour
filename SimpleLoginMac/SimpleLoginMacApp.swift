import SwiftUI

@main
struct SimpleLoginMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, onboarding: appDelegate.onboarding)
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

        Window("New Alias", id: NewAliasView.windowID) {
            NewAliasView(model: appDelegate.newAlias)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("All Aliases", id: AllAliasesView.windowID) {
            AllAliasesView(model: appDelegate.allAliases, appModel: model)
        }
        .defaultSize(width: 520, height: 600)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(appModel: model, settings: appDelegate.settings, onboarding: appDelegate.onboarding)
        }
    }
}

/// Opens onboarding whenever there is no API key: at launch and after signing out.
/// Keeps the pinned list fresh for each key, and refreshes it whenever the menu opens. The menu's own
/// `onAppear` fires only once, not on every open, so opening is detected through menu tracking.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.engine.hasActiveTimers ? "envelope.badge.fill" : "envelope")
            .task(id: model.session) { await model.keepPinnedFresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                Task { await model.refreshPinned() }
            }
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
