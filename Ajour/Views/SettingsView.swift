import SwiftUI

struct SettingsView: View {
    let appModel: AppModel
    let settings: SettingsModel
    let onboarding: OnboardingModel
    let openOnboarding: () -> Void

    var body: some View {
        Form {
            Section("Account") {
                account
            }
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            Section("About") {
                Text(AboutText.tagline)
                Text(AboutText.disclaimer)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { settings.refreshLaunchAtLogin() }
        .task { await settings.refreshAccount() }
        .alert("Could Not Sign Out", isPresented: Binding(
            get: { settings.signOutError != nil },
            set: { if !$0 { settings.signOutError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(settings.signOutError ?? "")
        }
    }

    @ViewBuilder private var account: some View {
        if appModel.phase == .signedOut {
            Text("Not signed in.")
            Button("Set Up…") { openOnboarding() }
        } else {
            if let userInfo = appModel.userInfo {
                LabeledContent("Name", value: userInfo.name)
                LabeledContent("Email", value: userInfo.email)
            } else {
                Text("Account details are not available right now.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Replace API Key…") {
                    onboarding.beginKeyReplacement()
                    openOnboarding()
                }
                Spacer()
                if settings.isSigningOut {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Sign Out") {
                    Task { await settings.signOut() }
                }
                .disabled(settings.isSigningOut)
            }
        }
    }
}
