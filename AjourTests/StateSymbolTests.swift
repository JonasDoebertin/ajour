import AppKit
import Testing
@testable import Ajour

struct StateSymbolTests {
    private let allKinds: [AliasStatus.Kind] = [.enabled, .disabled, .timed(shareLeft: 0.4), .busy]

    @Test func symbolsAreSixteenPoints() {
        for kind in allKinds {
            for highlighted in [false, true] {
                let image = StateSymbol.image(for: kind, highlighted: highlighted)
                #expect(image.size == CGSize(width: 16, height: 16))
                #expect(!image.isTemplate)
            }
        }
    }

    @Test func highlightedSymbolIsWhite() throws {
        let highlighted = try pixel(of: StateSymbol.image(for: .enabled, highlighted: true), x: 32, y: 32)
        let normal = try pixel(of: StateSymbol.image(for: .enabled, highlighted: false), x: 32, y: 32)
        #expect(highlighted == NSColor.white.usingColorSpace(.sRGB))
        #expect(normal != NSColor.white.usingColorSpace(.sRGB))
        #expect(normal.alphaComponent == 1)
    }

    @Test func pieStartsAtTwelveOClockAndRunsClockwise() throws {
        let quarter = StateSymbol.image(for: .timed(shareLeft: 0.25), highlighted: false)
        #expect(try pixel(of: quarter, x: 40, y: 24).alphaComponent == 1)
        #expect(try pixel(of: quarter, x: 24, y: 24).alphaComponent == 0)
        #expect(try pixel(of: quarter, x: 40, y: 40).alphaComponent == 0)
        #expect(try pixel(of: quarter, x: 24, y: 40).alphaComponent == 0)
    }

    @Test func emptyTimerDrawsNoPieAndFullTimerDrawsDisc() throws {
        let empty = StateSymbol.image(for: .timed(shareLeft: 0), highlighted: false)
        let full = StateSymbol.image(for: .timed(shareLeft: 1), highlighted: false)
        #expect(try pixel(of: empty, x: 32, y: 32).alphaComponent == 0)
        #expect(try pixel(of: full, x: 32, y: 32).alphaComponent == 1)
        #expect(try pixel(of: full, x: 24, y: 40).alphaComponent == 1)
    }

    @Test func busySymbolLeavesTheUpperRightOpen() throws {
        let busy = StateSymbol.image(for: .busy, highlighted: false)
        #expect(try pixel(of: busy, x: 7, y: 32).alphaComponent == 1)
        #expect(try pixel(of: busy, x: 32, y: 57).alphaComponent == 1)
        #expect(try pixel(of: busy, x: 52, y: 12).alphaComponent == 0)
    }

    /// Renders the image at 4× into a bitmap; `x` and `y` count pixels from the top left.
    private func pixel(of image: NSImage, x: Int, y: Int) throws -> NSColor {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            NSGraphicsContext.restoreGraphicsState()
        }
        return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }
}
