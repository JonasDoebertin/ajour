import SwiftUI

/// Asks whether to sign out although aliases stay enabled. A system alert gives a button only one key, so Cancel
/// couldn't answer both Return and Escape there; this sheet looks like one and lets both keys cancel.
struct StillEnabledAlert: View {
    let error: SignOutError
    let signOutAnyway: () -> Void
    let cancel: () -> Void

    /// Focus moves to Cancel whenever the sheet becomes key, which is when macOS would otherwise focus the first
    /// button, so with Full Keyboard Access a press of Space can't sign out by accident.
    @FocusState private var cancelIsFocused: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(error.title)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                // A long list of aliases scrolls instead of pushing the buttons off the screen.
                ScrollView {
                    Text(error.userMessage)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 240)
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
                .focused($cancelIsFocused)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 260)
        .onChange(of: controlActiveState, initial: true) {
            if controlActiveState == .key { cancelIsFocused = true }
        }
        .onExitCommand(perform: cancel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(error.title)
    }
}
