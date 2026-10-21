import SimpleLoginKit
import SwiftUI

struct MenuContent: View {
    let model: AppModel
    let onboarding: OnboardingModel
    let windows: WindowCoordinator

    var body: some View {
        if let lastError = model.lastError {
            Button(Self.errorTitle(for: lastError)) {}
                .disabled(true)
            Divider()
        }
        if model.apiKeyInvalid {
            Button("API key invalid – Re-enter Key…") {
                onboarding.beginKeyReplacement()
                windows.show(.onboarding)
            }
            Divider()
        }
        if model.engine.loadError != nil {
            Button("Timer data unreadable") {}
                .disabled(true)
            Divider()
        }
        if model.phase == .signedOut {
            Button("Set Up…") { windows.show(.onboarding) }
            Divider()
        }
        if case .signedIn = model.phase {
            aliasSections
            aliasCreation
            Divider()
            Button("Settings…") { windows.show(.settings) }
            .keyboardShortcut(",")
            Divider()
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    nonisolated private static let errorTitleLength = 80

    /// A long server message would stretch the whole menu.
    nonisolated static func errorTitle(for message: String) -> String {
        guard message.count > errorTitleLength else { return message }
        return message.prefix(errorTitleLength - 1) + "…"
    }

    /// Timed aliases that aren't pinned come first; pinned aliases with a timer stay in the pinned section.
    @ViewBuilder private var aliasSections: some View {
        let sections = model.menuSections
        if !sections.timedUnpinned.isEmpty {
            ForEach(sections.timedUnpinned) { AliasMenu(item: $0, model: model) }
            Divider()
        }
        if !sections.pinned.isEmpty {
            ForEach(sections.pinned) { AliasMenu(item: $0, model: model) }
            Divider()
        }
    }

    @ViewBuilder private var aliasCreation: some View {
        Button("New Random Alias") {
            Task { await model.createRandomAlias(expiringAfter: nil) }
        }
        Menu("New Random Alias That Expires") {
            ForEach(AliasDuration.allCases, id: \.self) { duration in
                Button("After \(duration.title)") {
                    Task { await model.createRandomAlias(expiringAfter: duration) }
                }
            }
        }
        Button("New Alias…") { windows.show(.newAlias) }
        Button("All Aliases…") { windows.show(.allAliases) }
    }
}

private struct AliasMenu: View {
    let item: MenuAliasItem
    let model: AppModel

    var body: some View {
        Menu(item.menuTitle) {
            Button("Copy Address") { model.copy(email: item.email) }
            Divider()
            Group {
                switch item.state {
                case .disabled:
                    ForEach(AliasDuration.allCases, id: \.self) { duration in
                        Button("Enable for \(duration.title)") {
                            Task { await model.enable(aliasID: item.id, for: duration) }
                        }
                    }
                case .timed:
                    disableNowButton
                    Button("Keep Enabled") {
                        Task { await model.keepEnabled(aliasID: item.id, email: item.email) }
                    }
                    Menu("Extend") {
                        ForEach(AliasDuration.allCases, id: \.self) { duration in
                            Button(duration.title) { model.extend(aliasID: item.id, by: duration) }
                        }
                    }
                case .enabled:
                    disableNowButton
                    ForEach(AliasDuration.allCases, id: \.self) { duration in
                        Button("Disable After \(duration.title)") {
                            Task { await model.disableAfter(aliasID: item.id, duration: duration) }
                        }
                    }
                }
            }
            .disabled(model.isBusy(aliasID: item.id))
        }
    }

    private var disableNowButton: some View {
        Button("Disable Now") {
            Task { await model.disableNow(aliasID: item.id) }
        }
    }
}

extension MenuAliasItem {
    var menuTitle: String {
        let marker = state == .disabled ? "○" : "●"
        guard case .timed(let remaining) = state else { return "\(marker) \(email)" }
        return "\(marker) \(email) · \(RemainingTime.format(remaining)) left"
    }
}
