import AppKit

/// Shows menu entries in an `NSMenu`. While only titles change, it keeps the existing items, so a countdown
/// updates while the menu is open without closing the submenu the pointer is in.
@MainActor final class MenuRenderer: NSObject {
    private let menu: NSMenu
    private let perform: (MenuAction) -> Void
    private var shownEntries: [MenuEntry] = []

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
                item.title = entry.title ?? ""
            }
        } else {
            menu.items = entries.map(makeItem)
        }
        shownEntries = entries
    }

    private func makeItem(for entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .header(let title):
            return .sectionHeader(title: title)
        case .notice(let title, _, _):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case let .action(title, action, _, shortcut, isEnabled):
            let item = NSMenuItem(title: title, action: #selector(performAction(of:)), keyEquivalent: shortcut)
            item.target = self
            item.representedObject = MenuActionBox(action)
            item.isEnabled = isEnabled
            return item
        case let .submenu(title, entries, _, isEnabled):
            let item = makeSubmenuItem(title: title, entries: entries)
            item.isEnabled = isEnabled
            return item
        case let .alias(row, entries):
            return makeSubmenuItem(title: row.email, entries: entries)
        case .separator:
            return .separator()
        }
    }

    private func makeSubmenuItem(title: String, entries: [MenuEntry]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        submenu.items = entries.map(makeItem)
        item.submenu = submenu
        return item
    }

    @objc private func performAction(of item: NSMenuItem) {
        guard let box = item.representedObject as? MenuActionBox else { return }
        perform(box.action)
    }
}

private final class MenuActionBox: NSObject {
    let action: MenuAction

    init(_ action: MenuAction) {
        self.action = action
    }
}
