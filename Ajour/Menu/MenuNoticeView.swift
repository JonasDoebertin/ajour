import AppKit

/// Shows a menu notice at full contrast. AppKit dims the title of a disabled item, so the notice draws itself instead,
/// with its symbol and text lined up with the other items. It is information, not an action: it takes no highlight and
/// no clicks.
@MainActor final class MenuNoticeView: NSView {
    static let maximumTextWidth: CGFloat = 230

    private static let imageColumnLeading: CGFloat = 16.5
    private static let imageTitleSpacing: CGFloat = 5.5
    private static let trailingInset: CGFloat = 14
    private static let verticalInset: CGFloat = 4
    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let detailFont = NSFont.systemFont(ofSize: 11)

    let titleColor = NSColor.labelColor
    let detailColor = NSColor.secondaryLabelColor
    private(set) var title = ""
    private(set) var detail: String?
    private(set) var symbolImage: NSImage?
    private var text = NSAttributedString()
    /// Until the notice is in a menu, it assumes the column of the alias rows' status symbols, the widest in Ajour's menus.
    private var imageColumnWidth: CGFloat = 16

    var maximumWidth: CGFloat {
        textLeading + Self.maximumTextWidth + Self.trailingInset
    }

    private var textLeading: CGFloat {
        Self.imageColumnLeading + imageColumnWidth + Self.imageTitleSpacing
    }

    init() {
        super.init(frame: .zero)
        autoresizingMask = .width
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    nonisolated override var isFlipped: Bool { true }

    func show(title: String, detail: String?, symbol: String, tone: MenuTone, fullText: String?) {
        self.title = title
        self.detail = detail
        symbolImage = Self.symbolImage(symbol, tone: tone)
        text = Self.text(title: title, titleColor: titleColor, detail: detail, detailColor: detailColor)
        let fullText = fullText ?? [title, detail].compactMap { $0 }.joined(separator: "\n")
        toolTip = fullText
        setAccessibilityLabel(fullText)
        let textSize = Self.size(of: text)
        setFrameSize(NSSize(
            width: textLeading + textSize.width + Self.trailingInset,
            height: textSize.height + 2 * Self.verticalInset
        ))
        needsDisplay = true
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        if let menu = enclosingMenuItem?.menu, let width = Self.imageColumnWidth(of: menu) {
            imageColumnWidth = width
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let symbolImage {
            let firstLineHeight = Self.titleFont.ascender - Self.titleFont.descender + Self.titleFont.leading
            symbolImage.draw(in: NSRect(
                origin: NSPoint(
                    x: Self.imageColumnLeading + (imageColumnWidth - symbolImage.size.width) / 2,
                    y: Self.verticalInset + (firstLineHeight - symbolImage.size.height) / 2
                ),
                size: symbolImage.size
            ))
        }
        text.draw(
            with: NSRect(x: textLeading, y: Self.verticalInset, width: Self.maximumTextWidth, height: bounds.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {}

    /// AppKit makes a menu's image column as wide as its widest image, measured its own way, so a scratch menu with the
    /// same images measures it against an image of known width.
    private static func imageColumnWidth(of menu: NSMenu) -> CGFloat? {
        let images = menu.items.compactMap(\.image)
        guard !images.isEmpty else { return nil }
        return widthOfMenu(showing: images) - referenceMenuWidth + referenceImage.size.width
    }

    private static let referenceImage = NSImage(size: NSSize(width: 1, height: 1))
    private static let referenceMenuWidth = widthOfMenu(showing: [referenceImage])

    private static func widthOfMenu(showing images: [NSImage]) -> CGFloat {
        let menu = NSMenu()
        menu.items = images.map { image in
            let item = NSMenuItem(title: "Image column", action: nil, keyEquivalent: "")
            item.image = image
            return item
        }
        return menu.size.width
    }

    /// Matches the size AppKit draws the images of other items at. Danger symbols carry the danger color; plain ones take
    /// the label color, as the symbols of enabled items do.
    private static func symbolImage(_ name: String, tone: MenuTone) -> NSImage? {
        let color = tone == .danger ? Palette.danger : .labelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular, scale: .small)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    private static func text(title: String, titleColor: NSColor, detail: String?, detailColor: NSColor) -> NSAttributedString {
        let wrapping = NSMutableParagraphStyle()
        wrapping.lineBreakMode = .byWordWrapping
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor, .paragraphStyle: wrapping]
        let text = NSMutableAttributedString(string: title, attributes: titleAttributes)
        if let detail {
            text.append(NSAttributedString(string: "\n", attributes: titleAttributes))
            text.append(NSAttributedString(
                string: detail,
                attributes: [.font: detailFont, .foregroundColor: detailColor, .paragraphStyle: wrapping]
            ))
        }
        return text
    }

    private static func size(of text: NSAttributedString) -> NSSize {
        let bounds = text.boundingRect(
            with: NSSize(width: maximumTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }
}
