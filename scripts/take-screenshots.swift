// Takes the README screenshots from a Debug build running in demo mode.
//
//     swift scripts/take-screenshots.swift <path to Debug Ajour.app> <output directory> [dark]
//
// The optional `dark` argument launches the demo with `-AppleInterfaceStyle Dark`. That only affects the windows: the
// status menu follows the system appearance, so switch the system itself to take the menu in the other appearance.
//
// Needs Screen Recording and Accessibility permission for the terminal app. While it runs, it covers the screen
// with a backdrop and moves the mouse, so don't touch the Mac until it finishes.

import AppKit
import ApplicationServices

let arguments = CommandLine.arguments
guard arguments.count == 3 || (arguments.count == 4 && arguments[3] == "dark") else {
    print("usage: swift scripts/take-screenshots.swift <path to Debug Ajour.app> <output directory> [dark]")
    exit(2)
}
let usesDarkWindows = arguments.count == 4
let appURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

setvbuf(stdout, nil, _IONBF, 0)
NSApplication.shared.setActivationPolicy(.accessory)

func wait(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func fail(_ message: String) -> Never {
    print("error: \(message)")
    exit(1)
}

// MARK: Demo app

func launchDemo(signedOut: Bool = false) -> Process {
    let process = Process()
    process.executableURL = appURL.appendingPathComponent("Contents/MacOS/Ajour")
    process.arguments = ["-AjourDemo", "YES", "-AjourDemoSignedOut", signedOut ? "YES" : "NO"]
    if usesDarkWindows { process.arguments? += ["-AppleInterfaceStyle", "Dark"] }
    do { try process.run() } catch { fail("could not launch \(appURL.path): \(error)") }
    return process
}

func quit(_ process: Process) {
    NSRunningApplication(processIdentifier: process.processIdentifier)?.terminate()
    process.waitUntilExit()
}

// MARK: Accessibility

func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) ?? []
}

func frame(of element: AXUIElement) -> CGRect {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let value: AXValue = attribute(element, kAXPositionAttribute) { AXValueGetValue(value, .cgPoint, &position) }
    if let value: AXValue = attribute(element, kAXSizeAttribute) { AXValueGetValue(value, .cgSize, &size) }
    return CGRect(origin: position, size: size)
}

func statusItem(of process: Process) -> AXUIElement {
    let app = AXUIElementCreateApplication(process.processIdentifier)
    for _ in 0..<50 {
        if let menuBar: AXUIElement = attribute(app, "AXExtrasMenuBar"), let item = children(of: menuBar).first {
            return item
        }
        wait(0.2)
    }
    fail("the demo app's menu bar item did not appear")
}

func menuItem(in element: AXUIElement, titled matches: (String) -> Bool) -> AXUIElement? {
    for child in children(of: element) {
        if let title: String = attribute(child, kAXTitleAttribute), matches(title) { return child }
        if let found = menuItem(in: child, titled: matches) { return found }
    }
    return nil
}

// MARK: Input

func move(to point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func click(_ point: CGPoint) {
    move(to: point)
    wait(0.1)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func press(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    for isDown in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}

/// Types through System Events, which delivers text more reliably than posted key events.
func type(_ text: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", "on run argv", "-e", "tell application \"System Events\" to keystroke (item 1 of argv)", "-e", "end run", text]
    try? process.run()
    process.waitUntilExit()
}

let escapeKey: CGKeyCode = 53

/// Pressing through accessibility opens the menu reliably; a posted click can miss the menu bar item.
func press(_ element: AXUIElement) {
    AXUIElementSetMessagingTimeout(element, 1)
    AXUIElementPerformAction(element, kAXPressAction as CFString)
}

func openMenu(of process: Process) -> AXUIElement {
    let item = statusItem(of: process)
    press(item)
    wait(0.8)
    return item
}

func element(in root: AXUIElement, role: String) -> AXUIElement? {
    if (attribute(root, kAXRoleAttribute) as String?) == role { return root }
    for child in children(of: root) {
        if let found = element(in: child, role: role) { return found }
    }
    return nil
}

func clickTextField(inWindowTitled title: String, of process: Process) {
    let app = AXUIElementCreateApplication(process.processIdentifier)
    let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
    guard let window = windows.first(where: { (attribute($0, kAXTitleAttribute) as String?) == title }),
          let field = element(in: window, role: kAXTextFieldRole) else { fail("no text field in \(title)") }
    click(CGPoint(x: frame(of: field).midX, y: frame(of: field).midY))
    wait(0.3)
}

func choose(_ title: String, in process: Process) {
    let item = openMenu(of: process)
    guard let entry = menuItem(in: item, titled: { $0 == title }) else { fail("menu item \(title) not found") }
    press(entry)
}

// MARK: Capturing

func windows(of process: Process) -> [[String: Any]] {
    let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return all.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == process.processIdentifier }
}

