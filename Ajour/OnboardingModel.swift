import Observation
import SimpleLoginKit

struct OnboardingProgress: Equatable {
    let step: Int
    let total: Int
}

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
    private(set) var isFinishing = false
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

    /// A launch-at-login failure keeps the window open, so the user reads why before closing it.
    var closesWindow: Bool {
        isComplete && errorMessage == nil
    }

    var canSubmit: Bool {
        !trimmedKey.isEmpty && !isSubmitting
    }

    /// Replacing a key shows only the key step and its confirmation, so there is nothing to count.
    var progress: OnboardingProgress? {
        guard !isReplacingKey else { return nil }
        let position = switch step {
        case .explain: 1
        case .enterKey: 2
        case .confirm: 3
        case .finish: 4
        }
        return OnboardingProgress(step: position, total: 4)
    }

    var canGoBack: Bool {
        switch step {
        case .enterKey: !isReplacingKey
        case .confirm: true
        case .explain, .finish: false
        }
    }

    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return "\(first)\(last)".uppercased()
    }

    func showKeyEntry() {
        step = .enterKey
    }

    func goBack() {
        guard canGoBack else { return }
        step = step == .enterKey ? .explain : .enterKey
        errorMessage = nil
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
        } catch APIError.unauthorized {
            errorMessage = "SimpleLogin did not accept this key. Check that you copied all of it, or create a new one."
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

    /// Completes setup even when launch at login can't be changed, for example with ad-hoc signing:
    /// the user can't fix that here, and Settings shows the actual state later.
    func finish(launchAtLogin enabled: Bool) async {
        guard !isFinishing, !isComplete else { return }
        isFinishing = true
        defer { isFinishing = false }
        errorMessage = nil
        if enabled != launchAtLogin.isEnabled() {
            do {
                try launchAtLogin.setEnabled(enabled)
            } catch {
                errorMessage = LaunchAtLoginControl.errorMessage(for: error)
            }
        }
        await requestNotificationAuthorization()
        isComplete = true
    }

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
