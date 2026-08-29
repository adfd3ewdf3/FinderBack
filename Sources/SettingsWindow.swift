import AppKit
import ApplicationServices

// MARK: - Settings: the style tiles
//
// Each tile draws a miniature of Finder's menu with a REAL BarView sitting on it —
// the same class, the same Config knobs, the same drawing code as the live bar. A
// hand-drawn mock-up would drift the first time the design is tuned; this cannot.

final class StyleTile: NSView {
    static let size = NSSize(width: 168, height: 150)

    let style: BarStyle
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }

    private static let menuWidth: CGFloat = 138
    private static let menuHeight: CGFloat = 70
    private static let menuBottomInset: CGFloat = 12

    private let bar: BarView

    /// The menu miniature follows the system appearance (the real bar deliberately
    /// does not — see Config.fillColor), so the tile shows what the user will see.
    private static let menuFill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.14, alpha: 1)
            : NSColor(white: 0.97, alpha: 1)
    }

    init(style: BarStyle) {
        self.style = style
        let menuTop = Self.menuBottomInset + Self.menuHeight
        let menuX = ((Self.size.width - Self.menuWidth) / 2).rounded()
        // Exactly the geometry NavPanel.show uses: same width as the menu, bottom
        // edge dropped menuOverlap below the menu's top edge.
        bar = BarView(style: style,
                      frame: NSRect(x: menuX,
                                    y: menuTop - Config.menuOverlap,
                                    width: Self.menuWidth,
                                    height: style.height + Config.menuOverlap))
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        addSubview(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        // Selection chrome first, behind everything.
        let card = bounds.insetBy(dx: 1, dy: 1)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            cardPath.fill()
            NSColor.controlAccentColor.setStroke()
            cardPath.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            cardPath.lineWidth = 1
        }
        cardPath.stroke()

        // The menu miniature the bar is sitting on.
        let menu = NSRect(x: ((bounds.width - Self.menuWidth) / 2).rounded(),
                          y: Self.menuBottomInset,
                          width: Self.menuWidth,
                          height: Self.menuHeight)
        let menuPath = NSBezierPath(roundedRect: menu, xRadius: Config.cornerRadius, yRadius: Config.cornerRadius)
        Self.menuFill.setFill()
        menuPath.fill()

        // A couple of plausible Finder rows, so the seam has something to sit against.
        let rowFont = NSFont.menuFont(ofSize: 11)
        let attrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: NSColor.labelColor]
        var rowTop = menu.maxY - 10
        for title in ["New Folder", "Get Info"] {
            let text = NSAttributedString(string: title, attributes: attrs)
            text.draw(at: NSPoint(x: menu.minX + 16, y: (rowTop - 14).rounded()))
            rowTop -= 24
        }
        NSColor.separatorColor.setStroke()
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: menu.minX + 10, y: (menu.maxY - 34).rounded() + 0.5))
        rule.line(to: NSPoint(x: menu.maxX - 10, y: (menu.maxY - 34).rounded() + 0.5))
        rule.lineWidth = 1
        rule.stroke()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    /// Whole tile is the target; the bar inside must not eat the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
}

