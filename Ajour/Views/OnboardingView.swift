import SimpleLoginKit
import SwiftUI

struct OnboardingView: View {
    private static let apiKeyPage = URL(string: "https://app.simplelogin.io/dashboard/api_key")!

    @Bindable var model: OnboardingModel
    let close: () -> Void
    @State private var clipboardKey: String?
    @State private var launchAtLogin = true
    @Environment(\.openURL) private var openURL

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
            if closesWindow { close() }
        }
        .onDisappear {
            model.reset()
            clipboardKey = nil
            launchAtLogin = true
        }
    }

    private var explanation: some View {
        Group {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text("Welcome to Ajour")
                    .font(.system(size: 24, weight: .bold))
                Text(AboutText.tagline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            FormGroup {
                Feature(symbol: "timer", title: "Open an alias for a moment", detail: "Enable it for 5 minutes, 1 hour or 24 hours.")
                Divider()
                Feature(symbol: "bell", title: "Know when mail arrives", detail: "Disable it right from the notification.")
                Divider()
                Feature(symbol: "lock", title: "It closes on its own", detail: "When the time is up, the alias turns off again.")
            }
            Text("Ajour needs a SimpleLogin API key to enable and disable your aliases. It never sees your password.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            footer {
                Button("Continue") { model.showKeyEntry() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var keyEntry: some View {
        Group {
            heading("Add Your API Key", detail: "In SimpleLogin, open API Keys, create a key named “Ajour” and paste it below.")
            Button {
                openURL(Self.apiKeyPage)
            } label: {
                HStack(spacing: 6) {
                    Text("Open SimpleLogin")
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(.bordered)
            FormGroup {
                LabeledContent("API Key") {
                    SecureField("API Key", text: $model.apiKey, prompt: Text("Paste key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .overlay {
                            if model.errorMessage != nil {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Palette.color(Palette.danger), lineWidth: 1.5)
                            }
                        }
                        .onSubmit { submit() }
                }
                .padding(.vertical, 4)
            }
            if let clipboardKey, model.apiKey.isEmpty {
                clipboardCard(for: clipboardKey)
            }
            if let errorMessage = model.errorMessage {
                InlineError(message: errorMessage)
            }
            footer {
                if model.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking key…")
                        .foregroundStyle(.secondary)
                }
                backButton
                Button("Continue") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSubmit)
            }
        }
    }

    private func clipboardCard(for key: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(Palette.color(Palette.accentText))
                .accessibilityHidden(true)
            Text("API key on clipboard")
                .fontWeight(.semibold)
            Spacer()
            Button("Use Key from Clipboard") { model.apiKey = key }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func confirmation(of userInfo: UserInfo) -> some View {
        Group {
            heading("Signed In", detail: "Ajour can now manage the aliases of this account.")
            FormGroup {
                HStack(spacing: 12) {
                    Text(OnboardingModel.initials(of: userInfo.name))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.color(Palette.accentText))
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(userInfo.name)
                            .font(.title3.bold())
                        Text(userInfo.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    KeyAcceptedBadge()
                }
                .padding(.vertical, 4)
            }
            footer {
                backButton
                Button("Continue") { model.confirmAccount() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var finish: some View {
        Group {
            heading("You’re All Set", detail: "Ajour lives in the menu bar. Click the envelope to open an alias for a moment.")
            MenuBarIllustration()
            FormGroup {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .disabled(model.isFinishing || model.isComplete)
            }
            if let errorMessage = model.errorMessage {
                InlineError(message: errorMessage)
            }
            footer {
                if model.isComplete {
                    Button("Close") { close() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") {
                        Task { await model.finish(launchAtLogin: launchAtLogin) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isFinishing)
                }
            }
        }
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var backButton: some View {
        if model.canGoBack {
            Button("Back") { model.goBack() }
                .buttonStyle(.bordered)
                .disabled(model.isSubmitting)
        }
    }

    private func footer(@ViewBuilder buttons: () -> some View) -> some View {
        HStack(spacing: 8) {
            if let progress = model.progress {
                ProgressDots(progress: progress)
            }
            Spacer()
            buttons()
        }
        .controlSize(.large)
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

private struct Feature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Palette.color(Palette.accentText))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct KeyAcceptedBadge: View {
    var body: some View {
        Label("Key accepted", systemImage: "checkmark.circle")
            .font(.callout.weight(.medium))
            .foregroundStyle(Palette.color(Palette.stateOn))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.color(Palette.stateOn).opacity(0.12), in: Capsule())
    }
}

private struct ProgressDots: View {
    let progress: OnboardingProgress

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...progress.total, id: \.self) { step in
                Capsule()
                    .fill(step <= progress.step ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: step == progress.step ? 16 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(progress.step) of \(progress.total)")
    }
}

/// A stand-in for the menu bar that points out where Ajour lives.
private struct MenuBarIllustration: View {
    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            Image("MenuBarGlyphIdle")
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 1.5))
            Image(systemName: "wifi")
            Text(Date.now, format: .dateTime.hour().minute())
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}
