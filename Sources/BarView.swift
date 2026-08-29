import AppKit

// MARK: - The bar's shape
//
// Drawn by hand rather than with layer.cornerRadius for two reasons:
//
//  1. The bottom edge must have NO outline. macOS draws its own hairline rim around a
//     window's shadow, all the way round, and there is no way to suppress one side of
//     it — so the window shadow is off and this view draws the border itself, on the
//     top and sides only. The bottom edge is where the bar meets the menu, and any
//     line there is exactly what breaks the illusion.
//  2. The bottom corners are INVERTED — scooped up and inward — so they cradle the
//     menu's rounded top corners rather than cutting flat across them.

class BarBackgroundView: NSView {
    override var isOpaque: Bool { false }

    /// Walks the outline from the bottom-left corner counterclockwise: up the left
    /// side, round the two rounded top corners, down the right side, ending at the
    /// bottom-right corner. The bottom edge itself is NOT included — callers decide
    /// whether to close it (for filling) or leave it open (for stroking).
    private func sidesAndTop(in r: NSRect) -> NSBezierPath {
        let top = min(Config.cornerRadius, r.width / 2, r.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.minY))
        path.line(to: NSPoint(x: r.minX, y: r.maxY - top))
        path.appendArc(withCenter: NSPoint(x: r.minX + top, y: r.maxY - top), radius: top,
                       startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: NSPoint(x: r.maxX - top, y: r.maxY))
        path.appendArc(withCenter: NSPoint(x: r.maxX - top, y: r.maxY - top), radius: top,
                       startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: r.maxX, y: r.minY))
        return path
    }

    /// The bottom edge, right to left. NOT one long bow: the deep coverage is only
    /// needed at the menu's rounded corners, and a full-width curve dragged visible
    /// diagonals across the first menu item's hover highlight. So the edge swoops up
    /// from each outer corner over `bottomSwoopWidth`, then runs FLAT at
    /// `bottomCurveDepth` across the middle — the flat part stays just 1-2pt below
    /// the menu's top edge, hiding its border while barely touching the highlight.
    private func bottomCurve(on path: NSBezierPath, in r: NSRect) {
        let flat = min(Config.bottomCurveDepth, r.height / 2)
        let swoop = min(Config.bottomSwoopWidth, r.width / 2)
        // Right swoop: from the bottom-right corner up to the flat level. Control
        // points chosen so the curve leaves the corner steeply and lands tangent to
        // the flat run (horizontal at its end).
        path.curve(to: NSPoint(x: r.maxX - swoop, y: r.minY + flat),
                   controlPoint1: NSPoint(x: r.maxX - swoop * 0.4, y: r.minY),
                   controlPoint2: NSPoint(x: r.maxX - swoop * 0.7, y: r.minY + flat))
        // Flat middle.
        path.line(to: NSPoint(x: r.minX + swoop, y: r.minY + flat))
        // Left swoop back down to the bottom-left corner.
        path.curve(to: NSPoint(x: r.minX, y: r.minY),
                   controlPoint1: NSPoint(x: r.minX + swoop * 0.7, y: r.minY + flat),
                   controlPoint2: NSPoint(x: r.minX + swoop * 0.4, y: r.minY))
    }

    override func draw(_ dirtyRect: NSRect) {
        let fillPath = sidesAndTop(in: bounds)
        bottomCurve(on: fillPath, in: bounds)
        fillPath.close()
        Config.fillColor.setFill()
        fillPath.fill()

        // Stroke the sides and top only. The bottom edge is where the bar meets the
        // menu, and any line there is exactly what breaks the illusion — so the path
        // is left open and the curve is never stroked.
        let inset = Config.borderWidth / 2
        let outline = sidesAndTop(in: bounds.insetBy(dx: inset, dy: inset))
        Config.borderColor.setStroke()
        outline.lineWidth = Config.borderWidth
        outline.lineCapStyle = .butt
        outline.stroke()
    }
}

// MARK: - The bar's contents
//
// Shape plus decoration in ONE view, so there is a single source of truth for what
// the bar looks like. NavPanel puts it in a panel over Finder's menu; the settings
// window puts the very same view in its preview tiles — a preview that renders the
// real thing cannot drift away from it as the design is tuned.

final class BarView: BarBackgroundView {
    let style: BarStyle

    // .arrows
    private var leftArrow: NSView?
    private var rightArrow: NSView?
    private var divider: NSBox?
    // .labels
    private var backLabel: NSTextField?
    private var forwardLabel: NSTextField?
    private var backIcon: NSImageView?
    private var forwardIcon: NSImageView?