// MARK: - Settings window
//
// The app has no Dock icon and no menu bar of its own, so this window is reachable
// two ways: the menu bar item, and re-opening the app (double-clicking it in Finder
// while it is already running sends a reopen event, which we turn into "show this").

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var tiles: [StyleTile] = []
    private var loginCheck: NSButton?
    private var axLabel: NSTextField?
    /// Held so the layout keeps a strong reference and for future enable/disable use.
    private var axButton: NSButton?
    /// Polls while the window is open, so the accessibility row turns green the
    /// moment the user flips the switch in System Settings — without them having to
    /// come back here and click something.
    private var axPoll: Timer?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) {
            [weak self] _ in self?.syncControls()
        }
    }

    func show() {
        if window == nil { build() }
        guard let window else { return }
        // .accessory apps can still activate and take key focus; without this the
        // window appears behind whatever the user was in.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
        syncControls()
        startAXPoll()
    }

    private func build() {
        let width: CGFloat = 400
        let height: CGFloat = 466
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "FinderBack"
        w.isReleasedWhenClosed = false   // we keep and reuse the one window
        w.delegate = self
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        w.contentView = content

        let pad: CGFloat = 20
        var y = height - pad   // cursor walks DOWN from the top edge

        func place(_ view: NSView, height h: CGFloat, indent: CGFloat = 0, gapAfter: CGFloat = 0) {
            y -= h
            view.frame = NSRect(x: pad + indent, y: y, width: width - pad * 2 - indent, height: h)
            content.addSubview(view)
            y -= gapAfter
        }

        place(Self.text("FinderBack", font: .systemFont(ofSize: 15, weight: .semibold)), height: 20)
        place(Self.text("Back and Forward buttons on Finder's right-click menu.",
                        font: .systemFont(ofSize: 11), color: .secondaryLabelColor),
              height: 15, gapAfter: 20)

        place(Self.text("STYLE", font: .systemFont(ofSize: 10, weight: .semibold),
                        color: .secondaryLabelColor),
              height: 13, gapAfter: 8)

        // The two tiles, side by side, centred as a pair.
        let gap: CGFloat = 16
        let pairWidth = StyleTile.size.width * 2 + gap
        var tileX = ((width - pairWidth) / 2).rounded()
        y -= StyleTile.size.height
        for style in BarStyle.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let tile = StyleTile(style: style)
            tile.frame.origin = NSPoint(x: tileX, y: y)
            tile.onClick = { Preferences.shared.style = style }
            content.addSubview(tile)
            tiles.append(tile)

            let caption = Self.text(style.displayName, font: .systemFont(ofSize: 12, weight: .medium),
                                    align: .center)
            caption.frame = NSRect(x: tileX, y: y - 20, width: StyleTile.size.width, height: 16)
            content.addSubview(caption)

            let sub = Self.text(style.summary, font: .systemFont(ofSize: 10),
                                color: .secondaryLabelColor, align: .center)
            sub.frame = NSRect(x: tileX - 6, y: y - 35, width: StyleTile.size.width + 12, height: 14)
            content.addSubview(sub)

            tileX += StyleTile.size.width + gap
        }
        y -= 35 + 18

        place(Self.separator(), height: 1, gapAfter: 14)

        let login = NSButton(checkboxWithTitle: "Open FinderBack at login", target: self,
                             action: #selector(toggleLogin(_:)))
        login.font = .systemFont(ofSize: 12)
        place(login, height: 18, gapAfter: 12)
        loginCheck = login

        let ax = Self.text("", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        ax.usesSingleLineMode = false
        ax.cell?.wraps = true
        place(ax, height: 30, gapAfter: 6)
        axLabel = ax

        // Kept visible even when permission is already granted: hiding it left an
        // empty hole in the layout, and it is still the fastest way to the pane when
        // the user wants to check or revoke.
        let axBtn = NSButton(title: "Open Accessibility Settings", target: self,
                             action: #selector(openAXSettings))
        axBtn.bezelStyle = .rounded
        axBtn.controlSize = .small
        axBtn.font = .systemFont(ofSize: 11)
        axBtn.sizeToFit()
        axBtn.frame = NSRect(x: pad, y: y - 20, width: max(180, axBtn.frame.width), height: 20)
        content.addSubview(axBtn)
        axButton = axBtn
        y -= 20 + 14

        place(Self.separator(), height: 1, gapAfter: 10)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let versionLabel = Self.text("Version \(version)", font: .systemFont(ofSize: 11),
                                     color: .tertiaryLabelColor)
        versionLabel.frame = NSRect(x: pad, y: y - 20, width: 150, height: 16)
        content.addSubview(versionLabel)

        let quit = NSButton(title: "Quit FinderBack", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        quit.font = .systemFont(ofSize: 11)
        quit.sizeToFit()
        quit.frame = NSRect(x: width - pad - max(120, quit.frame.width), y: y - 22,
                            width: max(120, quit.frame.width), height: 22)
        content.addSubview(quit)

        window = w
    }

    /// Every control reads its value from the source of truth, never from a cached
    /// copy — the style can change from the menu bar item, and Login Items can be
    /// switched off in System Settings behind our back.
    private func syncControls() {
        let current = BarStyle.current
        for tile in tiles { tile.isSelected = (tile.style == current) }
        loginCheck?.state = LoginItem.isEnabled ? .on : .off

        let trusted = AXIsProcessTrusted()
        axLabel?.stringValue = trusted
            ? "Accessibility access granted — FinderBack is watching for right-clicks in Finder."
            : "FinderBack needs Accessibility access to see right-clicks and send ⌘[ / ⌘] to Finder. Turn on FinderBack in the list, then come back."
        axLabel?.textColor = trusted ? .secondaryLabelColor : .systemOrange
    }

    private func startAXPoll() {
        axPoll?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.syncControls() }
        RunLoop.main.add(timer, forMode: .common)
        axPoll = timer
    }

    func windowWillClose(_ notification: Notification) {
        axPoll?.invalidate()
        axPoll = nil
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        if let problem = LoginItem.set(sender.state == .on) {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = problem
            alert.runModal()
        }
        loginCheck?.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func openAXSettings() {
        // Re-prompting also re-adds us to the list if the entry was removed.
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // Small builders, so the layout above reads as layout and not as boilerplate.

    private static func text(_ s: String, font: NSFont, color: NSColor = .labelColor,
                             align: NSTextAlignment = .left) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = font
        f.textColor = color
        f.alignment = align
        return f
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
