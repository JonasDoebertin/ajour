import AppKit

/// The 16 pt symbols for alias states, drawn by hand so the pie can show any share of the timer.
enum StateSymbol {
    private static let canvas: CGFloat = 16
    private static let ringDiameter: CGFloat = 14
    private static let ringInnerRadiusShare: CGFloat = 0.76
    private static let dotDiameter: CGFloat = 6
    private static let pieDiameter: CGFloat = 8
    private static let slashWidth: CGFloat = 1.6
    private static let slashReach: CGFloat = 3.5
    private static let twelveOClock: CGFloat = 90

    static func image(for kind: AliasStatus.Kind, highlighted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
            let color = highlighted ? NSColor.white : tint(for: kind)
            color.set()
            draw(kind, in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func tint(for kind: AliasStatus.Kind) -> NSColor {
        switch kind {
        case .enabled: Palette.stateOn
        case .timed: Palette.stateTimed
        case .disabled, .busy: Palette.stateOff
        }
    }

    private static func draw(_ kind: AliasStatus.Kind, in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        switch kind {
        case .enabled:
            ring(at: center).fill()
            disc(diameter: dotDiameter, at: center).fill()
        case .timed(let shareLeft):
            ring(at: center).fill()
            pie(share: shareLeft, at: center)?.fill()
        case .disabled:
            ring(at: center).fill()
            slash(at: center).stroke()
        case .busy:
            openRing(at: center).stroke()
        }
    }

    private static var ringWidth: CGFloat {
        ringDiameter / 2 * (1 - ringInnerRadiusShare)
    }

    private static func ring(at center: NSPoint) -> NSBezierPath {
        let path = disc(diameter: ringDiameter, at: center)
        path.append(disc(diameter: ringDiameter * ringInnerRadiusShare, at: center).reversed)
        return path
    }

    /// Three quarters of the ring, leaving the upper right open like a spinner.
    private static func openRing(at center: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: ringDiameter / 2 - ringWidth / 2,
            startAngle: twelveOClock,
            endAngle: 360,
            clockwise: false
        )
        path.lineWidth = ringWidth
        path.lineCapStyle = .round
        return path
    }

    private static func disc(diameter: CGFloat, at center: NSPoint) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(
            x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter
        ))
    }

    private static func pie(share: Double, at center: NSPoint) -> NSBezierPath? {
        let share = min(max(share, 0), 1)
        guard share > 0 else { return nil }
        guard share < 1 else { return disc(diameter: pieDiameter, at: center) }
        let path = NSBezierPath()
        path.move(to: center)
        path.appendArc(
            withCenter: center,
            radius: pieDiameter / 2,
            startAngle: twelveOClock,
            endAngle: twelveOClock - 360 * CGFloat(share),
            clockwise: true
        )
        path.close()
        return path
    }

    private static func slash(at center: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x + slashReach, y: center.y + slashReach))
        path.line(to: NSPoint(x: center.x - slashReach, y: center.y - slashReach))
        path.lineWidth = slashWidth
        path.lineCapStyle = .round
        return path
    }
}
