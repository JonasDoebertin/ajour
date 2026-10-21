import AppKit
import Testing
@testable import Ajour

@MainActor
struct MenuRendererTests {
    let menu = NSMenu()
    let performed = PerformedActions()

    func makeRenderer() -> MenuRenderer {
        let performed = performed
        return MenuRenderer(menu: menu) { performed.actions.append($0) }
    }

    @Test func rendersTitlesSeparatorsAndShortcuts() {
        let renderer = makeRenderer()

        renderer.show([.notice("Offline"), .separator, .action("Quit", .quit, shortcut: "q")])

        #expect(menu.items.map(\.title) == ["Offline", "", "Quit"])
        #expect(menu.items[0].isEnabled == false)
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items[2].isEnabled)
        #expect(menu.items[2].keyEquivalent == "q")
        #expect(menu.autoenablesItems == false)
    }

    @Test func rendersSubmenusWithTheirOwnEnabledState() throws {
        let renderer = makeRenderer()

        renderer.show([.submenu("Extend", [.action("1 Hour", .extend(aliasID: 7, duration: .oneHour))], isEnabled: false)])

        let submenu = try #require(menu.items.first?.submenu)
        #expect(menu.items.first?.isEnabled == false)
        #expect(submenu.items.map(\.title) == ["1 Hour"])
        #expect(submenu.autoenablesItems == false)
    }

    @Test func choosingAnItemPerformsItsAction() throws {
        let renderer = makeRenderer()
        renderer.show([.submenu("○ shop@example.com", [.action("Copy Address", .copy(email: "shop@example.com"))])])
        let submenu = try #require(menu.items.first?.submenu)

        submenu.performActionForItem(at: 0)

        #expect(performed.actions == [.copy(email: "shop@example.com")])
    }

    @Test func aNewCountdownUpdatesTheTitleOfTheSameItems() throws {
        let renderer = makeRenderer()
        let children: [MenuEntry] = [.action("Disable Now", .disableNow(aliasID: 7))]
        renderer.show([.submenu("● shop@example.com · 1:00 left", children), .separator])
        let item = try #require(menu.items.first)
        let submenu = try #require(item.submenu)

        renderer.show([.submenu("● shop@example.com · 0:59 left", children), .separator])

        #expect(menu.items.first === item)
        #expect(item.submenu === submenu)
        #expect(item.title == "● shop@example.com · 0:59 left")
    }

    @Test func aChangedLayoutReplacesTheItems() throws {
        let renderer = makeRenderer()
        renderer.show([.submenu("● shop@example.com · 0:01 left", [.action("Disable Now", .disableNow(aliasID: 7))])])
        let item = try #require(menu.items.first)

        renderer.show([.submenu("○ shop@example.com", [.action("Enable for 5 Minutes", .enable(aliasID: 7, duration: .fiveMinutes))])])

        #expect(menu.items.first !== item)
        #expect(menu.items.first?.submenu?.items.map(\.title) == ["Enable for 5 Minutes"])
    }

    @Test func anAddedEntryReplacesTheItems() {
        let renderer = makeRenderer()
        renderer.show([.action("Quit", .quit)])

        renderer.show([.notice("Offline"), .action("Quit", .quit)])

        #expect(menu.items.map(\.title) == ["Offline", "Quit"])
    }
}

@MainActor final class PerformedActions {
    var actions: [MenuAction] = []
}
