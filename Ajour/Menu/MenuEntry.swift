import SimpleLoginKit

enum MenuAction: Equatable {
    case setUp
    case reEnterAPIKey
    case openSettings
    case quit
    case createRandomAlias(expiringAfter: AliasDuration?)
    case openNewAlias
    case openAllAliases
    case copy(email: String)
    case enable(aliasID: Int, duration: AliasDuration)
    case disableNow(aliasID: Int)
    case keepEnabled(aliasID: Int, email: String)
    case extend(aliasID: Int, duration: AliasDuration)
    case disableAfter(aliasID: Int, duration: AliasDuration)
}

/// Everything the menu shows, taken from the app model at one moment.
struct MenuState {
    var phase: AppModel.Phase
    var lastError: String?
    var apiKeyInvalid = false
    var timerDataUnreadable = false
    var sections = MenuSections(timedUnpinned: [], pinned: [])
    var busyAliasIDs: Set<Int> = []
}

/// Describes the status item menu as data, so it can be tested and compared with what is on screen.
indirect enum MenuEntry: Equatable {
    case notice(String)
    case action(String, MenuAction, shortcut: String = "", isEnabled: Bool = true)
    case submenu(String, [MenuEntry], isEnabled: Bool = true)
    case separator

    var title: String? {
        switch self {
        case .notice(let title), .action(let title, _, _, _), .submenu(let title, _, _): title
        case .separator: nil
        }
    }

    /// Entries with the same layout differ at most in their titles, which can change on screen in place.
    /// A submenu's entries must match exactly, because only the submenu's own title is updated.
    func hasSameLayout(as other: MenuEntry) -> Bool {
        switch (self, other) {
        case (.notice, .notice), (.separator, .separator):
            true
        case let (.action(_, action, shortcut, isEnabled), .action(_, otherAction, otherShortcut, otherIsEnabled)):
            action == otherAction && shortcut == otherShortcut && isEnabled == otherIsEnabled
        case let (.submenu(_, entries, isEnabled), .submenu(_, otherEntries, otherIsEnabled)):
            entries == otherEntries && isEnabled == otherIsEnabled
        default:
            false
        }
    }

    static func entries(for state: MenuState) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        if let lastError = state.lastError {
            entries += [.notice(errorTitle(for: lastError)), .separator]
        }
        if state.apiKeyInvalid {
            entries += [.action("API key invalid – Re-enter Key…", .reEnterAPIKey), .separator]
        }
        if state.timerDataUnreadable {
            entries += [.notice("Timer data unreadable"), .separator]
        }
        if state.phase == .signedOut {
            entries += [.action("Set Up…", .setUp), .separator]
        }
        if case .signedIn = state.phase {
            entries += aliasSections(state)
            entries += aliasCreation
            entries += [.separator, .action("Settings…", .openSettings, shortcut: ","), .separator]
        }
        entries.append(.action("Quit", .quit, shortcut: "q"))
        return entries
    }

    private static let errorTitleLength = 80

    /// A long server message would stretch the whole menu.
    static func errorTitle(for message: String) -> String {
        guard message.count > errorTitleLength else { return message }
        return message.prefix(errorTitleLength - 1) + "…"
    }

    /// Timed aliases that aren't pinned come first; pinned aliases with a timer stay in the pinned section.
    private static func aliasSections(_ state: MenuState) -> [MenuEntry] {
        [state.sections.timedUnpinned, state.sections.pinned]
            .filter { !$0.isEmpty }
            .flatMap { items in
                items.map { alias($0, isBusy: state.busyAliasIDs.contains($0.id)) } + [.separator]
            }
    }

    private static var aliasCreation: [MenuEntry] {
        [
            .action("New Random Alias", .createRandomAlias(expiringAfter: nil)),
            .submenu("New Random Alias That Expires", AliasDuration.allCases.map { duration in
                .action("After \(duration.title)", .createRandomAlias(expiringAfter: duration))
            }),
            .action("New Alias…", .openNewAlias),
            .action("All Aliases…", .openAllAliases),
        ]
    }

    static func alias(_ item: MenuAliasItem, isBusy: Bool) -> MenuEntry {
        .submenu(item.menuTitle, [.action("Copy Address", .copy(email: item.email)), .separator] + changes(of: item, isEnabled: !isBusy))
    }

    private static func changes(of item: MenuAliasItem, isEnabled: Bool) -> [MenuEntry] {
        let disableNow = MenuEntry.action("Disable Now", .disableNow(aliasID: item.id), isEnabled: isEnabled)
        switch item.state {
        case .disabled:
            return AliasDuration.allCases.map { duration in
                .action("Enable for \(duration.title)", .enable(aliasID: item.id, duration: duration), isEnabled: isEnabled)
            }
        case .timed:
            return [
                disableNow,
                .action("Keep Enabled", .keepEnabled(aliasID: item.id, email: item.email), isEnabled: isEnabled),
                .submenu("Extend", AliasDuration.allCases.map { duration in
                    .action(duration.title, .extend(aliasID: item.id, duration: duration))
                }, isEnabled: isEnabled),
            ]
        case .enabled:
            return [disableNow] + AliasDuration.allCases.map { duration in
                .action("Disable After \(duration.title)", .disableAfter(aliasID: item.id, duration: duration), isEnabled: isEnabled)
            }
        }
    }
}

extension MenuAliasItem {
    var menuTitle: String {
        let marker = state == .disabled ? "○" : "●"
        guard case .timed(let remaining, _, _) = state else { return "\(marker) \(email)" }
        return "\(marker) \(email) · \(RemainingTime.format(remaining)) left"
    }
}
