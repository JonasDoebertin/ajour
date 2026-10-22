import AppKit
import SwiftUI

/// Draws for the view's own appearance, so the symbol follows Light, Dark, and Increase Contrast changes.
struct StateSymbolView: View {
    let kind: AliasStatus.Kind
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Image(nsImage: StateSymbol.image(for: kind, highlighted: false, appearance: NSAppearance(named: appearanceName)))
    }

    private var appearanceName: NSAppearance.Name {
        switch (colorScheme, contrast) {
        case (.dark, .increased): .accessibilityHighContrastDarkAqua
        case (.dark, _): .darkAqua
        case (_, .increased): .accessibilityHighContrastAqua
        default: .aqua
        }
    }
}
