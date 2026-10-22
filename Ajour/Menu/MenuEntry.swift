import Foundation
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
    var activities: [Int: AliasActivity] = [:]
    var lastErrorIsNetwork = false
    var reducesMotion = false
    var locale: Locale = .current
    var timeZone: TimeZone = .current
}

/// What an alias row shows and speaks.
struct MenuAliasRow: Equatable {
    let id: Int
    let email: String
    let status: AliasStatus
    let accessibilityLabel: String
}

/// Describes the status item menu as data, so it can be tested and compared with what is on screen.
indirect enum MenuEntry: Equatable {
    case header(String)
    case notice(title: String, detail: String?, symbol: String)
    case action(String, MenuAction, symbol: String? = nil, shortcut: String = "", isEnabled: Bool = true)
    case submenu(String, [MenuEntry], symbol: String? = nil, isEnabled: Bool = true)
    case alias(MenuAliasRow, [MenuEntry])
    case separator

    var title: String? {
        switch self {
        case .header(let title), .notice(let title, _, _), .action(let title, _, _, _, _), .submenu(let title, _, _, _): title
        case .alias(let row, _): row.email
        case .separator: nil
        }
    }

    /// Entries with the same layout differ at most in their titles and alias statuses, which can change on screen in place.
    /// A submenu's entries must match exactly, because only the submenu's own title is updated.
    func hasSameLayout(as other: MenuEntry) -> Bool {
        switch (self, other) {
        case (.header, .header), (.notice, .notice), (.separator, .separator):
            true
        case let (.action(_, action, symbol, shortcut, isEnabled), .action(_, otherAction, otherSymbol, otherShortcut, otherIsEnabled)):
            action == otherAction && symbol == otherSymbol && shortcut == otherShortcut && isEnabled == otherIsEnabled
        case let (.submenu(_, entries, symbol, isEnabled), .submenu(_, otherEntries, otherSymbol, otherIsEnabled)):
            entries == otherEntries && symbol == otherSymbol && isEnabled == otherIsEnabled
        case let (.alias(row, entries), .alias(otherRow, otherEntries)):
            row.id == otherRow.id && entries == otherEntries
        default:
            false
        }
    }

    static func entries(for state: MenuState) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        if let lastError = state.lastError {
            entries += [errorNotice(for: lastError, isNetwork: state.lastErrorIsNetwork), .separator]
        }
        if state.apiKeyInvalid {
            entries += [.action("API key invalid – Re-enter Key…", .reEnterAPIKey, symbol: "key"), .separator]
        }
        if state.timerDataUnreadable {
            entries += [.notice(title: "Timer data unreadable", detail: nil, symbol: "exclamationmark.triangle"), .separator]
        }
        if state.phase == .signedOut {
            entries += [
                .notice(title: "Not set up", detail: "Add a SimpleLogin API key to manage your aliases.", symbol: "key"),
                .action("Set Up…", .setUp, symbol: "person.badge.key"),
                .separator,
            ]
        }
        if case .signedIn = state.phase {
            entries += aliasSections(state)
            entries += aliasCreation
            entries += [.separator, .action("Settings…", .openSettings, symbol: "gearshape", shortcut: ","), .separator]
        }
        entries.append(.action("Quit", .quit, symbol: "power", shortcut: "q"))
        return entries
    }

    private static let lineLength = 80

    /// A long server message would stretch the whole menu.
    private static func truncated(_ text: String) -> String {
        guard text.count > lineLength else { return text }
        return text.prefix(lineLength - 1) + "…"
    }

    private static func errorNotice(for message: String, isNetwork: Bool) -> MenuEntry {
        let problem = ProblemMessage(message)
        return .notice(
            title: truncated(problem.title),
            detail: problem.detail.map(truncated),
            symbol: isNetwork ? "wifi.slash" : "exclamationmark.triangle"
        )
    }

    private static let noPinnedAliases = MenuEntry.notice(
        title: "No pinned aliases yet",
        detail: "Open All Aliases, right-click an alias and choose Pin to keep it here.",
        symbol: "pin"
    )

    /// Timed aliases that aren't pinned come first; pinned aliases with a timer stay in the pinned section.
    private static func aliasSections(_ state: MenuState) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        if !state.sections.timedUnpinned.isEmpty {
            entries += [.header("Timers")] + aliasRows(state.sections.timedUnpinned, pinned: false, state: state) + [.separator]
        }
        entries.append(.header("Pinned"))
        entries += state.sections.pinned.isEmpty ? [noPinnedAliases] : aliasRows(state.sections.pinned, pinned: true, state: state)
        entries.append(.separator)
        return entries
    }

    private static func aliasRows(_ items: [MenuAliasItem], pinned: Bool, state: MenuState) -> [MenuEntry] {
        items.map { alias($0, pinned: pinned, state: state) }
    }

    private static let aliasCreation: [MenuEntry] = [
        .action("New Random Alias", .createRandomAlias(expiringAfter: nil), symbol: "dice"),
        .submenu("New Random Alias That Expires", [.header("Expires After")] + durationActions(symbol: "timer") {
            .createRandomAlias(expiringAfter: $0)
        }, symbol: "timer"),
        .action("New Alias…", .openNewAlias, symbol: "square.and.pencil"),
        .action("All Aliases…", .openAllAliases, symbol: "list.bullet"),
    ]

    /// Only the first item of a group carries the symbol.
    private static func durationActions(
        symbol: String,
        titlePrefix: String = "",
        isEnabled: Bool = true,
        action: (AliasDuration) -> MenuAction
    ) -> [MenuEntry] {
        AliasDuration.allCases.enumerated().map { index, duration in
            .action(titlePrefix + duration.title, action(duration), symbol: index == 0 ? symbol : nil, isEnabled: isEnabled)
        }
    }

    static func alias(_ item: MenuAliasItem, pinned: Bool, state: MenuState) -> MenuEntry {
        let activity = state.activities[item.id]
        let row = MenuAliasRow(
            id: item.id,
            email: item.email,
            status: AliasStatus.make(
                state: item.state,
                activity: activity,
                reducesMotion: state.reducesMotion,
                locale: state.locale,
                timeZone: state.timeZone
            ),
            accessibilityLabel: AliasStatus.accessibilityLabel(
                email: item.email,
                pinned: pinned,
                state: item.state,
                activity: activity,
                locale: state.locale,
                timeZone: state.timeZone
            )
        )
        let copy = MenuEntry.action("Copy Address", .copy(email: item.email), symbol: "doc.on.doc")
        return .alias(row, [copy, .separator] + changes(of: item, isEnabled: activity == nil))
    }

    private static func changes(of item: MenuAliasItem, isEnabled: Bool) -> [MenuEntry] {
        let disableNow = MenuEntry.action("Disable Now", .disableNow(aliasID: item.id), symbol: "poweroff", isEnabled: isEnabled)
        switch item.state {
        case .disabled:
            return durationActions(symbol: "timer", titlePrefix: "Enable for ", isEnabled: isEnabled) {
                .enable(aliasID: item.id, duration: $0)
            }
        case .timed:
            return [
                disableNow,
                .action("Keep Enabled", .keepEnabled(aliasID: item.id, email: item.email), symbol: "infinity", isEnabled: isEnabled),
                .submenu("Extend", [.header("Extend By")] + durationActions(symbol: "timer") {
                    .extend(aliasID: item.id, duration: $0)
                }, symbol: "goforward.plus", isEnabled: isEnabled),
            ]
        case .enabled:
            return [disableNow] + durationActions(symbol: "timer", titlePrefix: "Disable After ", isEnabled: isEnabled) {
                .disableAfter(aliasID: item.id, duration: $0)
            }
        }
    }
}