    init(style: BarStyle, frame: NSRect) {
        self.style = style
        super.init(frame: frame)

        // Everything below is DECORATION. In the panel none of it is ever clicked in
        // the normal AppKit sense — while Finder's menu is tracking, no click reaches
        // that window. Hit testing happens in the event tap, against
        // NavPanel.direction(for:).
        switch style {
        case .arrows:
            let left = Self.arrow(symbol: "arrow.left", fallback: "\u{2190}")
            let right = Self.arrow(symbol: "arrow.right", fallback: "\u{2192}")
            let line = NSBox()
            line.boxType = .separator
            [left, right, line].forEach(addSubview)
            (leftArrow, rightArrow, divider) = (left, right, line)

        case .labels:
            let back = Self.label("Back")
            let forward = Self.label("Forward")
            let backImage = Self.rowIcon("arrow.left")
            let forwardImage = Self.rowIcon("arrow.right")
            [back, forward, backImage, forwardImage].forEach(addSubview)
            (backLabel, forwardLabel) = (back, forward)
            (backIcon, forwardIcon) = (backImage, forwardImage)
        }

        layOut(size: frame.size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// One arrow, in a container view that gets sized to a whole cell by layOut.
    /// Uses SF Symbols rather than the text arrows "\u{2190}" and "\u{2192}": those
    /// two characters are not guaranteed to be the same width or to have matching
    /// side bearings in the system font, which made the pair look lopsided and the
    /// right arrow look slightly smaller. arrow.left and arrow.right are drawn as
    /// exact mirrors of each other.
    private static func arrow(symbol: String, fallback: String) -> NSView {
        let container = NSView()
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        {
            let view = NSImageView()
            view.image = image
            view.imageScaling = .scaleNone
            view.imageAlignment = .alignCenter   // centres in both axes within its frame
            view.contentTintColor = Config.glyphColor
            container.addSubview(view)
        } else {
            container.addSubview(glyph(fallback))
        }
        return container
    }

    private static func glyph(_ s: String) -> NSTextField {
        // Text fallback only. The centring MUST live in the attributed string's
        // paragraph style: setting NSTextField.alignment does nothing when the field
        // was built from an attributed string — that string's own (default, left)
        // alignment wins.
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center

        let f = NSTextField(labelWithAttributedString: NSAttributedString(
            string: s,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: Config.glyphColor,
                .paragraphStyle: centred,
            ]
        ))
        f.sizeToFit()
        return f
    }

    /// The small leading icon on a row, sitting in the same column Finder puts its
    /// menu item icons in.
    private static func rowIcon(_ symbol: String) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Config.rowIconPointSize,
                                                                 weight: .regular))
        view.imageScaling = .scaleNone
        view.imageAlignment = .alignCenter
        view.contentTintColor = Config.glyphColor
        return view
    }

    /// A menu row's text. NSFont.menuFont is the same face and size AppKit uses for
    /// real menu items, so the rows sit in the same typographic rhythm as the Finder
    /// menu directly below them.
    private static func label(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithAttributedString: NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: Config.labelFontSize),
                .foregroundColor: Config.glyphColor,
            ]
        ))
        f.sizeToFit()
        return f
    }

    /// The bar's width changes with the menu it sits on, so contents are laid out on
    /// every resize rather than pinned at fixed positions.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layOut(size: newSize)
        needsDisplay = true   // the silhouette depends on the width
    }

    private func layOut(size: NSSize) {
        // `size` includes the overlap strip along the bottom that is hidden behind the
        // menu. Contents are positioned from the TOP of the panel, so they stay in the
        // visible part regardless of how deep the overlap is.
        let width = size.width
        let h = size.height
        let visibleH = h - Config.menuOverlap

        switch style {
        case .arrows:
            guard let leftArrow, let rightArrow, let divider else { return }
            let mid = (width / 2).rounded()
            let cell = Config.glyphCellWidth
            // The arrows are centred in the visible area LESS the top headroom, and
            // anchored at its bottom, so arrowsTopPadding only ever pads the top edge.
            let arrowsH = visibleH - Config.arrowsTopPadding

            // Two equal cells straddling the midline, so the pair is symmetric about it.
            for (container, x) in [(leftArrow, mid - cell), (rightArrow, mid)] {
                container.frame = NSRect(x: x, y: Config.menuOverlap, width: cell, height: arrowsH)
                for sub in container.subviews {
                    if sub is NSImageView {
                        sub.frame = container.bounds          // NSImageView self-centres
                    } else {
                        sub.frame = NSRect(x: 0,
                                           y: ((arrowsH - sub.frame.height) / 2).rounded(),
                                           width: cell,
                                           height: sub.frame.height)
                    }
                }
            }
            // The divider is 1pt wide, so drawing it AT `mid` puts the whole point on
            // the right arrow's side of the midline: the left arrow ends up 22.5pt
            // from the divider's centre and the right arrow 21.5pt. That 1pt is enough
            // to read as "not quite centred". Straddle the midline instead.
            divider.frame = NSRect(x: mid - 0.5, y: Config.menuOverlap + 6, width: 1, height: arrowsH - 12)

        case .labels:
            guard let backLabel, let forwardLabel, let backIcon, let forwardIcon else { return }
            // Row 0 is the TOP row. Cocoa's y grows upward, so row n's top edge is
            // measured down from the panel's top.
            for (index, row) in [(backLabel, backIcon), (forwardLabel, forwardIcon)].enumerated() {
                let (label, icon) = row
                let rowTop = h - Config.rowsTopPadding - CGFloat(index) * Config.rowHeight
                let rowBottom = rowTop - Config.rowHeight

                icon.frame = NSRect(x: Config.rowIconInsetX, y: rowBottom,
                                    width: Config.rowIconWidth, height: Config.rowHeight)
                let textHeight = label.frame.height
                label.frame = NSRect(
                    x: Config.labelInsetX,
                    y: (rowBottom + (Config.rowHeight - textHeight) / 2).rounded(),
                    width: max(0, width - Config.labelInsetX),
                    height: textHeight
                )
            }
        }
    }
}
