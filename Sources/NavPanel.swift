import AppKit

// MARK: - The panel

final class NavPanel {
    let panel: NSPanel
    private let style: BarStyle
    private let body: BarView

    init(style: BarStyle) {
        self.style = style
        let initial = NSRect(x: 0, y: 0, width: Config.initialWidth,
                             height: style.height + Config.menuOverlap)

        panel = NSPanel(
            contentRect: initial,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // One level ABOVE Finder's menu: the bar's bottom strip is drawn OVER the top
        // of the menu, hiding the menu's border and rounded corners there. Below the
        // menu instead, the menu's own edge and shadow stayed visible across the seam.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.hidesOnDeactivate = false    // we are never the active app; must stay put
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // OFF on purpose: the system shadow comes with a hairline rim on ALL four
        // sides, and the bottom one is the seam we are trying to erase. The border is
        // drawn by BarBackgroundView instead.
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        body = BarView(style: style, frame: initial)
        body.autoresizingMask = [.width, .height]
        panel.contentView = body
    }

    /// Which way a click inside the bar means. The clickable regions are always the
    /// full halves of the bar — left/right for .arrows, top/bottom for .labels — so
    /// the targets stay large regardless of where the glyphs are drawn.
    func direction(for point: NSPoint) -> NavDirection? {
        // Only the part ABOVE the menu counts. The overlap strip along the bottom is
        // behind Finder's menu, so a click there is a click on the menu's first row —
        // treating it as a hit on our bar would fire navigation instead.
        var f = panel.frame
        f.origin.y += Config.menuOverlap
        f.size.height -= Config.menuOverlap
        guard f.contains(point) else { return nil }
        switch style {
        case .arrows: return point.x < f.midX ? .back : .forward
        case .labels: return point.y > f.midY ? .back : .forward   // top row is Back
        }
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    /// Sit flush on top of a measured menu: same left edge, same width, bottom edge
    /// touching the menu's top edge.
    func show(onMenuFrame menuDisplayFrame: CGRect) {
        // AX gives the menu's TOP-left in display coordinates; converting it yields
        // the cocoa y of the menu's top edge, which is exactly where our bottom goes.
        let topLeft = cocoaPoint(fromDisplayPoint: menuDisplayFrame.origin)
        // Drop the bottom edge past the menu's top edge and grow by the same amount,
        // so the height visible above the menu is still style.height.
        place(NSRect(x: topLeft.x, y: topLeft.y - Config.menuOverlap,
                     width: menuDisplayFrame.width, height: style.height + Config.menuOverlap),
              note: "flush on measured menu \(fmtRect(menuDisplayFrame))")
    }

    private func place(_ proposed: NSRect, note: String) {
        var rect = proposed
        let vf = screen(containing: NSPoint(x: rect.midX, y: rect.midY)).visibleFrame

        // Clamp onto the visible screen so we can never draw partly off-display.
        rect.origin.x = min(max(rect.origin.x, vf.minX + Config.screenMargin),
                            vf.maxX - rect.width - Config.screenMargin)
        rect.origin.y = min(max(rect.origin.y, vf.minY + Config.screenMargin),
                            vf.maxY - rect.height - Config.screenMargin)

        // setFrame resizes the content view, which re-lays out and redraws it.
        panel.setFrame(rect, display: true)
        // orderFrontRegardless, NOT makeKeyAndOrderFront: we must not steal focus from
        // Finder, and we must appear even though our app is not active.
        panel.orderFrontRegardless()
        dbg("  panel SHOWN frame=\(fmtRect(panel.frame)) — \(note)")
    }

    func hide(reason: String) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        dbg("  panel HIDDEN (\(reason))")
    }
}
