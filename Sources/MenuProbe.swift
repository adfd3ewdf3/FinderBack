import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Measuring Finder's menu
//
// Everything about "sit flush on top of the menu" needs three numbers we cannot
// guess: the menu's left edge, its top edge, and its width. Finder sizes its context
// menu to its contents (a right-click on a file is much wider than one on empty
// space) and nudges it around near screen edges, so hard-coded offsets are always
// wrong somewhere.
//
// So we ask the accessibility API where the menu actually is. This is READ-ONLY and
// geometry-only: position and size of one AXMenu element. Nothing is read from the
// menu's contents, and nothing is clicked or activated through it.

enum MenuProbe {
    /// One system-wide element, with a hard timeout. These queries run inside the
    /// event-tap callback, and a slow AX round trip there would get the tap disabled
    /// by the system for being unresponsive.
    private static let system: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.2)
        return element
    }()

    /// Roles that mean the pointer was ON something — a file, a folder, a list row —
    /// rather than on empty space. Anything else (scroll areas, groups, the desktop
    /// list itself) counts as empty space.
    static let itemRoles: Set<String> = [
        "AXImage", "AXRow", "AXCell", "AXStaticText", "AXTextField",
        "AXButton", "AXCheckBox", "AXMenuButton", "AXDisclosureTriangle",
    ]

    /// The accessibility role of whatever is directly under a point. Queried at
    /// right-mouse-DOWN, before the menu exists, so it describes what was clicked.
    /// Role only — no filename, no path, nothing about the item's contents.
    static func role(under point: CGPoint) -> String? {
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
              let element = found else { return nil }
        return role(of: element)
    }

    /// Points to test, relative to the cursor, in CGEvent display coordinates.
    /// Normally the menu opens down-and-right of the cursor; the other three cover
    /// the cases where Finder flips it near a screen edge.
    private static let probeOffsets: [CGPoint] = [
        CGPoint(x: 20, y: 30), CGPoint(x: -20, y: 30),
        CGPoint(x: 20, y: -30), CGPoint(x: -20, y: -30),
    ]

    /// The frame of the open context menu, in display coordinates, or nil if there
    /// isn't one yet.
    static func openMenuFrame(nearCursor cursor: CGPoint) -> CGRect? {
        for off in probeOffsets {
            let p = CGPoint(x: cursor.x + off.x, y: cursor.y + off.y)
            if let frame = menuFrame(at: p) { return frame }
        }
        return nil
    }

    /// Cheap "is that menu still there?" check for the watchdog. One probe at the
    /// centre of the menu we already measured, and a short walk up — a menu item's
    /// AXMenu is one or two levels above it. The full four-point, eight-level search
    /// used to find the menu costs up to 32 accessibility round trips, which is what
    /// made dismissal lag by ~300ms.
    static func isMenuOpen(frame: CGRect) -> Bool {
        menuFrame(at: CGPoint(x: frame.midX, y: frame.midY), maxDepth: 3) != nil
    }

    private static func menuFrame(at p: CGPoint, maxDepth: Int = 8) -> CGRect? {
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &found) == .success,
              var element = found else { return nil }

        // The hit usually lands on a menu ITEM, so walk up to the enclosing AXMenu.
        for _ in 0 ..< maxDepth {
            if role(of: element) == (kAXMenuRole as String) { return frame(of: element) }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { return nil }
            element = unsafeDowncast(parent as AnyObject, to: AXUIElement.self)
        }
        return nil
    }

    static func role(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(posRef as AnyObject, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeRef as AnyObject, to: AXValue.self), .cgSize, &size),
              size.width > 1, size.height > 1
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
