import AppKit
import SwiftUI

/// The app's custom colors. Each adapts to appearance and Increase Contrast through the asset catalog.
enum Palette {
    static let stateOn = named("StateOn")
    static let stateTimed = named("StateTimed")
    static let stateOff = named("StateOff")
    static let danger = named("Danger")
    static let accentText = named("AccentText")

    static func color(_ nsColor: NSColor) -> Color {
        Color(nsColor: nsColor)
    }

    private static func named(_ name: String) -> NSColor {
        guard let color = NSColor(named: name) else {
            preconditionFailure("Missing color asset \(name)")
        }
        return color
    }
}
