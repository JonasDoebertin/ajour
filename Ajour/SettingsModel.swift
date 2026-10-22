import Observation
import SimpleLoginKit

@MainActor @Observable final class SettingsModel {
    private(set) var launchAtLogin = false
    private(set) var launchAtLoginError: String?
    var signOutError: String?
    /// Set while sign-out is blocked by aliases that stay enabled, until the person signs out anyway or cancels.
    var blockedSignOut: SignOutError?
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
        await performSignOut { try await appModel.signOut() }
    }

    func signOutAnyway() async {
        blockedSignOut = nil
        await performSignOut { try await appModel.signOutAnyway() }
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
