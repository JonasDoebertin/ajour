import AppKit
import Foundation
import SimpleLoginKit
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

        renderer.show([.notice(title: "Offline", detail: nil, symbol: "wifi.slash"), .separator, .action("Quit", .quit, shortcut: "q")])

        #expect(menu.items.map(\.title) == ["Offline", "", "Quit"])
        #expect(menu.items[0].isEnabled == false)
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items[2].isEnabled)
        #expect(menu.items[2].keyEquivalent == "q")
        #expect(menu.autoenablesItems == false)
    }

    @Test func headersBecomeSectionHeaders() {
        let renderer = makeRenderer()

        renderer.show([.header("Pinned")])

        #expect(menu.items.first?.isSectionHeader == true)
        #expect(menu.items.first?.title == "Pinned")
    }

    @Test func actionsCarryTheirSymbol() throws {
        let renderer = makeRenderer()

        renderer.show([.action("Quit", .quit, symbol: "power"), .submenu("Extend", [], symbol: "goforward.plus")])

        #expect(try #require(menu.items[0].image).isTemplate)
        #expect(try #require(menu.items[1].image).isTemplate)
    }

    @Test func noticesShowTitleDetailAndSymbol() throws {
        let renderer = makeRenderer()

        renderer.show([.notice(title: "Not set up", detail: "Add a SimpleLogin API key to manage your aliases.", symbol: "key")])

        let item = try #require(menu.items.first)
        #expect(item.attributedTitle?.string == "Not set up\nAdd a SimpleLogin API key to manage your aliases.")
        #expect(foregroundColor(ofLine: 0, in: item) == .labelColor)
        #expect(foregroundColor(ofLine: 1, in: item) == .secondaryLabelColor)
        #expect(item.image != nil)
        #expect(item.isEnabled == false)
    }

    @Test func dangerNoticesDrawTheirSymbolInTheDangerColor() throws {
        let renderer = makeRenderer()

        renderer.show([
            .notice(title: "Timer data unreadable", detail: nil, symbol: "exclamationmark.triangle", tone: .danger),
            .notice(title: "No pinned aliases yet", detail: nil, symbol: "pin"),
        ])

        let danger = try #require(menu.items[0].image)
        #expect(!danger.isTemplate)
        let colors = try opaqueColors(of: danger)
        #expect(!colors.isEmpty && colors.allSatisfy { $0.isClose(to: Palette.danger) })
        #expect(try #require(menu.items[1].image).isTemplate)
    }

    @Test func aHighlightedDangerActionDrawsItsSymbolWhite() throws {
        let renderer = makeRenderer()
        renderer.show([.action("API key invalid – Re-enter Key…", .reEnterAPIKey, symbol: "key", tone: .danger)])
        let item = try #require(menu.items.first)

        renderer.highlight(item, in: menu)
        let highlighted = try opaqueColors(of: try #require(item.image))
        renderer.resetHighlight()
        let normal = try opaqueColors(of: try #require(item.image))

        #expect(!highlighted.isEmpty && highlighted.allSatisfy { $0.isClose(to: .white) })
        #expect(!normal.isEmpty && normal.allSatisfy { $0.isClose(to: Palette.danger) })
    }

    @Test func aChangedNoticeUpdatesTheSameItem() throws {
        let renderer = makeRenderer()
        renderer.show([.notice(title: "Offline", detail: nil, symbol: "wifi.slash"), .action("Quit", .quit)])
        let item = try #require(menu.items.first)

        renderer.show([.notice(title: "Could not reach SimpleLogin.", detail: "Check your network connection.", symbol: "exclamationmark.triangle"), .action("Quit", .quit)])

        #expect(menu.items.first === item)
        #expect(item.attributedTitle?.string == "Could not reach SimpleLogin.\nCheck your network connection.")
        #expect(item.image?.accessibilityDescription == NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)?.accessibilityDescription)
    }

    @Test func aliasRowShowsAddressAndStatusLines() throws {
        let renderer = makeRenderer()

        renderer.show([aliasEntry(email: "travel@alexmorgan.example", status: travelStatus(words: "47:06 left"), children: [])])

        let item = try #require(menu.items.first)
        #expect(item.attributedTitle?.string == "travel@alexmorgan.example\n47:06 left · off at 14:54")
        #expect(foregroundColor(ofLine: 0, in: item) == .labelColor)
        #expect(foregroundColor(ofLine: 1, in: item) == Palette.stateTimed)
        #expect(item.image?.isTemplate == false)
        #expect(item.accessibilityLabel() == "travel@alexmorgan.example")
    }

    @Test func busyAliasRowsUseTheOffColor() throws {
        let renderer = makeRenderer()

        renderer.show([aliasEntry(status: .make(state: .enabled, activity: .disabling), children: [])])

        let item = try #require(menu.items.first)
        #expect(item.attributedTitle?.string == "shop@example.com\nDisabling…")
        #expect(foregroundColor(ofLine: 1, in: item) == Palette.stateOff)
    }

    @Test func rendersAliasRowsAsSubmenusTitledWithTheAddress() throws {
        let renderer = makeRenderer()

        renderer.show([aliasEntry(status: .make(state: .disabled, activity: nil), children: [.action("Copy Address", .copy(email: "shop@example.com"))])])

        #expect(menu.items.first?.title.components(separatedBy: "\n").first == "shop@example.com")
        #expect(menu.items.first?.submenu?.items.map(\.title) == ["Copy Address"])
        #expect(menu.items.first?.submenu?.delegate === renderer)
    }

    @Test func highlightingTurnsTheRowWhite() throws {
        let renderer = makeRenderer()
        renderer.show([aliasEntry(status: travelStatus(words: "47:06 left"), children: [])])
        let item = try #require(menu.items.first)

        renderer.highlight(item, in: menu)

        #expect(isWhite(item))
    }

    @Test func movingTheHighlightRestoresThePreviousRow() throws {
        let renderer = makeRenderer()
        renderer.show([aliasEntry(status: travelStatus(words: "47:06 left"), children: []), aliasEntry(id: 8, email: "other@example.com", status: .make(state: .enabled, activity: nil), children: [])])
        let first = menu.items[0]
        let second = menu.items[1]

        renderer.highlight(first, in: menu)
        renderer.highlight(second, in: menu)

        #expect(foregroundColor(ofLine: 0, in: first) == .labelColor)
        #expect(foregroundColor(ofLine: 1, in: first) == Palette.stateTimed)
        #expect(isWhite(second))
    }

    @Test func closingTheMenuRestoresTheHighlightedRow() throws {
        let renderer = makeRenderer()
        renderer.show([aliasEntry(status: travelStatus(words: "47:06 left"), children: [])])
        let item = try #require(menu.items.first)
        renderer.highlight(item, in: menu)

        renderer.resetHighlight()

        #expect(foregroundColor(ofLine: 0, in: item) == .labelColor)
        #expect(foregroundColor(ofLine: 1, in: item) == Palette.stateTimed)
    }

    @Test func aCountdownUpdatesTheHighlightedRowInPlace() throws {
        let renderer = makeRenderer()
        renderer.show([aliasEntry(status: travelStatus(words: "47:06 left"), children: [])])
        let item = try #require(menu.items.first)
        renderer.highlight(item, in: menu)

        renderer.show([aliasEntry(status: travelStatus(words: "47:05 left"), children: [])])

        #expect(menu.items.first === item)
        #expect(item.attributedTitle?.string == "shop@example.com\n47:05 left · off at 14:54")
        #expect(isWhite(item))
    }

    @Test func aTimerEndingRebuildsTheRow() throws {
        let renderer = makeRenderer()
        renderer.show([aliasEntry(status: status(remaining: 1), children: [.action("Disable Now", .disableNow(aliasID: 7))])])
        let item = try #require(menu.items.first)

        renderer.show([aliasEntry(status: .make(state: .disabled, activity: nil), children: [.action("Enable for 5 Minutes", .enable(aliasID: 7, duration: .fiveMinutes))])])

        #expect(menu.items.first !== item)
        #expect(menu.items.first?.attributedTitle?.string == "shop@example.com\nDisabled")
    }

    @Test func aRowRebuiltUnderThePointerStaysHighlighted() throws {
        let menu = PointedMenu()
        let renderer = MenuRenderer(menu: menu) { _ in }
        renderer.show([aliasEntry(status: status(remaining: 1), children: [.action("Disable Now", .disableNow(aliasID: 7))])])
        let item = try #require(menu.items.first)
        renderer.highlight(item, in: menu)
        menu.pointsAtFirstItem = true

        renderer.show([aliasEntry(status: .make(state: .disabled, activity: nil), children: [.action("Enable for 5 Minutes", .enable(aliasID: 7, duration: .fiveMinutes))])])

        let rebuilt = try #require(menu.items.first)
        #expect(rebuilt !== item)
        #expect(isWhite(rebuilt))
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
        renderer.show([.submenu("Alias", [.action("Copy Address", .copy(email: "shop@example.com"))])])
        let submenu = try #require(menu.items.first?.submenu)

        submenu.performActionForItem(at: 0)

        #expect(performed.actions == [.copy(email: "shop@example.com")])
    }

    @Test func aNewCountdownKeepsTheSameItems() throws {
        let renderer = makeRenderer()
        let children: [MenuEntry] = [.action("Disable Now", .disableNow(aliasID: 7))]
        renderer.show([aliasEntry(status: status(remaining: 60), children: children), .separator])
        let item = try #require(menu.items.first)
        let submenu = try #require(item.submenu)

        renderer.show([aliasEntry(status: status(remaining: 59), children: children), .separator])

        #expect(menu.items.first === item)
        #expect(item.submenu === submenu)
    }

    @Test func aNewTitleUpdatesTheSameItem() throws {
        let renderer = makeRenderer()
        renderer.show([.submenu("Extend (1)", [.action("1 Hour", .extend(aliasID: 7, duration: .oneHour))])])
        let item = try #require(menu.items.first)

        renderer.show([.submenu("Extend (2)", [.action("1 Hour", .extend(aliasID: 7, duration: .oneHour))])])

        #expect(menu.items.first === item)
        #expect(item.title == "Extend (2)")
    }

    @Test func anAddedEntryReplacesTheItems() {
        let renderer = makeRenderer()
        renderer.show([.action("Quit", .quit)])

        renderer.show([.notice(title: "Offline", detail: nil, symbol: "wifi.slash"), .action("Quit", .quit)])

        #expect(menu.items.map(\.title) == ["Offline", "Quit"])
    }
}

private func status(remaining: TimeInterval) -> AliasStatus {
    .make(state: .timed(remaining: remaining, endsAt: Date(timeIntervalSince1970: 3600), length: 300), activity: nil)
}

private func travelStatus(words: String) -> AliasStatus {
    AliasStatus(kind: .timed(shareLeft: 0.8), words: words, turnsOff: "off at 14:54")
}

private func aliasEntry(id: Int = 7, email: String = "shop@example.com", status: AliasStatus, children: [MenuEntry]) -> MenuEntry {
    .alias(MenuAliasRow(id: id, email: email, status: status, accessibilityLabel: email), children)
}

@MainActor private func foregroundColor(ofLine line: Int, in item: NSMenuItem) -> NSColor? {
    guard let title = item.attributedTitle else { return nil }
    let lines = title.string.components(separatedBy: "\n")
    let location = lines.prefix(line).reduce(0) { $0 + ($1 as NSString).length + 1 }
    return title.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
}

@MainActor private func isWhite(_ item: NSMenuItem) -> Bool {
    guard let title = item.attributedTitle else { return false }
    var allWhite = true
    title.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: title.length)) { color, _, _ in
        if color as? NSColor != .white { allWhite = false }
    }
    return allWhite
}

/// Stands in for AppKit's menu tracking, which sets the highlighted item while the pointer is over it.
private final class PointedMenu: NSMenu {
    var pointsAtFirstItem = false

    override var highlightedItem: NSMenuItem? {
        pointsAtFirstItem ? items.first : nil
    }
}

@MainActor final class PerformedActions {
    var actions: [MenuAction] = []
}

/// The colors of the fully opaque pixels of `image`, drawn in the light appearance.
@MainActor private func opaqueColors(of image: NSImage) throws -> [NSColor] {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
    }
    return (0..<32).flatMap { x in (0..<32).compactMap { y in bitmap.colorAt(x: x, y: y) } }
        .filter { $0.alphaComponent == 1 }
}

private extension NSColor {
    @MainActor func isClose(to other: NSColor) -> Bool {
        var resolved: NSColor?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            resolved = other.usingColorSpace(.deviceRGB)
        }
        guard let mine = usingColorSpace(.deviceRGB), let resolved else { return false }
        return abs(mine.redComponent - resolved.redComponent) < 0.03
            && abs(mine.greenComponent - resolved.greenComponent) < 0.03
            && abs(mine.blueComponent - resolved.blueComponent) < 0.03
    }
}
