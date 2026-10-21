import AppKit
import Observation

/// Puts the app's menu in the menu bar. Unlike SwiftUI's `MenuBarExtra`, an AppKit menu can change while it is
/// open, so countdowns keep running and the pinned list refreshed on opening shows up right away.
@MainActor final class StatusMenuController: NSObject, NSMenuDelegate {
    private static let liveUpdateInterval: TimeInterval = 0.25

    private let model: AppModel
    private let onboarding: OnboardingModel
    private let windows: WindowCoordinator
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private lazy var renderer = MenuRenderer(menu: menu) { [weak self] in self?.perform($0) }
    private var liveUpdates: Timer?
    private var iconUpdates: Task<Void, Never>?

    init(model: AppModel, onboarding: OnboardingModel, windows: WindowCoordinator) {
        self.model = model
        self.onboarding = onboarding
        self.windows = windows
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        iconUpdates = Task { [weak self, model] in
            for await hasActiveTimers in Observations({ model.engine.hasActiveTimers }) {
                self?.showIcon(hasActiveTimers: hasActiveTimers)
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        showCurrentEntries()
    }

    /// Menu tracking runs the run loop in its own mode, so the timer is added for all common modes.
    func menuWillOpen(_ menu: NSMenu) {
        Task { await model.refreshPinned() }
        let timer = Timer(timeInterval: Self.liveUpdateInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.showCurrentEntries() }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveUpdates = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        liveUpdates?.invalidate()
        liveUpdates = nil
    }

    private func showCurrentEntries() {
        renderer.show(MenuEntry.entries(for: model.menuState(at: .now)))
    }

    private func showIcon(hasActiveTimers: Bool) {
        statusItem.button?.image = NSImage(
            systemSymbolName: hasActiveTimers ? "envelope.badge.fill" : "envelope",
            accessibilityDescription: "Ajour"
        )
    }

    private func perform(_ action: MenuAction) {
        switch action {
        case .setUp:
            windows.show(.onboarding)
        case .reEnterAPIKey:
            onboarding.beginKeyReplacement()
            windows.show(.onboarding)
        case .openSettings:
            windows.show(.settings)
        case .quit:
            NSApp.terminate(nil)
        case .createRandomAlias(let duration):
            Task { await model.createRandomAlias(expiringAfter: duration) }
        case .openNewAlias:
            windows.show(.newAlias)
        case .openAllAliases:
            windows.show(.allAliases)
        case .copy(let email):
            model.copy(email: email)
        case let .enable(aliasID, duration):
            Task { await model.enable(aliasID: aliasID, for: duration) }
        case .disableNow(let aliasID):
            Task { await model.disableNow(aliasID: aliasID) }
        case let .keepEnabled(aliasID, email):
            Task { await model.keepEnabled(aliasID: aliasID, email: email) }
        case let .extend(aliasID, duration):
            model.extend(aliasID: aliasID, by: duration)
        case let .disableAfter(aliasID, duration):
            Task { await model.disableAfter(aliasID: aliasID, duration: duration) }
        }
    }
}
