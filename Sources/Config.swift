import AppKit
import CoreGraphics
import Foundation

// MARK: - Tunables

enum Config {
    static let finderBundleID = "com.apple.finder"

    /// Height of the bar visible ABOVE the menu (.arrows style). Its WIDTH and
    /// POSITION come from measuring Finder's real menu at runtime (see MenuProbe).
    /// The arrows are centred in this height, so shrinking it trims the top edge AND
    /// walks the arrows down towards the menu's first item — which is the knob for
    /// "too much dead space above the arrows". Don't go below ~16: the top corner
    /// radius is 12 and the shape starts to look pinched.
    static let barHeight: CGFloat = 22

    /// Extra headroom added ABOVE the arrows (.arrows style). The bar grows by this
    /// much at its top edge and the arrows stay where they were relative to the menu,
    /// so this is purely "don't crowd the arrows against the top border" — it does
    /// NOT change the gap down to the menu's first item (that is barHeight).
    static let arrowsTopPadding: CGFloat = 3

    static let initialWidth: CGFloat = 190

    /// Fixed dark fill, matched to Finder's menu by eye. Because this is a hard-coded
    /// dark colour the glyphs are hard-coded light too — the bar does not follow
    /// light mode.
    static let fillColor = NSColor(red: 0x13 / 255.0, green: 0x13 / 255.0, blue: 0x13 / 255.0, alpha: 1)
    static let glyphColor = NSColor(white: 0.92, alpha: 1)
    /// The hairline around the bar, matched to the one macOS draws around a menu.
    static let borderColor = NSColor(white: 1.0, alpha: 0.28)
    /// 1 is a hairline at 1pt (two device pixels on a Retina display). 0.5 gives a
    /// single-pixel line, which reads sharper but fainter.
    static let borderWidth: CGFloat = 1

    /// The bottom edge runs FLAT at this height above the panel's bottom for most of
    /// its width, swooping down to the bottom only at the two outer corners. The flat
    /// part therefore sits (menuOverlap - this) below the menu's top edge — keep that
    /// difference >= 1 so the menu's own top border stays covered. Raising this lifts
    /// the flat middle closer to the menu top (less intrusion into the hover
    /// highlight); the corners always reach the full menuOverlap depth.
    static let bottomCurveDepth: CGFloat = 10

    /// Width of each corner swoop. Wider = a more gradual dip; narrower = the flat
    /// middle extends closer to the corners. Should comfortably exceed the menu's
    /// ~12pt corner rounding so the swoop fully wraps it.
    static let bottomSwoopWidth: CGFloat = 26

    /// Width of each arrow's cell; the pair is centred on the bar's midline.
    /// (.arrows style only.)
    static let glyphCellWidth: CGFloat = 44

    // --- .labels style: two stacked menu rows, the way Chrome does it -------------
    /// Height of one row. Matched by eye to a Finder menu row.
    static let rowHeight: CGFloat = 24
    /// Space above the first row ("Back") — the gap under the bar's top edge.
    static let rowsTopPadding: CGFloat = 4
    /// Space below the last row ("Forward") — the gap down to the menu. Smaller
    /// brings Forward closer to "New Folder".
    static let rowsBottomPadding: CGFloat = 1
    /// Row text inset, chosen to line up with Finder's item labels, which sit past
    /// their icons.
    static let labelInsetX: CGFloat = 34
    /// The row icon's column, matching where Finder puts its menu item icons.
    static let rowIconInsetX: CGFloat = 12
    static let rowIconWidth: CGFloat = 18
    static let rowIconPointSize: CGFloat = 13
    /// 0 means "the system's standard menu font size", whatever that is on this OS.
    static let labelFontSize: CGFloat = 0

    /// Only show the bar when the right-click landed on empty space, not on a file
    /// or folder. Back/Forward are window navigation, so they have no business on an
    /// item's menu. Set false to show it everywhere.
    static let onlyOnEmptySpace = true

    /// When a left-click outside dismisses the menu, macOS fades the menu out over a
    /// beat rather than snapping it away — and our instant orderOut made the bar
    /// vanish visibly ahead of it. Wait this long before hiding, so both leave
    /// together. Only applies to the click-outside path; a click ON the bar, or a
    /// dismissing key, still hides immediately.
    static let dismissLinger: TimeInterval = 0.04

    /// How often to re-check that Finder's menu is still open while the bar is up.
    /// This is the backstop for dismissals we can't see directly — Mission Control, a
    /// hot corner, ⌘-Tab. It only runs while the bar is on screen.
    static let menuWatchInterval: TimeInterval = 0.04

    /// How long to wait for Finder's menu to actually exist before measuring it.
    /// The bar is not shown until a measurement succeeds; if the menu never appears
    /// (e.g. the right-click only dismissed a previous menu) no bar is shown at all.
    /// The first entry is 0: by the time we get here the role lookup has already
    /// burned 10-40ms of real time, so the menu is often up already and there is no
    /// reason to wait before the first attempt. The rest ramp up gently.
    static let probeDelays: [TimeInterval] = [0, 0.012, 0.025, 0.045, 0.080, 0.130, 0.220, 0.330]

    /// Corner radius of Finder's context menu, matched here. Only the TOP corners are
    /// rounded; the bottom is square and runs on underneath the menu.
    static let cornerRadius: CGFloat = 12

    /// How far the bar extends DOWN past the menu's top edge, drawn OVER the menu.
    /// This covers the menu's own top border and rounded top corners, which is what
    /// was breaking the illusion. Too large and it starts clipping the menu's first
    /// row — the menu only has a few points of padding above its first item.
    /// Set to 0 to go back to sitting flush on top with no overlap.
    static let menuOverlap: CGFloat = 12

    /// Finder's menu is STILL OPEN at the instant our tap sees the left-mouse-down.
    /// If we post ⌘[ immediately, Finder's modal menu-tracking loop swallows it.
    /// This delay lets the click dismiss the menu first. Bump it if navigation
    /// sometimes doesn't fire; lower it if it feels sluggish.
    static let navigationDelay: TimeInterval = 0.15

    /// Keep this much space between the panel and the edge of the screen.
    static let screenMargin: CGFloat = 6

    static let keyLeftBracket: CGKeyCode = 33   // [  ->  ⌘[  = Back
    static let keyRightBracket: CGKeyCode = 30  // ]  ->  ⌘]  = Forward
    /// Keys that dismiss an open context menu outright, so the bar should go with it
    /// immediately rather than waiting for the watchdog to notice. Letters and arrows
    /// are deliberately absent: those navigate within an open menu. Keycodes are only
    /// ever compared against this set — never logged or stored.
    static let dismissKeys: Set<Int64> = [
        53,  // escape
        49,  // space   (dismisses the menu and opens Quick Look)
        36,  // return
        76,  // keypad enter
        48,  // tab
    ]
}
