import SwiftUI

struct SettingsView: View {
    let appModel: AppModel
    let settings: SettingsModel
    let onboarding: OnboardingModel
    let openOnboarding: () -> Void

    @State private var confirmsSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("Account") { account }
            group("General") { general }
            group("About") { about }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .onAppear { settings.refreshLaunchAtLogin() }
        .task { await settings.refreshAccount() }
        .alert("Sign Out of Ajour?", isPresented: $confirmsSignOut) {
            // Not marked destructive: an alert takes Return away from a destructive button.
            Button("Sign Out") {
                Task { await settings.signOut() }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ajour disables aliases with a running timer, then removes the API key from this Mac.")
        }
        .sheet(item: Bindable(settings).blockedSignOut) { error in
            StillEnabledAlert(error: error) {
                settings.signOutAnyway()
            } cancel: {
                settings.blockedSignOut = nil
            }
        }
        .alert("Could Not Sign Out", isPresented: Binding(
            get: { settings.signOutError != nil },
            set: { if !$0 { settings.signOutError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(settings.signOutError ?? "")
        }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            FormGroup { content() }
        }
    }

    @ViewBuilder private var account: some View {
        if appModel.phase == .signedOut {
            HStack {
                Text("Not signed in.")
                Spacer()
                Button("Set Up…") { openOnboarding() }
            }
            .padding(.vertical, 4)
        } else {
            if let userInfo = appModel.userInfo {
                detail("Name", userInfo.name)
                Divider()
                detail("Email", userInfo.email)
            } else {
                Text("Account details are not available right now.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            Divider()
            HStack(spacing: 8) {
                Spacer()
                if settings.isSigningOut {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Replace API Key…") {
                    onboarding.beginKeyReplacement()
                    openOnboarding()
                }
                Button {
                    confirmsSignOut = true
                } label: {
                    Text(settings.isSigningOut ? "Signing Out…" : "Sign Out")
                        .foregroundStyle(Palette.color(Palette.danger))
                }
                .disabled(settings.isSigningOut)
            }
            .padding(.vertical, 6)
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var general: some View {
        HStack {
            Text("Launch at login")
            Spacer()
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.setLaunchAtLogin($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 6)
        if let error = settings.launchAtLoginError {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                InlineError(message: error)
                Button("Open Login Items…") { settings.openLoginItems() }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var about: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ajour")
                    .font(.headline)
                Text(AboutText.tagline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        Divider()
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(AboutText.disclaimer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}
