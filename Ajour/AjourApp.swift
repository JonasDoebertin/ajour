import SwiftUI

@main
struct AjourApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, onboarding: appDelegate.onboarding, windows: appDelegate.windows)
        } label: {
            MenuBarLabel(model: model, windows: appDelegate.windows)
        }
        .menuBarExtraStyle(.menu)

        // Windows open through `WindowCoordinator`; this scene only routes the Settings shortcut there.
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

/// Opens onboarding whenever there is no API key: at launch and after signing out.
/// Keeps the pinned list fresh for each key, and refreshes it whenever the menu opens. The menu's own
/// `onAppear` fires only once, not on every open, so opening is detected through menu tracking.
private struct MenuBarLabel: View {
    let model: AppModel
    let windows: WindowCoordinator

    var body: some View {
        Image(systemName: model.engine.hasActiveTimers ? "envelope.badge.fill" : "envelope")
            .task(id: model.session) { await model.keepPinnedFresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                Task { await model.refreshPinned() }
            }
            .onChange(of: model.phase, initial: true) { _, phase in
                if phase == .signedOut { windows.show(.onboarding) }
            }
    }
}
