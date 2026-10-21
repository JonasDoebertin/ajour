import Testing
import SimpleLoginKit
@testable import Ajour

struct MenuEntryTests {
    @Test func signedOutOffersSetUpAndQuit() {
        let entries = MenuEntry.entries(for: MenuState(phase: .signedOut))

        #expect(entries == [
            .action("Set Up…", .setUp),
            .separator,
            .action("Quit", .quit, shortcut: "q"),
        ])
    }

    @Test func loadingOffersOnlyQuit() {
        let entries = MenuEntry.entries(for: MenuState(phase: .loading))

        #expect(entries == [.action("Quit", .quit, shortcut: "q")])
    }

    @Test func problemsComeFirst() {
        let state = MenuState(
            phase: .loading,
            lastError: String(repeating: "a", count: 81),
            apiKeyInvalid: true,
            timerDataUnreadable: true
        )

        let entries = MenuEntry.entries(for: state)

        #expect(entries == [
            .notice(String(repeating: "a", count: 79) + "…"),
            .separator,
            .action("API key invalid – Re-enter Key…", .reEnterAPIKey),
            .separator,
            .notice("Timer data unreadable"),
            .separator,
            .action("Quit", .quit, shortcut: "q"),
        ])
    }

    @Test func signedInListsTimedThenPinnedAliasesThenActions() {
        let sections = MenuSections(
            timedUnpinned: [MenuAliasItem(id: 9, email: "temp@example.com", state: .timed(remaining: 192))],
            pinned: [MenuAliasItem(id: 7, email: "shop@example.com", state: .disabled)]
        )

        let entries = MenuEntry.entries(for: MenuState(phase: .signedIn(nil), sections: sections))

        #expect(entries.map(\.title) == [
            "● temp@example.com · 3:12 left",
            nil,
            "○ shop@example.com",
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
        #expect(entries[5] == .submenu("New Random Alias That Expires", [
            .action("After 5 Minutes", .createRandomAlias(expiringAfter: .fiveMinutes)),
            .action("After 1 Hour", .createRandomAlias(expiringAfter: .oneHour)),
            .action("After 24 Hours", .createRandomAlias(expiringAfter: .twentyFourHours)),
        ]))
        #expect(entries[9] == .action("Settings…", .openSettings, shortcut: ","))
    }

    @Test func aDisabledAliasOffersToEnableIt() {
        let entry = MenuEntry.alias(MenuAliasItem(id: 7, email: "shop@example.com", state: .disabled), isBusy: false)

        #expect(entry == .submenu("○ shop@example.com", [
            .action("Copy Address", .copy(email: "shop@example.com")),
            .separator,
            .action("Enable for 5 Minutes", .enable(aliasID: 7, duration: .fiveMinutes)),
            .action("Enable for 1 Hour", .enable(aliasID: 7, duration: .oneHour)),
            .action("Enable for 24 Hours", .enable(aliasID: 7, duration: .twentyFourHours)),
        ]))
    }

    @Test func aTimedAliasOffersToDisableKeepOrExtendIt() {
        let entry = MenuEntry.alias(MenuAliasItem(id: 7, email: "shop@example.com", state: .timed(remaining: 60)), isBusy: false)

        #expect(entry == .submenu("● shop@example.com · 1:00 left", [
            .action("Copy Address", .copy(email: "shop@example.com")),
            .separator,
            .action("Disable Now", .disableNow(aliasID: 7)),
            .action("Keep Enabled", .keepEnabled(aliasID: 7, email: "shop@example.com")),
            .submenu("Extend", [
                .action("5 Minutes", .extend(aliasID: 7, duration: .fiveMinutes)),
                .action("1 Hour", .extend(aliasID: 7, duration: .oneHour)),
                .action("24 Hours", .extend(aliasID: 7, duration: .twentyFourHours)),
            ]),
        ]))
    }

    @Test func anEnabledAliasOffersToDisableItNowOrLater() {
        let entry = MenuEntry.alias(MenuAliasItem(id: 7, email: "shop@example.com", state: .enabled), isBusy: false)

        #expect(entry == .submenu("● shop@example.com", [
            .action("Copy Address", .copy(email: "shop@example.com")),
            .separator,
            .action("Disable Now", .disableNow(aliasID: 7)),
            .action("Disable After 5 Minutes", .disableAfter(aliasID: 7, duration: .fiveMinutes)),
            .action("Disable After 1 Hour", .disableAfter(aliasID: 7, duration: .oneHour)),
            .action("Disable After 24 Hours", .disableAfter(aliasID: 7, duration: .twentyFourHours)),
        ]))
    }

    @Test func aBusyAliasCanStillBeCopiedButNotChanged() {
        let entry = MenuEntry.alias(MenuAliasItem(id: 7, email: "shop@example.com", state: .timed(remaining: 60)), isBusy: true)

        #expect(entry == .submenu("● shop@example.com · 1:00 left", [
            .action("Copy Address", .copy(email: "shop@example.com")),
            .separator,
            .action("Disable Now", .disableNow(aliasID: 7), isEnabled: false),
            .action("Keep Enabled", .keepEnabled(aliasID: 7, email: "shop@example.com"), isEnabled: false),
            .submenu("Extend", [
                .action("5 Minutes", .extend(aliasID: 7, duration: .fiveMinutes)),
                .action("1 Hour", .extend(aliasID: 7, duration: .oneHour)),
                .action("24 Hours", .extend(aliasID: 7, duration: .twentyFourHours)),
            ], isEnabled: false),
        ]))
    }

    @Test func aNewTitleKeepsTheLayout() {
        let before = MenuEntry.submenu("● shop@example.com · 1:00 left", [.action("Disable Now", .disableNow(aliasID: 7))])
        let after = MenuEntry.submenu("● shop@example.com · 0:59 left", [.action("Disable Now", .disableNow(aliasID: 7))])

        #expect(after.hasSameLayout(as: before))
    }

    @Test func otherSubmenuItemsChangeTheLayout() {
        let before = MenuEntry.submenu("● shop@example.com · 0:01 left", [.action("Disable Now", .disableNow(aliasID: 7))])
        let after = MenuEntry.submenu("○ shop@example.com", [.action("Enable for 5 Minutes", .enable(aliasID: 7, duration: .fiveMinutes))])

        #expect(!after.hasSameLayout(as: before))
    }

    @Test func aChangedActionChangesTheLayout() {
        #expect(!MenuEntry.action("Quit", .quit).hasSameLayout(as: .action("Quit", .quit, shortcut: "q")))
    }
}
