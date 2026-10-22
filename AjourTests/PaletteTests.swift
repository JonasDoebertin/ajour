import AppKit
import Testing
@testable import Ajour

struct PaletteTests {
    @Test func paletteColorsDifferBetweenLightAndDark() {
        for color in [Palette.stateOn, Palette.stateTimed, Palette.stateOff, Palette.danger, Palette.accentText] {
            #expect(hex(color, in: .aqua) != hex(color, in: .darkAqua))
        }
        #expect(hex(Palette.stateTimed, in: .aqua) == "A15C00")
        #expect(hex(Palette.stateTimed, in: .darkAqua) == "F4B544")
    }

    @Test func menuBarGlyphsAreTemplateImages() throws {
        for name in ["MenuBarGlyphIdle", "MenuBarGlyphTimers"] {
            let image = try #require(NSImage(named: name))
            #expect(image.isTemplate)
            #expect(image.size == CGSize(width: 23, height: 18))
        }
    }

    private func hex(_ color: NSColor, in appearanceName: NSAppearance.Name) -> String {
        var result = ""
        NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
            let rgb = color.usingColorSpace(.sRGB) ?? color
            let component = { (value: CGFloat) in Int((value * 255).rounded()) }
            result = String(
                format: "%02X%02X%02X",
                component(rgb.redComponent), component(rgb.greenComponent), component(rgb.blueComponent)
            )
        }
        return result
    }
}
