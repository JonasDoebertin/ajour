import Observation
import SimpleLoginKit

@MainActor @Observable final class SettingsModel {
    /// Offers what the menu does: a downloaded update restarts, otherwise a check, which Sparkle can't start while it
    /// shows an update or downloads one in the background.
    enum UpdateButton: Equatable {
        case checkForUpdates(isEnabled: Bool)
        case restartToUpdate
    }

    private(set) var launchAtLogin = false
    private(set) var launchAtLoginError: String?
    private(set) var installsUpdatesAutomatically = true
    var signOutError: String?
    /// Set while sign-out is blocked by aliases that stay enabled, until the person signs out anyway or cancels.
    var blockedSignOut: SignOutError?
    private(set) var isSigningOut = false

    @ObservationIgnored private let appModel: AppModel
    @ObservationIgnored private let launchAtLoginControl: LaunchAtLoginControl

    @ObservationIgnored private let updates: UpdatesControl?

    init(appModel: AppModel, launchAtLogin: LaunchAtLoginControl, updates: UpdatesControl?) {
        self.appModel = appModel
        launchAtLoginControl = launchAtLogin
        self.updates = updates
        refreshInstallsUpdatesAutomatically()
    }

    /// Debug builds and the test host have no updater, so there is nothing to offer.
    var offersUpdates: Bool {
        updates != nil
    }

    func refreshInstallsUpdatesAutomatically() {
        installsUpdatesAutomatically = updates?.installsAutomatically() ?? true
    }

    func setInstallsUpdatesAutomatically(_ enabled: Bool) {
        updates?.setInstallsAutomatically(enabled)
        refreshInstallsUpdatesAutomatically()
    }

    /// Reads the updater each time, so the button follows it while Settings stays open.
    var updateButton: UpdateButton {
        guard let updates else { return .checkForUpdates(isEnabled: false) }
        if case .readyToInstall = updates.menuState() { return .restartToUpdate }
        return .checkForUpdates(isEnabled: updates.canCheckForUpdates())
    }

    func checkForUpdates() {
        updates?.checkForUpdates()
    }

    func restartToUpdate() {
        updates?.restartToUpdate()
    }

    /// Retries the account load when it failed earlier, for example while offline at launch.
    func refreshAccount() async {
        guard appModel.phase == .signedIn(nil) else { return }
        await appModel.loadUserInfo()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = launchAtLoginControl.isEnabled()
    }

    /// Shows the actual state afterwards, so a refused change doesn't leave the toggle on.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginControl.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = LaunchAtLoginControl.errorMessage(enabling: enabled)
        }
        refreshLaunchAtLogin()
    }

    func openLoginItems() {
        launchAtLoginControl.openSettings()
    }

    func signOut() async {
        await performSignOut { try await appModel.signOut() }
    }

    /// Answers a blocked sign-out once: a second click while the sheet closes finds nothing left to answer.
    @discardableResult
    func signOutAnyway() -> Task<Void, Never>? {
        guard blockedSignOut != nil else { return nil }
        blockedSignOut = nil
        return Task { await performSignOut { try await appModel.signOutAnyway() } }
    }

    private func performSignOut(_ signOut: () async throws -> Void) async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await signOut()
        } catch let error as SignOutError {
            switch error {
            case .aliasesStillEnabled: blockedSignOut = error
            case .timerDataUnreadable, .timersNotSaved: signOutError = error.userMessage
            }
        } catch {
            signOutError = "The API key could not be removed from the Keychain."
        }
    }
}
