import AppKit
import SimpleLoginKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let onboarding: OnboardingModel
    let settings: SettingsModel
    let newAlias: NewAliasModel
    let allAliases: AllAliasesModel
    let notifications: NotificationController
    let windows: WindowCoordinator

    override init() {
        let model = AppModel(timerStore: Self.makeTimerStore())
        let notifications = NotificationController { aliasID in
            Task { await model.disableNow(aliasID: aliasID) }
        }
        model.onMailArrivals = { $0.forEach(notifications.post) }
        model.onTimerEvents = { $0.forEach(notifications.post) }
        model.onAliasDisabled = { notifications.removeNotifications(aliasID: $0) }
        model.onNewAliasCopied = { notifications.postCopied(email: $0) }
        self.model = model
        self.notifications = notifications
        let onboarding = OnboardingModel(
            appModel: model,
            launchAtLogin: .system,
            requestNotificationAuthorization: { await notifications.requestAuthorization() }
        )
        let settings = SettingsModel(appModel: model, launchAtLogin: .system)
        let newAlias = NewAliasModel(appModel: model)
        let allAliases = AllAliasesModel(appModel: model)
        self.onboarding = onboarding
        self.settings = settings
        self.newAlias = newAlias
        self.allAliases = allAliases
        windows = WindowCoordinator { kind, windows in
            switch kind {
            case .onboarding:
                return NSHostingController.windowContent(
                    OnboardingView(model: onboarding) { [weak windows] in windows?.close(.onboarding) },
                    fitsContent: true
                )
            case .newAlias:
                return NSHostingController.windowContent(
                    NewAliasView(model: newAlias) { [weak windows] in windows?.close(.newAlias) },
                    fitsContent: true
                )
            case .allAliases:
                return NSHostingController.windowContent(
                    AllAliasesView(model: allAliases, appModel: model),
                    fitsContent: false
                )
            case .settings:
                return NSHostingController.windowContent(
                    SettingsView(appModel: model, settings: settings, onboarding: onboarding) { [weak windows] in
                        windows?.show(.onboarding)
                    },
                    fitsContent: true
                )
            }
        }
        super.init()
    }

    /// A click on a notification that launches the app is delivered only to a delegate set this early.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isHostingUnitTests else { return }
        notifications.activate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isHostingUnitTests else { return }
        #if DEBUG
        if KeychainAccessCheck.isRequested { KeychainAccessCheck.run() }
        #endif
        model.start()
    }

    /// Records of aliases that could not be disabled in time stay on disk for the next launch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.needsToDisableBeforeQuitting else { return .terminateNow }
        Task {
            await model.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static func makeTimerStore() -> any TimerStore {
        do {
            return FileTimerStore(fileURL: try FileTimerStore.defaultURL())
        } catch {
            return UnavailableTimerStore(reason: error.localizedDescription)
        }
    }

    /// The test host must not touch the real Keychain item, timer file, or API.
    private static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// Stands in when the timer file's location can't be determined, so the menu reports
/// unreadable timer data instead of the app treating the timer list as empty.
struct UnavailableTimerStore: TimerStore {
    let reason: String

    func load() throws -> [TimerRecord] {
        throw TimerStoreError.unreadable(reason)
    }

    func save(_ records: [TimerRecord]) throws {
        throw TimerStoreError.unreadable(reason)
    }
}