func bounds(of window: [String: Any]) -> CGRect {
    CGRect(dictionaryRepresentation: window[kCGWindowBounds as String] as! CFDictionary) ?? .zero
}

func screencapture(_ arguments: [String], to name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x"] + arguments + [outputURL.appendingPathComponent(name).path]
    try? process.run()
    process.waitUntilExit()
    print("saved \(name)")
}

func captureWindow(titled title: String, of process: Process, as name: String) {
    for _ in 0..<50 {
        if let window = windows(of: process).first(where: { ($0[kCGWindowName as String] as? String) == title }),
           let id = window[kCGWindowNumber as String] as? Int {
            wait(1.5)
            screencapture(["-l", String(id)], to: name)
            return
        }
        wait(0.2)
    }
    fail("window \(title) did not appear")
}

/// Covers the screen below the menus, so a capture around them shows a calm background instead of the desktop.
final class Backdrop {
    private let window: NSWindow

    init() {
        let screen = NSScreen.screens[0]
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        window.ignoresMouseEvents = true
        let gradient = CAGradientLayer()
        gradient.colors = [NSColor(srgbRed: 0.42, green: 0.36, blue: 0.91, alpha: 1).cgColor, NSColor(srgbRed: 0.16, green: 0.67, blue: 0.80, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        window.contentView?.wantsLayer = true
        window.contentView?.layer = gradient
        window.orderFrontRegardless()
        wait(0.5)
    }

    func remove() {
        window.orderOut(nil)
    }
}

func captureMenu(of process: Process, hovering title: (String) -> Bool, as name: String) {
    let backdrop = Backdrop()
    let item = openMenu(of: process)
    if let entry = menuItem(in: item, titled: title) {
        move(to: CGPoint(x: frame(of: entry).midX, y: frame(of: entry).midY))
        wait(1.2)
    }
    let menus = windows(of: process).filter { ($0[kCGWindowLayer as String] as? Int ?? 0) >= Int(CGWindowLevelForKey(.popUpMenuWindow)) }
    guard !menus.isEmpty else { fail("the menu did not open") }
    let area = menus.map(bounds).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -56, dy: -40)
    screencapture(["-R", "\(Int(area.minX)),\(Int(max(area.minY, 0))),\(Int(area.width)),\(Int(area.height))"], to: name)
    press(keyCode: escapeKey)
    press(keyCode: escapeKey)
    backdrop.remove()
    wait(0.5)
}

// MARK: Screenshots

let demo = launchDemo()
_ = statusItem(of: demo)
wait(3)

captureMenu(of: demo, hovering: { $0.hasPrefix("travel@") }, as: "menu.png")

choose("All Aliases…", in: demo)
captureWindow(titled: "All Aliases", of: demo, as: "all-aliases.png")
press(keyCode: 13, flags: .maskCommand)

print("opening New Alias")
choose("New Alias…", in: demo)
wait(1.5)
clickTextField(inWindowTitled: "New Alias", of: demo)
type("concert-tickets")
captureWindow(titled: "New Alias", of: demo, as: "new-alias.png")
press(keyCode: 13, flags: .maskCommand)

choose("Settings…", in: demo)
captureWindow(titled: "Settings", of: demo, as: "settings.png")
press(keyCode: 13, flags: .maskCommand)

quit(demo)

let onboarding = launchDemo(signedOut: true)
captureWindow(titled: "Set Up", of: onboarding, as: "onboarding.png")
quit(onboarding)
