import AppKit
import SwiftUI

/// Opens the app's windows from AppKit, which the status item menu needs because SwiftUI's `openWindow`
/// only exists inside SwiftUI scenes. Each opening gets fresh content, so views start over like a new scene.
@MainActor final class WindowCoordinator: NSObject, NSWindowDelegate {
    enum Kind {
        case onboarding, newAlias, allAliases, settings
    }

    private let makeContent: (Kind, WindowCoordinator) -> NSViewController
    private var windows: [Kind: NSWindow] = [:]

    init(makeContent: @escaping (Kind, WindowCoordinator) -> NSViewController) {
        self.makeContent = makeContent
    }

    /// A menu bar app isn't active by itself, so without activating, the window opens behind other apps.
    func show(_ kind: Kind) {
        let window = windows[kind] ?? makeWindow(kind)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let kind = windows.first(where: { $0.value === window })?.key else { return }
        windows[kind] = nil
        window.contentViewController = nil
    }

    private func makeWindow(_ kind: Kind) -> NSWindow {
        let window = NSWindow(contentViewController: makeContent(kind, self))
        window.title = kind.title
        window.styleMask = kind.styleMask
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        if let size = kind.defaultSize { window.setContentSize(size) }
        window.center()
        window.delegate = self
        windows[kind] = window
        return window
    }
}

extension WindowCoordinator.Kind {
    var title: String {
        switch self {
        case .onboarding: "Set Up"
        case .newAlias: "New Alias"
        case .allAliases: "All Aliases"
        case .settings: "Settings"
        }
    }

    var styleMask: NSWindow.StyleMask {
        switch self {
        case .allAliases: [.titled, .closable, .miniaturizable, .resizable]
        case .onboarding, .newAlias, .settings: [.titled, .closable]
        }
    }

    var defaultSize: CGSize? {
        switch self {
        case .allAliases: CGSize(width: 520, height: 600)
        case .onboarding, .newAlias, .settings: nil
        }
    }
}

@MainActor enum WindowContent {
    /// Bridges toolbar items into the window. A window that isn't resizable follows the size of its content
    /// instead: its views take the height they need, so wrapped text is never cut off. Sizing such a window by
    /// its preferred content size made AppKit stop the app in an endless layout loop.
    static func hosting(_ rootView: some View, fitsContent: Bool) -> NSViewController {
        guard fitsContent else { return bridgingToolbars(NSHostingController(rootView: rootView)) }
        let controller = NSHostingController(rootView: rootView.fixedSize(horizontal: false, vertical: true))
        controller.sizingOptions = .intrinsicContentSize
        return bridgingToolbars(controller)
    }

    private static func bridgingToolbars<Content: View>(_ controller: NSHostingController<Content>) -> NSViewController {
        controller.sceneBridgingOptions = .all
        return controller
    }
}
