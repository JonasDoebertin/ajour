import AppKit
import SimpleLoginKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let onboarding: OnboardingModel
    let settings: SettingsModel
    let newAlias: NewAliasModel
    let allAliases: AllAliasesModel
    let notifications: NotificationController

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
        onboarding = OnboardingModel(
            appModel: model,
            launchAtLogin: .system,
            requestNotificationAuthorization: { await notifications.requestAuthorization() }
        )
        settings = SettingsModel(appModel: model, launchAtLogin: .system)
        newAlias = NewAliasModel(appModel: model)
        allAliases = AllAliasesModel(appModel: model)
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
