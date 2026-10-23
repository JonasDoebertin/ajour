import AppKit

/// Shows menu entries in an `NSMenu`. While only titles and statuses change, it keeps the existing items, so a countdown
/// updates while the menu is open without closing the submenu the pointer is in.
@MainActor final class MenuRenderer: NSObject, NSMenuDelegate {
    private let menu: NSMenu
    private let perform: (MenuAction) -> Void
    private var shownEntries: [MenuEntry] = []
    private var highlightedItems: [ObjectIdentifier: NSMenuItem] = [:]

    init(menu: NSMenu, perform: @escaping (MenuAction) -> Void) {
        self.menu = menu
        self.perform = perform
        super.init()
        menu.autoenablesItems = false
    }

    func show(_ entries: [MenuEntry]) {
        guard entries != shownEntries else { return }
        if entries.count == shownEntries.count, zip(entries, shownEntries).allSatisfy({ $0.hasSameLayout(as: $1) }) {
            for (item, entry) in zip(menu.items, entries) {
                item.representedObject = MenuEntryBox(entry)
                showContent(of: entry, in: item)
            }
        } else {
            highlightedItems.removeAll()
            menu.items = entries.map(makeItem)
            if let pointed = menu.highlightedItem, menu.items.contains(where: { $0 === pointed }) {
                highlight(pointed, in: menu)
            }
        }
        shownEntries = entries
    }

    /// Menus keep at most one highlighted item each; the one losing the highlight gets its colors back.
    func highlight(_ item: NSMenuItem?, in menu: NSMenu) {
        let previous = highlightedItems[ObjectIdentifier(menu)]
        highlightedItems[ObjectIdentifier(menu)] = item
        if let previous, previous !== item {
            showContent(of: previous)
        }
        if let item {
            showContent(of: item)
        }
    }

    func resetHighlight() {
        let items = highlightedItems.values
        highlightedItems.removeAll()
        items.forEach { showContent(of: $0) }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        highlight(item, in: menu)
    }

    private func makeItem(for entry: MenuEntry) -> NSMenuItem {
        let item: NSMenuItem
        switch entry {
        case .header(let title):
            return .sectionHeader(title: title)
        case .notice:
            item = NSMenuItem()
            item.isEnabled = false
        case let .action(title, _, _, shortcut, isEnabled, _):
            item = NSMenuItem(title: title, action: #selector(performAction(of:)), keyEquivalent: shortcut)
            item.target = self
            item.isEnabled = isEnabled
        case let .submenu(title, entries, symbol, isEnabled):
            item = makeSubmenuItem(title: title, entries: entries)
            item.image = symbol.flatMap { Self.symbolImage($0) }
            item.isEnabled = isEnabled
        case let .alias(row, entries):
            item = makeSubmenuItem(title: row.email, entries: entries)
        case .separator:
            return .separator()
        }
        item.representedObject = MenuEntryBox(entry)
        showContent(of: entry, in: item)
        return item
    }

    private func makeSubmenuItem(title: String, entries: [MenuEntry]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        submenu.delegate = self
        submenu.items = entries.map(makeItem)
        item.submenu = submenu
        return item
    }

    private func showContent(of item: NSMenuItem) {
        guard let box = item.representedObject as? MenuEntryBox else { return }
        showContent(of: box.entry, in: item)
    }

    /// Shows what can change without a new layout: titles, notices, and alias statuses.
    private func showContent(of entry: MenuEntry, in item: NSMenuItem) {
        let isHighlighted = highlightedItems.values.contains { $0 === item }
        switch entry {
        case let .notice(title, detail, symbol, tone, fullText):
            item.attributedTitle = Self.noticeTitle(title, detail: detail)
            item.image = Self.symbolImage(symbol, tone: tone)
            item.toolTip = fullText
            item.setAccessibilityLabel(fullText)
        case let .alias(row, _):
            item.attributedTitle = Self.aliasTitle(row, isHighlighted: isHighlighted)
            item.image = StateSymbol.image(for: row.status.kind, highlighted: isHighlighted)
            item.setAccessibilityLabel(row.accessibilityLabel)
        case let .action(title, _, symbol, _, _, tone):
            item.title = title
            item.image = symbol.flatMap { Self.symbolImage($0, tone: tone, isHighlighted: isHighlighted) }
        case .header(let title), .submenu(let title, _, _, _):
            item.title = title
        case .separator:
            break
        }
    }

    /// Plain symbols stay templates, so AppKit tints them; danger symbols carry their own color.
    private static func symbolImage(_ name: String, tone: MenuTone = .plain, isHighlighted: Bool = false) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        guard tone == .danger else { return image }
        let color = isHighlighted ? NSColor.white : Palette.danger
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    }

    private static func noticeTitle(_ title: String, detail: String?) -> NSAttributedString {
        twoLineTitle(
            title, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor,
            detail: detail, detailFont: .systemFont(ofSize: 11), detailColor: .secondaryLabelColor
        )
    }

    private static func aliasTitle(_ row: MenuAliasRow, isHighlighted: Bool) -> NSAttributedString {
        twoLineTitle(
            row.email, font: .systemFont(ofSize: 13), color: isHighlighted ? .white : .labelColor,
            detail: row.status.line,
            detailFont: .monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            detailColor: isHighlighted ? .white : StateSymbol.tint(for: row.status.kind)
        )
    }

    private static func twoLineTitle(
        _ title: String, font: NSFont, color: NSColor,
        detail: String?, detailFont: NSFont, detailColor: NSColor
    ) -> NSAttributedString {
        let text = NSMutableAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        if let detail {
            text.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: color]))
            text.append(NSAttributedString(string: detail, attributes: [.font: detailFont, .foregroundColor: detailColor]))
        }
        return text
    }

    @objc private func performAction(of item: NSMenuItem) {
        guard case .action(_, let action, _, _, _, _) = (item.representedObject as? MenuEntryBox)?.entry else { return }
        perform(action)
    }
}

private final class MenuEntryBox: NSObject {
    let entry: MenuEntry

    init(_ entry: MenuEntry) {
        self.entry = entry
    }
}
