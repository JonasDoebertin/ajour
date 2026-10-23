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

    @Test func noticesUseAFullContrastViewThatCannotBeChosen() throws {
        let renderer = makeRenderer()

        renderer.show([.notice(title: "Not set up", detail: "Add a SimpleLogin API key to manage your aliases.", symbol: "key")])

        let item = try #require(menu.items.first)
        let view = try noticeView(of: item)
        #expect(view.title == "Not set up")
        #expect(view.detail == "Add a SimpleLogin API key to manage your aliases.")
        #expect(view.symbolImage != nil)
        #expect(item.isEnabled == false)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let lines = try strongestColorPerLine(drawnBy: view, in: appearance)
            #expect(lines.count == 3)
            #expect(lines.first?.matches(.labelColor, in: appearance) == true)
            #expect(lines.dropFirst().allSatisfy { $0.matches(.secondaryLabelColor, in: appearance) })
        }
    }

    @Test func dangerNoticesDrawTheirSymbolInTheDangerColor() throws {
        let renderer = makeRenderer()

        renderer.show([
            .notice(title: "Timer data unreadable", detail: nil, symbol: "exclamationmark.triangle", tone: .danger),
            .notice(title: "No pinned aliases yet", detail: nil, symbol: "pin"),
        ])

        let danger = try #require(try noticeView(of: menu.items[0]).symbolImage)
        #expect(!danger.isTemplate)
        let colors = try opaqueColors(of: danger)
        #expect(!colors.isEmpty && colors.allSatisfy { $0.isClose(to: Palette.danger) })
        let plain = try #require(try noticeView(of: menu.items[1]).symbolImage)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let plainColors = try visibleColors(of: plain, in: appearance)
            #expect(!plainColors.isEmpty && plainColors.allSatisfy { $0.isClose(to: .labelColor, in: appearance) })
        }
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

    @Test func aNoticeOffersItsFullTextAsTooltipAndSpokenLabel() throws {
        let renderer = makeRenderer()
        let message = "shop-blue-7421@simplelogin.com was enabled for the previous account and has been disabled."

        renderer.show([.notice(
            title: "shop-blue-7421@simplelogin.com was enabled for the previous…",
            detail: nil,
            symbol: "exclamationmark.triangle",
            tone: .danger,
            fullText: message
        )])

        let view = try noticeView(of: try #require(menu.items.first))
        #expect(view.toolTip == message)
        #expect(view.accessibilityLabel() == message)
    }

    @Test func aNoticeWithoutFullTextSpeaksTitleAndDetail() throws {
        let renderer = makeRenderer()

        renderer.show([.notice(
            title: "No pinned aliases yet",
            detail: "Open All Aliases, right-click an alias and choose Pin to keep it here.",
            symbol: "pin"
        )])

        let view = try noticeView(of: try #require(menu.items.first))
        let spoken = "No pinned aliases yet\nOpen All Aliases, right-click an alias and choose Pin to keep it here."
        #expect(view.accessibilityLabel() == spoken)
        #expect(view.toolTip == spoken)
        #expect(view.isAccessibilityElement() == true)
        #expect(view.accessibilityRole() == .staticText)
    }

    @Test func aNoticeUpdatedInPlaceDropsTheFullTextItNoLongerHas() throws {
        let renderer = makeRenderer()
        renderer.show([.notice(title: "Offline", detail: nil, symbol: "wifi.slash", fullText: "Offline for now.")])
        let item = try #require(menu.items.first)

        renderer.show([.notice(title: "Not set up", detail: nil, symbol: "key")])

        let view = try noticeView(of: item)
        #expect(menu.items.first === item)
        #expect(view.toolTip == "Not set up")
        #expect(view.accessibilityLabel() == "Not set up")
    }

    @Test func aChangedNoticeUpdatesTheSameItem() throws {
        let renderer = makeRenderer()
        renderer.show([.notice(title: "Offline", detail: nil, symbol: "wifi.slash"), .action("Quit", .quit)])
        let item = try #require(menu.items.first)
        let viewBefore = try noticeView(of: item)

        renderer.show([.notice(title: "Could not reach SimpleLogin.", detail: "Check your network connection.", symbol: "exclamationmark.triangle"), .action("Quit", .quit)])

        let view = try noticeView(of: item)
        #expect(menu.items.first === item)
        #expect(item.view === viewBefore)
        #expect(view.title == "Could not reach SimpleLogin.")
        #expect(view.detail == "Check your network connection.")
        #expect(view.symbolImage?.accessibilityDescription == NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)?.accessibilityDescription)
    }

    @Test func aLongDetailWrapsInsteadOfWideningTheMenu() throws {
        let longDetail = String(repeating: "Lorem ipsum dolor sit amet ", count: 8).prefix(200)
        let long = try shownNoticeView(detail: String(longDetail))
        let short = try shownNoticeView(detail: "Lorem")

        #expect(long.frame.width <= long.maximumWidth)
        #expect(long.frame.height > short.frame.height)
    }

    @Test func aLongWordWrapsInsideTheNotice() throws {
        let long = try shownNoticeView(detail: String(repeating: "x", count: 200))
        let short = try shownNoticeView(detail: "x")

        #expect(long.frame.width <= long.maximumWidth)
        #expect(long.frame.height > short.frame.height)
    }

    @Test func aNoticeShrinksWhenItsDetailGetsShorter() throws {
        let renderer = makeRenderer()
        renderer.show([.notice(title: "Offline", detail: String(repeating: "Lorem ipsum ", count: 16), symbol: "wifi.slash")])
        let view = try noticeView(of: try #require(menu.items.first))
        let longHeight = view.frame.height

        renderer.show([.notice(title: "Offline", detail: "Lorem ipsum", symbol: "wifi.slash")])

        #expect(try noticeView(of: try #require(menu.items.first)) === view)
        #expect(view.frame.height < longHeight)
    }

    @Test func aNoticeIsNeverHighlighted() throws {
        let renderer = makeRenderer()
        let danger = MenuEntry.notice(title: "Timer data unreadable", detail: nil, symbol: "exclamationmark.triangle", tone: .danger)
        let plain = MenuEntry.notice(title: "Offline", detail: "Check the connection.", symbol: "wifi.slash")
        renderer.show([danger, plain, aliasEntry(status: travelStatus(words: "47:06 left"), children: [])])
        let dangerItem = menu.items[0]
        let plainItem = menu.items[1]

        renderer.highlight(dangerItem, in: menu)
        renderer.show([danger, plain, aliasEntry(status: travelStatus(words: "47:05 left"), children: [])])
        let symbolColors = try opaqueColors(of: try #require(try noticeView(of: dangerItem).symbolImage))
        renderer.highlight(plainItem, in: menu)
        renderer.show([danger, plain, aliasEntry(status: travelStatus(words: "47:04 left"), children: [])])
        let lines = try strongestColorPerLine(drawnBy: try noticeView(of: plainItem), in: .aqua)

        #expect(menu.items[0] === dangerItem && menu.items[1] === plainItem)
        #expect(!symbolColors.isEmpty && symbolColors.allSatisfy { $0.isClose(to: Palette.danger) })
        #expect(lines.count == 2)
        #expect(lines.first?.matches(.labelColor, in: .aqua) == true)
        #expect(lines.last?.matches(.secondaryLabelColor, in: .aqua) == true)
    }

    @Test func aStretchedNoticeKeepsItsWidthWhenUpdatedInPlace() throws {
        let renderer = makeRenderer()
        let offline = MenuEntry.notice(title: "Offline", detail: nil, symbol: "wifi.slash")
        renderer.show([offline, aliasEntry(status: travelStatus(words: "47:06 left"), children: [])])
        let view = try noticeView(of: try #require(menu.items.first))
        view.setFrameSize(NSSize(width: 500, height: view.frame.height))

        renderer.show([offline, aliasEntry(status: travelStatus(words: "47:05 left"), children: [])])
        let widthWithSameContent = view.frame.width
        renderer.show([
            .notice(title: "Could not reach SimpleLogin.", detail: "Check your network connection.", symbol: "wifi.slash"),
            aliasEntry(status: travelStatus(words: "47:04 left"), children: []),
        ])

        #expect(try noticeView(of: try #require(menu.items.first)) === view)
        #expect(widthWithSameContent == 500)
        #expect(view.frame.width == 500)
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

        renderer.show([aliasEntry(status: .make(state: .enabled, change: .disabling), children: [])])

        let item = try #require(menu.items.first)
        #expect(item.attributedTitle?.string == "shop@example.com\nDisabling…")
        #expect(foregroundColor(ofLine: 1, in: item) == Palette.stateOff)
    }

    @Test func rendersAliasRowsAsSubmenusTitledWithTheAddress() throws {
        let renderer = makeRenderer()

        renderer.show([aliasEntry(status: .make(state: .disabled, change: nil), children: [.action("Copy Address", .copy(email: "shop@example.com"))])])

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
        renderer.show([aliasEntry(status: travelStatus(words: "47:06 left"), children: []), aliasEntry(id: 8, email: "other@example.com", status: .make(state: .enabled, change: nil), children: [])])
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

        renderer.show([aliasEntry(status: .make(state: .disabled, change: nil), children: [.action("Enable for 5 Minutes", .enable(aliasID: 7, duration: .fiveMinutes))])])

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

        renderer.show([aliasEntry(status: .make(state: .disabled, change: nil), children: [.action("Enable for 5 Minutes", .enable(aliasID: 7, duration: .fiveMinutes))])])

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

@MainActor private func noticeView(of item: NSMenuItem) throws -> MenuNoticeView {
    try #require(item.view as? MenuNoticeView)
}

@MainActor private func shownNoticeView(detail: String) throws -> MenuNoticeView {
    let menu = NSMenu()
    MenuRenderer(menu: menu) { _ in }.show([.notice(title: "Offline", detail: detail, symbol: "wifi.slash")])
    return try noticeView(of: try #require(menu.items.first))
}

private func status(remaining: TimeInterval) -> AliasStatus {
    .make(state: .timed(remaining: remaining, endsAt: Date(timeIntervalSince1970: 3600), length: 300), change: nil)
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

/// Draws `view` in `appearance` and returns, for each band of rows with something drawn in it, the most opaque color
/// drawn there. Glyph stems are covered fully, so that color is the text color, not an antialiased edge.
@MainActor private func strongestColorPerLine(drawnBy view: NSView, in appearance: NSAppearance.Name) throws -> [NSColor] {
    view.appearance = NSAppearance(named: appearance)
    defer { view.appearance = nil }
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let rows = (0..<bitmap.pixelsHigh).map { y in
        (0..<bitmap.pixelsWide).compactMap { x in bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) }
            .filter { $0.alphaComponent > 0.1 }
    }
    var lines: [[NSColor]] = []
    var previousRowWasEmpty = true
    for row in rows {
        if !row.isEmpty {
            if previousRowWasEmpty { lines.append([]) }
            lines[lines.count - 1] += row
        }
        previousRowWasEmpty = row.isEmpty
    }
    return lines.compactMap { $0.max { $0.alphaComponent < $1.alphaComponent } }
}

/// The colors of the fully opaque pixels of `image`, drawn in the light appearance.
@MainActor private func opaqueColors(of image: NSImage) throws -> [NSColor] {
    try colors(of: image, in: .aqua).filter { $0.alphaComponent == 1 }
}

/// The colors of the pixels of `image` that are more opaque than transparent, so translucent label colors count too.
@MainActor private func visibleColors(of image: NSImage, in appearance: NSAppearance.Name) throws -> [NSColor] {
    try colors(of: image, in: appearance).filter { $0.alphaComponent > 0.5 }
}

@MainActor private func colors(of image: NSImage, in appearance: NSAppearance.Name) throws -> [NSColor] {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
    }
    return (0..<32).flatMap { x in (0..<32).compactMap { y in bitmap.colorAt(x: x, y: y) } }
}

private extension NSColor {
    /// Compares opacity too, which tells the label color from the secondary label color in the same appearance.
    @MainActor func matches(_ other: NSColor, in appearance: NSAppearance.Name) -> Bool {
        var resolved: NSColor?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            resolved = other.usingColorSpace(.deviceRGB)
        }
        guard let resolved else { return false }
        return isClose(to: other, in: appearance) && abs(alphaComponent - resolved.alphaComponent) < 0.06
    }

    @MainActor func isClose(to other: NSColor, in appearance: NSAppearance.Name = .aqua) -> Bool {
        var resolved: NSColor?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            resolved = other.usingColorSpace(.deviceRGB)
        }
        guard let mine = usingColorSpace(.deviceRGB), let resolved else { return false }
        return abs(mine.redComponent - resolved.redComponent) < 0.03
            && abs(mine.greenComponent - resolved.greenComponent) < 0.03
            && abs(mine.blueComponent - resolved.blueComponent) < 0.03
    }
}
