import AppKit

// MARK: - Coordinate conversion
//
// THIS IS THE PART THAT BITES. There are two global coordinate spaces in play:
//
//   CGEvent / "display space":  origin at the TOP-LEFT of the primary display,
//                               +y points DOWN.
//   AppKit  / "screen space":   origin at the BOTTOM-LEFT of the primary display,
//                               +y points UP.  (NSScreen.screens[0] is by definition
//                               the primary display and its frame.origin is (0, 0).)
//
// Both spaces share the same origin CORNER of the same display and the same x axis,
// and secondary monitors are placed relative to that same origin in both. So the only
// transform needed — on one monitor or six, above/below/left/right — is flipping y
// around the primary display's height. Everything in this app converts here and only
// here; nothing else is allowed to do arithmetic on a y coordinate.

func cocoaPoint(fromDisplayPoint p: CGPoint) -> NSPoint {
    guard let primary = NSScreen.screens.first else {
        return NSPoint(x: p.x, y: p.y)  // no screens; nothing sensible to do
    }
    // primary.frame.origin.y is always 0, so frame.maxY is the primary display's height.
    return NSPoint(x: p.x, y: primary.frame.maxY - p.y)
}

/// The screen whose frame contains a point in AppKit screen space.
func screen(containing point: NSPoint) -> NSScreen {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        ?? NSScreen.main
        ?? NSScreen.screens[0]
}

// MARK: - Formatting for the debug log

func fmt(_ v: CGFloat) -> String { String(format: "%.0f", v) }
func fmtRect(_ r: NSRect) -> String {
    "(\(fmt(r.minX)),\(fmt(r.minY)) \(fmt(r.width))x\(fmt(r.height)))"
}
