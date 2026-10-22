import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

struct MenuEntryTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let german = Locale(identifier: "de_DE")
    private let endsAt = Date(timeIntervalSince1970: 1_792_000_000)

    private func state(
        phase: AppModel.Phase = .signedIn(nil),
        lastError: String? = nil,
        lastErrorIsNetwork: Bool = false,
        sections: MenuSections = MenuSections(timedUnpinned: [], pinned: []),
        pinnedLoaded: Bool = true,
        activities: [Int: Ajour.AliasActivity] = [:],
        reducesMotion: Bool = false
    ) -> MenuState {
        MenuState(
            phase: phase,
            lastError: lastError,
            sections: sections,
            pinnedLoaded: pinnedLoaded,
            activities: activities,
            lastErrorIsNetwork: lastErrorIsNetwork,
            reducesMotion: reducesMotion,
            locale: german,
            timeZone: berlin
        )
    }

    private func entry(for item: MenuAliasItem, pinned: Bool = false, activity: Ajour.AliasActivity? = nil) -> MenuEntry {
        let activities = activity.map { [item.id: $0] } ?? [:]
        return MenuEntry.alias(item, pinned: pinned, state: state(activities: activities))
    }

    private func children(of entry: MenuEntry) -> [MenuEntry] {
        guard case .alias(_, let children) = entry else { return [] }
        return children
    }

    private func row(of entry: MenuEntry) -> MenuAliasRow? {
        guard case .alias(let row, _) = entry else { return nil }
        return row
    }

    private let timedItem = MenuAliasItem(id: 7, email: "shop@example.com", state: .timed(remaining: 60, endsAt: Date(timeIntervalSince1970: 60), length: 300))
    private let copyAddress = MenuEntry.action("Copy Address", .copy(email: "shop@example.com"), symbol: "doc.on.doc")

    @Test func signedOutExplainsSetup() {
        let entries = MenuEntry.entries(for: state(phase: .signedOut))

        #expect(entries == [
            .notice(title: "Not set up", detail: "Add a SimpleLogin API key to manage your aliases.", symbol: "key"),
            .action("Set Up…", .setUp, symbol: "person.badge.key"),
            .separator,
            .action("Quit", .quit, symbol: "power", shortcut: "q"),
        ])
    }

    @Test func loadingOffersOnlyQuit() {
        let entries = MenuEntry.entries(for: state(phase: .loading))

        #expect(entries == [.action("Quit", .quit, symbol: "power", shortcut: "q")])
    }

    @Test func problemsComeFirst() {
        let menuState = MenuState(
            phase: .loading,
            lastError: String(repeating: "a", count: 81),
            apiKeyInvalid: true,
            timerDataUnreadable: true
        )

        let entries = MenuEntry.entries(for: menuState)

        #expect(entries == [
            .notice(title: String(repeating: "a", count: 79) + "…", detail: nil, symbol: "exclamationmark.triangle", tone: .danger),
            .action("API key invalid – Re-enter Key…", .reEnterAPIKey, symbol: "key", tone: .danger),
            .notice(title: "Timer data unreadable", detail: nil, symbol: "exclamationmark.triangle", tone: .danger),
            .separator,
            .action("Quit", .quit, symbol: "power", shortcut: "q"),
        ])
    }

    @Test func aShortErrorTitleAndDetailAreShownInFull() {
        let message = String(repeating: "a", count: 79) + ". " + String(repeating: "b", count: 80)

        let entries = MenuEntry.entries(for: state(phase: .loading, lastError: message))

        #expect(entries.first == .notice(
            title: String(repeating: "a", count: 79) + ".",
            detail: String(repeating: "b", count: 80),
            symbol: "exclamationmark.triangle",
            tone: .danger
        ))
    }

    @Test func aLongErrorDetailIsShortenedToEightyCharacters() {
        let message = "Something failed. " + String(repeating: "b", count: 81)

        let entries = MenuEntry.entries(for: state(phase: .loading, lastError: message))

        #expect(entries.first == .notice(
            title: "Something failed.",
            detail: String(repeating: "b", count: 79) + "…",
            symbol: "exclamationmark.triangle",
            tone: .danger
        ))
    }

    @Test func networkProblemShowsTitleAndDetail() {
        let message = "Could not reach SimpleLogin. Check your network connection."

        let network = MenuEntry.entries(for: state(phase: .loading, lastError: message, lastErrorIsNetwork: true))
        let other = MenuEntry.entries(for: state(phase: .loading, lastError: message))

        #expect(network.first == .notice(title: "Could not reach SimpleLogin.", detail: "Check your network connection.", symbol: "wifi.slash", tone: .danger))
        #expect(other.first == .notice(title: "Could not reach SimpleLogin.", detail: "Check your network connection.", symbol: "exclamationmark.triangle", tone: .danger))
    }

    @Test func signedInListsTimersThenPinnedUnderHeaders() {
        let sections = MenuSections(
            timedUnpinned: [MenuAliasItem(id: 9, email: "temp@example.com", state: .timed(remaining: 192, endsAt: endsAt, length: 300))],
            pinned: [MenuAliasItem(id: 7, email: "shop@example.com", state: .disabled)]
        )

        let entries = MenuEntry.entries(for: state(sections: sections))

        #expect(entries.map(\.title) == [
            "Timers",
            "temp@example.com",
            "Pinned",
            "shop@example.com",
            nil,
            "New Random Alias",
            "New Random Alias That Expires",
            "New Alias…",
            "All Aliases…",
            nil,
            "Settings…",
            nil,
            "Quit",
        ])
        #expect(entries[0] == .header("Timers"))
        #expect(entries[2] == .header("Pinned"))
        #expect(entries[5] == .action("New Random Alias", .createRandomAlias(expiringAfter: nil), symbol: "dice"))
        #expect(entries[6] == .submenu("New Random Alias That Expires", [
            .header("Expires After"),
            .action("5 Minutes", .createRandomAlias(expiringAfter: .fiveMinutes), symbol: "timer"),
            .action("1 Hour", .createRandomAlias(expiringAfter: .oneHour)),
            .action("24 Hours", .createRandomAlias(expiringAfter: .twentyFourHours)),
        ], symbol: "timer"))
        #expect(entries[7] == .action("New Alias…", .openNewAlias, symbol: "square.and.pencil"))
        #expect(entries[8] == .action("All Aliases…", .openAllAliases, symbol: "list.bullet"))
        #expect(entries[10] == .action("Settings…", .openSettings, symbol: "gearshape", shortcut: ","))
        #expect(entries[12] == .action("Quit", .quit, symbol: "power", shortcut: "q"))
    }

    @Test func withoutTimersTheMenuStartsWithPinned() {
        let sections = MenuSections(timedUnpinned: [], pinned: [MenuAliasItem(id: 7, email: "shop@example.com", state: .enabled)])

        let entries = MenuEntry.entries(for: state(sections: sections))

        #expect(entries.prefix(3).map(\.title) == ["Pinned", "shop@example.com", nil])
    }

    @Test func noPinnedAliasesExplainsPinning() {
        let entries = MenuEntry.entries(for: state())

        #expect(entries.prefix(3) == [
            .header("Pinned"),
            .notice(title: "No pinned aliases yet", detail: "Open All Aliases, right-click an alias and choose Pin to keep it here.", symbol: "pin"),
            .separator,
        ])
    }

    @Test func beforeThePinnedListLoadsOnlyItsHeaderShows() {
        let entries = MenuEntry.entries(for: state(pinnedLoaded: false))

        #expect(entries.prefix(2) == [.header("Pinned"), .separator])
    }

    @Test func aliasRowsCarryStatusAndSpokenLabel() throws {
        let sections = MenuSections(
            timedUnpinned: [],
            pinned: [MenuAliasItem(id: 7, email: "shop@example.com", state: .timed(remaining: 192, endsAt: endsAt, length: 300))]
        )

        let entries = MenuEntry.entries(for: state(sections: sections))

        let row = try #require(row(of: entries[1]))
        #expect(row.id == 7)
        #expect(row.email == "shop@example.com")
        #expect(row.status == AliasStatus.make(state: sections.pinned[0].state, activity: nil, locale: german, timeZone: berlin))
        #expect(row.accessibilityLabel == AliasStatus.accessibilityLabel(
            email: "shop@example.com", pinned: true, state: sections.pinned[0].state, activity: nil, locale: german, timeZone: berlin
        ))
        #expect(row.accessibilityLabel.contains("pinned"))
    }

    @Test func aDisabledAliasOffersToEnableIt() {
        let children = children(of: entry(for: MenuAliasItem(id: 7, email: "shop@example.com", state: .disabled)))

        #expect(children == [
            copyAddress,
            .separator,
            .action("Enable for 5 Minutes", .enable(aliasID: 7, duration: .fiveMinutes), symbol: "timer"),
            .action("Enable for 1 Hour", .enable(aliasID: 7, duration: .oneHour)),
            .action("Enable for 24 Hours", .enable(aliasID: 7, duration: .twentyFourHours)),
        ])
    }

    @Test func aTimedAliasOffersToDisableKeepOrExtendIt() {
        let children = children(of: entry(for: timedItem))

        #expect(children == [
            copyAddress,
            .separator,
            .action("Disable Now", .disableNow(aliasID: 7), symbol: "poweroff"),
            .action("Keep Enabled", .keepEnabled(aliasID: 7, email: "shop@example.com"), symbol: "infinity"),
            .submenu("Extend", [
                .header("Extend By"),
                .action("5 Minutes", .extend(aliasID: 7, duration: .fiveMinutes), symbol: "timer"),
                .action("1 Hour", .extend(aliasID: 7, duration: .oneHour)),
                .action("24 Hours", .extend(aliasID: 7, duration: .twentyFourHours)),
            ], symbol: "goforward.plus"),
        ])
    }

    @Test func anEnabledAliasOffersToDisableItNowOrLater() {
        let children = children(of: entry(for: MenuAliasItem(id: 7, email: "shop@example.com", state: .enabled)))

        #expect(children == [
            copyAddress,
            .separator,
            .action("Disable Now", .disableNow(aliasID: 7), symbol: "poweroff"),
            .action("Disable After 5 Minutes", .disableAfter(aliasID: 7, duration: .fiveMinutes), symbol: "timer"),
            .action("Disable After 1 Hour", .disableAfter(aliasID: 7, duration: .oneHour)),
            .action("Disable After 24 Hours", .disableAfter(aliasID: 7, duration: .twentyFourHours)),
        ])
    }

    @Test func busyAliasDisablesChangesButNotCopy() throws {
        let entry = entry(for: timedItem, activity: .enabling)

        #expect(try #require(row(of: entry)).status.line == "Enabling…")
        #expect(children(of: entry) == [
            copyAddress,
            .separator,
            .action("Disable Now", .disableNow(aliasID: 7), symbol: "poweroff", isEnabled: false),
            .action("Keep Enabled", .keepEnabled(aliasID: 7, email: "shop@example.com"), symbol: "infinity", isEnabled: false),
            .submenu("Extend", [
                .header("Extend By"),
                .action("5 Minutes", .extend(aliasID: 7, duration: .fiveMinutes), symbol: "timer"),
                .action("1 Hour", .extend(aliasID: 7, duration: .oneHour)),
                .action("24 Hours", .extend(aliasID: 7, duration: .twentyFourHours)),
            ], symbol: "goforward.plus", isEnabled: false),
        ])
    }

    @Test func aNewCountdownKeepsTheLayout() {
        let before = entry(for: timedItem)
        let later = MenuAliasItem(id: 7, email: "shop@example.com", state: .timed(remaining: 59, endsAt: Date(timeIntervalSince1970: 60), length: 300))
        let after = entry(for: later)

        #expect(after != before)
        #expect(after.hasSameLayout(as: before))
    }

    @Test func aStateChangeChangesTheLayout() {
        let before = entry(for: timedItem)
        let after = entry(for: MenuAliasItem(id: 7, email: "shop@example.com", state: .disabled))

        #expect(!after.hasSameLayout(as: before))
    }

    @Test func anotherAliasChangesTheLayout() {
        let other = MenuAliasItem(id: 8, email: "shop@example.com", state: timedItem.state)

        #expect(!entry(for: other).hasSameLayout(as: entry(for: timedItem)))
    }

    @Test func headersAndNoticesKeepTheLayoutWhenTheirTextChanges() {
        #expect(MenuEntry.header("Timers").hasSameLayout(as: .header("Pinned")))
        #expect(MenuEntry.notice(title: "A", detail: nil, symbol: "key").hasSameLayout(as: .notice(title: "B", detail: "C", symbol: "pin")))
        #expect(!MenuEntry.header("Timers").hasSameLayout(as: .separator))
    }

    @Test func aChangedActionChangesTheLayout() {
        #expect(!MenuEntry.action("Quit", .quit).hasSameLayout(as: .action("Quit", .quit, shortcut: "q")))
    }
}
