import SimpleLoginKit
import SwiftUI

struct OnboardingView: View {
    static let windowID = "onboarding"
    private static let apiKeyPage = URL(string: "https://app.simplelogin.io/dashboard/api_key")!

    @Bindable var model: OnboardingModel
    @State private var clipboardKey: String?
    @State private var launchAtLogin = true
    @Environment(\.openURL) private var openURL
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.step {
            case .explain:
                explanation
            case .enterKey:
                keyEntry
            case .confirm(let userInfo):
                confirmation(of: userInfo)
            case .finish:
                finish
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            offerClipboardKey()
        }
        .onChange(of: model.step, initial: true) {
            offerClipboardKey()
        }
        .onChange(of: model.closesWindow) { _, closesWindow in
            if closesWindow { dismissWindow(id: Self.windowID) }
        }
        .onDisappear {
            model.reset()
            clipboardKey = nil
            launchAtLogin = true
        }
    }

    private var explanation: some View {
        Group {
            Text("Welcome to Ajour")
                .font(.title2.bold())
            Text("The app needs a SimpleLogin API key to enable and disable your aliases. It never sees your password.")
            HStack {
                Spacer()
                Button("Continue") { model.showKeyEntry() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var keyEntry: some View {
        Group {
            Text("Add Your API Key")
                .font(.title2.bold())
            Text("Open SimpleLogin, create a new API key, name it, for example, “Mac”, and copy it.")
            Button("Open SimpleLogin") { openURL(Self.apiKeyPage) }
            SecureField("API key", text: $model.apiKey)
                .onSubmit { submit() }
            if let clipboardKey, model.apiKey.isEmpty {
                Button("Use key from clipboard") { model.apiKey = clipboardKey }
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            HStack {
                if model.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Continue") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSubmit)
            }
        }
    }

    private func confirmation(of userInfo: UserInfo) -> some View {
        Group {
            Text("Signed In")
                .font(.title2.bold())
            LabeledContent("Name", value: userInfo.name)
            LabeledContent("Email", value: userInfo.email)
            HStack {
                Spacer()
                Button("Continue") { model.confirmAccount() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var finish: some View {
        Group {
            Text("You’re All Set")
                .font(.title2.bold())
            Text("Ajour lives in the menu bar.")
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .disabled(model.isFinishing || model.isComplete)
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                if model.isComplete {
                    Button("Close") { dismissWindow(id: Self.windowID) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") {
                        Task { await model.finish(launchAtLogin: launchAtLogin) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isFinishing)
                }
            }
        }
    }

    private func submit() {
        guard model.canSubmit else { return }
        Task { await model.submit() }
    }

    /// Reads the clipboard only while the key is being entered: when that step appears and whenever the user
    /// comes back to the app, for example after copying the key in the browser.
    private func offerClipboardKey() {
        guard model.step == .enterKey else { return }
        clipboardKey = model.clipboardSuggestion(for: NSPasteboard.general.string(forType: .string))
    }
}
