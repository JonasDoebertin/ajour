import Observation
import SimpleLoginKit

@MainActor @Observable final class SettingsModel {
    private(set) var launchAtLogin = false
    private(set) var launchAtLoginError: String?
    var signOutError: String?
    private(set) var isSigningOut = false

    @ObservationIgnored private let appModel: AppModel
    @ObservationIgnored private let launchAtLoginControl: LaunchAtLoginControl

    init(appModel: AppModel, launchAtLogin: LaunchAtLoginControl) {
        self.appModel = appModel
        launchAtLoginControl = launchAtLogin
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
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await appModel.signOut()
        } catch let error as SignOutError {
            signOutError = error.userMessage
        } catch {
            signOutError = "The API key could not be removed from the Keychain."
        }
    }
}
