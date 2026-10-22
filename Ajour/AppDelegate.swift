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
    private var statusMenu: StatusMenuController?

    override init() {
        let model = Self.makeAppModel()
        let notifications = NotificationController { aliasID in
            Task { await model.disableNow(aliasID: aliasID) }
        }
        model.onMailArrivals = { arrivals in
            for arrival in arrivals {
                notifications.post(arrival, turnsOffAt: model.engine.record(for: arrival.aliasID)?.expiresAt)
            }
        }
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
                return WindowContent.hosting(
                    OnboardingView(model: onboarding) { [weak windows] in windows?.close(.onboarding) },
                    fitsContent: true
                )
            case .newAlias:
                return WindowContent.hosting(
                    NewAliasView(model: newAlias) { [weak windows] in windows?.close(.newAlias) },
                    fitsContent: true
                )
            case .allAliases:
                return WindowContent.hosting(
                    AllAliasesView(model: allAliases, appModel: model) { [weak windows] in
                        windows?.show(.newAlias)
                    },
                    fitsContent: false
                )
            case .settings:
                return WindowContent.hosting(
                    SettingsView(appModel: model, settings: settings, onboarding: onboarding) { [weak windows] in
                        windows?.show(.onboarding)
                    },
                    fitsContent: true
                )
            }
        }
        allAliases.onReplaceAPIKey = { [weak windows] in
            onboarding.beginKeyReplacement()
            windows?.show(.onboarding)
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
        statusMenu = StatusMenuController(model: model, onboarding: onboarding, windows: windows)
        followSession()
    }

    /// Opens onboarding whenever there is no API key, at launch and after signing out, and keeps the pinned
    /// list fresh for each key.
    private func followSession() {
        Task { [model, windows] in
            var previousPhase: AppModel.Phase?
            for await phase in Observations({ model.phase }) where phase != previousPhase {
                previousPhase = phase
                if phase == .signedOut { windows.show(.onboarding) }
            }
        }
        Task { [model] in
            var previousSession: Int?
            var pinnedRefresh: Task<Void, Never>?
            for await session in Observations({ model.session }) where session != previousSession {
                previousSession = session
                pinnedRefresh?.cancel()
                pinnedRefresh = Task { await model.keepPinnedFresh() }
            }
        }
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

    private static func makeAppModel() -> AppModel {
        #if DEBUG
        if DemoMode.isEnabled { return DemoMode.makeAppModel() }
        #endif
        return AppModel(timerStore: makeTimerStore())
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
