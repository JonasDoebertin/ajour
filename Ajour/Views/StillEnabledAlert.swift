import SwiftUI

/// Asks whether to sign out although aliases stay enabled. A system alert gives a button only one key, so Cancel
/// couldn't answer both Return and Escape there; this sheet looks like one and lets both keys cancel.
struct StillEnabledAlert: View {
    let error: SignOutError
    let signOutAnyway: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(error.title)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                Text(error.userMessage)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                Button(role: .destructive, action: signOutAnyway) {
                    Text("Sign Out Anyway")
                        .foregroundStyle(Palette.color(Palette.danger))
                        .frame(maxWidth: .infinity)
                }
                .tint(Palette.color(Palette.danger))
                Button(action: cancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 260)
        .onExitCommand(perform: cancel)
    }
}
