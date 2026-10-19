import Observation
import SimpleLoginKit

/// Guides through saving an API key. Nothing is submitted without the user pressing Continue.
@MainActor @Observable final class OnboardingModel {
    enum Step: Equatable {
        case explain, enterKey, confirm(UserInfo), finish
    }

    private(set) var step: Step = .explain
    var apiKey = ""
    private(set) var errorMessage: String?
    private(set) var isSubmitting = false
    private(set) var isComplete = false
    /// Replacing a key skips the final step, so it can't override the launch-at-login choice made in Settings.
    @ObservationIgnored private var isReplacingKey = false

    @ObservationIgnored private let appModel: AppModel
    @ObservationIgnored private let launchAtLogin: LaunchAtLoginControl
    @ObservationIgnored private let requestNotificationAuthorization: @MainActor () async -> Void

    init(
        appModel: AppModel,
        launchAtLogin: LaunchAtLoginControl,
        requestNotificationAuthorization: @escaping @MainActor () async -> Void
    ) {
        self.appModel = appModel
        self.launchAtLogin = launchAtLogin
        self.requestNotificationAuthorization = requestNotificationAuthorization
    }

    var canSubmit: Bool {
        !trimmedKey.isEmpty && !isSubmitting
    }

    func showKeyEntry() {
        step = .enterKey
    }

    func beginKeyReplacement() {
        reset()
        isReplacingKey = true
        step = .enterKey
    }

    func reset() {
        step = .explain
        apiKey = ""
        errorMessage = nil
        isComplete = false
        isReplacingKey = false
    }

    /// Offers the clipboard only while the field is empty, so it never replaces what the user typed.
    func clipboardSuggestion(for clipboardText: String?) -> String? {
        guard apiKey.isEmpty, let clipboardText, APIKeyFormat.looksLikeAPIKey(clipboardText) else { return nil }
        return clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            step = .confirm(try await appModel.signIn(apiKey: trimmedKey))
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "The API key could not be saved to the Keychain."
        }
    }

    func confirmAccount() {
        if isReplacingKey {
            isComplete = true
        } else {
            step = .finish
        }
    }

    func finish(launchAtLogin enabled: Bool) async {
        errorMessage = nil
        if enabled != launchAtLogin.isEnabled() {
            do {
                try launchAtLogin.setEnabled(enabled)
            } catch {
                errorMessage = LaunchAtLoginControl.errorMessage(for: error)
                return
            }
        }
        await requestNotificationAuthorization()
        isComplete = true
    }

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
