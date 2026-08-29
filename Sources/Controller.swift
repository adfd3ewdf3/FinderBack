import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - The event tap callback
//
// Called on the main run loop for every left/right mouse down and key down in the
// session. It is LISTEN-ONLY (kCGEventTapOptionListenOnly): the return value is
// ignored, we cannot modify or swallow anything, and if this function were ever to
// hang it could not wedge the user's mouse. That is the entire reason for the design.
//
// The trick this app exists for: while Finder runs its context menu, that modal
// menu-tracking loop excludes other applications' windows from receiving events, so
// our panel can be VISIBLE next to the menu but can never be CLICKED. The tap,
// however, sees the mouse-down before AppKit routes it to the menu. So we do our own
// hit test here and fire navigation ourselves; the same click then falls through and
// dismisses Finder's menu, which is what we want anyway.

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<Controller>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout:
        // macOS disables a tap whose callback was too slow. Just turn it back on.
        info("!! tap disabled by TIMEOUT — re-enabling")
        controller.reenableTap()
    case .tapDisabledByUserInput:
        info("!! tap disabled by user input — re-enabling")
        controller.reenableTap()
    default:
        controller.handle(type: type, event: event)
    }

    // Listen-only taps: this return value is discarded by the system.
    return Unmanaged.passUnretained(event)
}

// MARK: - Controller

final class Controller: NSObject, NSApplicationDelegate {
    /// Rebuilt (not mutated) when the style preference changes — a NavPanel's style
    /// is fixed at construction, and throwing the old panel away is far simpler than
    /// making every view swap its contents.
    private var nav = NavPanel(style: BarStyle.current)
    private var statusItem: StatusItem?
    private var tap: CFMachPort?
    /// Runs only while we are waiting for Accessibility permission, and stops the
    /// moment the tap starts.
    private var permissionPoll: Timer?
    /// Bumped on every right-click and every hide, so an in-flight menu measurement
    /// from a previous right-click can't pop the bar back up after the fact.
    private var probeGeneration = 0
    /// Runs while the bar is visible, checking that the menu it is attached to still
    /// exists.
    private var menuWatch: Timer?
    /// Cached because handle() runs for every click and keystroke on the machine, and
    /// asking NSWorkspace each time is a cross-process lookup on the critical path.
    /// Kept current by the didActivateApplication observer below.
    private var frontmostBundleID: String?
    private var runLoopSource: CFRunLoopSource?

    // MARK: Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        info("FinderBack starting (pid \(ProcessInfo.processInfo.processIdentifier))")

        installMainMenu()
        statusItem = StatusItem()

        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Requirement: hide when Finder stops being frontmost.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bid = app?.bundleIdentifier ?? "unknown"
            self?.frontmostBundleID = app?.bundleIdentifier
            if bid != Config.finderBundleID {
                self?.hidePanel("frontmost app is now \(bid)")
            }
        }

        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) {
            [weak self] _ in self?.rebuildPanel()
        }

        // An app the user double-clicks must not exit when it can't work yet. If
        // permission is missing we put the settings window up — which explains the
        // situation and links to the right pane — and watch for the switch to flip.
        if AXIsProcessTrusted() {
            info("accessibility: TRUSTED")
            beginTapping()
        } else {
            info("accessibility: NOT trusted — waiting for permission")
            print("""

            ─────────────────────────────────────────────────────────────
            FinderBack needs Accessibility permission and doesn't have it.

              1. Open  System Settings → Privacy & Security → Accessibility
              2. Turn ON the entry that just appeared. If you launched with
                 ./run.sh that entry is your TERMINAL app (Terminal / iTerm /
                 Ghostty…), because macOS attributes permission to whatever
                 launched the process. If you launched the .app it is
                 "FinderBack".
              3. FinderBack picks the permission up on its own — no relaunch
                 needed (except for the terminal, if you granted the terminal).
            ─────────────────────────────────────────────────────────────

            """)
            fflush(stdout)
            _ = checkAccessibility()   // prompts, and puts us in the list
            SettingsWindow.shared.show()
            startPermissionPoll()
        }
    }

    /// Called once permission is in hand, from launch or from the poll.
    private func beginTapping() {
        guard tap == nil else { return }
        guard startTap() else {
            info("!! could not create the event tap even though we are trusted")
            return
        }
        info("ready — style=\(BarStyle.current.rawValue) — right-click in Finder"
             + (verboseLogging ? "" : "  (per-event tracing off; pass --debug for it)"))
    }

    /// There is no notification for "accessibility trust changed", so this is a poll.
    /// It is cheap, and it stops for good as soon as the tap is running.
    private func startPermissionPoll() {
        permissionPoll?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            self?.permissionPoll = nil
            info("accessibility: TRUSTED (granted while running)")
            self?.beginTapping()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPoll = timer
    }

    /// Swap in a panel of the newly chosen style. Anything on screen belongs to the
    /// old style and goes with it.
    private func rebuildPanel() {
        hidePanel("style changed")
        nav = NavPanel(style: BarStyle.current)
    }

    /// An .accessory app shows no menu bar, but a main menu still supplies the key
    /// equivalents — without one, ⌘W and ⌘Q do nothing while the settings window is
    /// key.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit FinderBack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    @objc private func showSettings() { SettingsWindow.shared.show() }

    /// Double-clicking the app while it is already running (or clicking it in the
    /// Login Items list) sends this instead of launching a second copy. There are no
    /// windows to restore, so treat it as "show me the settings".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return true
    }

    /// The bar is not a document and the menu bar item is the app's real presence;
    /// closing the settings window must not quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func checkAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Tap lifecycle

    private func startTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.keyDown.rawValue)  // only ever inspected for Escape

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,             // never .defaultTap — see file header
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        info("event tap installed (listen-only, session tap, head insert)")
        return true
    }

    func reenableTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: Event handling

    func handle(type: CGEventType, event: CGEvent) {
        let front = frontmostBundleID ?? "none"
        let inFinder = (front == Config.finderBundleID)
        let visible = nav.isVisible

        switch type {
        case .rightMouseDown:
            let loc = event.location
            dbg("rightMouseDown display=(\(fmt(loc.x)),\(fmt(loc.y))) front=\(front) panelVisible=\(visible)")
            guard inFinder else {
                hidePanel("right-click outside Finder")
                dbg("  ignored — frontmost is not Finder")
                return
            }
            // Hand off and return. The accessibility lookup below takes tens of
            // milliseconds, and a tap callback that takes too long gets the tap
            // disabled by the system. Dispatching to the next run loop turn keeps the
            // callback itself trivial; the work still lands well before Finder's menu
            // finishes opening (~35ms), which is all the ordering this needs.
            DispatchQueue.main.async { [weak self] in self?.onRightClick(at: loc) }

        case .leftMouseDown:
            let loc = event.location
            let point = cocoaPoint(fromDisplayPoint: loc)
            dbg("leftMouseDown  display=(\(fmt(loc.x)),\(fmt(loc.y))) cocoa=(\(fmt(point.x)),\(fmt(point.y))) front=\(front) panelVisible=\(visible)")

            guard visible else {
                dbg("  ignored — panel not visible")
                return
            }
            let frame = nav.frame
            guard let direction = nav.direction(for: point) else {
                // Don't hide yet: the same click is dismissing Finder's menu with a
                // short fade, and hiding instantly makes the bar visibly beat the
                // menu out. Linger just long enough to leave together. The watchdog
                // is stopped so it can't jump the gun; the generation guard cancels
                // the linger if a new right-click re-anchors the bar meanwhile.
                menuWatch?.invalidate()
                menuWatch = nil
                let generation = probeGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + Config.dismissLinger) { [weak self] in
                    guard let self, generation == self.probeGeneration else { return }
                    self.hidePanel("click outside panel (after linger)")
                }
                dbg("  MISS — panel frame \(fmtRect(frame)), nothing fired; hiding in \(Int(Config.dismissLinger * 1000))ms")
                return
            }
            dbg("  HIT → \(direction == .back ? "BACK (⌘[)" : "FORWARD (⌘])") in \(fmtRect(frame))")
            hidePanel("acted on click")
            fireNavigation(back: direction == .back)

        case .keyDown:
            // Only looked at while our panel is on screen, and only ever compared
            // against Config.dismissKeys. No keystroke is read, logged, or stored.
            guard visible else { return }
            let dismisses = Config.dismissKeys.contains(event.getIntegerValueField(.keyboardEventKeycode))
            dbg("keyDown        dismisses=\(dismisses) front=\(front) panelVisible=true")
            if dismisses { hidePanel("key that dismisses the menu") }

        default:
            dbg("event type \(type.rawValue) (unhandled) front=\(front)")
        }
    }

    /// The real right-click handling, one run loop turn after the tap saw the event.
    private func onRightClick(at loc: CGPoint) {
        // A previous bar is NOT hidden here, on purpose. Right-click-while-open is
        // common (re-aiming the menu), and hiding the old bar just to re-show it
        // ~60ms later reads as a distinct blink — the worst-looking path in the app.
        // Instead the old bar stays put and is MOVED when the new menu is measured,
        // so the eye sees one bar hop, exactly like Finder's own menu does. The
        // watchdog and any in-flight probe are cancelled so they can't hide it or
        // move it to a stale position mid-flight.
        probeGeneration &+= 1
        menuWatch?.invalidate()
        menuWatch = nil

        // What did the click land on? Has to happen before Finder's menu opens and
        // covers the point. Role only — nothing about the item itself. NOTE: this
        // call is also the source of the residual delay before the bar appears. It
        // asks Finder's accessibility server, and Finder answers on its main thread —
        // which, at this exact moment, is busy tearing down the old menu and opening
        // the new one. ~10ms when Finder is idle, ~50ms when a menu was already open.
        // That cost is Finder's to pay and cannot be removed from here.
        let role = MenuProbe.role(under: loc) ?? "unknown"
        dbg("  element under cursor: role=\(role)")
        if Config.onlyOnEmptySpace, MenuProbe.itemRoles.contains(role) {
            hidePanel("superseded — new right-click landed on an item")
            dbg("  suppressed — clicked an item, not empty space")
            return
        }

        // Finder's menu does not exist yet, so there is nothing to measure. Poll for
        // it and show (or move) the bar the moment it can be measured.
        beginProbe(index: 0, generation: probeGeneration, cursor: loc)
    }

    private func hidePanel(_ reason: String) {
        probeGeneration &+= 1   // cancel any in-flight menu measurement
        menuWatch?.invalidate()
        menuWatch = nil
        nav.hide(reason: reason)
    }

    /// The bar is a separate window in a separate process from Finder's menu, so
    /// nothing makes them disappear together for free. Anything that dismisses the
    /// menu without a click — space for Quick Look, Mission Control, a hot corner,
    /// ⌘-Tab — would otherwise leave the bar stranded on screen. So while the bar is
    /// up, keep asking whether the menu is still there, and follow it down.
    private func startMenuWatch(menuFrame: CGRect) {
        menuWatch?.invalidate()
        let timer = Timer(timeInterval: Config.menuWatchInterval, repeats: true) { [weak self] _ in
            guard let self, self.nav.isVisible else { return }
            if !MenuProbe.isMenuOpen(frame: menuFrame) {
                self.hidePanel("Finder's menu closed")
            }
        }
        // .common so it keeps firing during tracking loops and Mission Control.
        RunLoop.main.add(timer, forMode: .common)
        menuWatch = timer
    }

    /// Try to measure the just-opened menu, retrying on the schedule in
    /// Config.probeDelays. Shows nothing at all if no menu ever appears.
    private func beginProbe(index: Int, generation: Int, cursor: CGPoint) {
        guard index < Config.probeDelays.count else {
            guard generation == probeGeneration else { return }
            // No menu ever appeared — e.g. the right-click just dismissed a previous
            // one. A bar with no menu under it would be an orphan, so hide anything
            // still showing from the previous menu.
            dbg("  no menu appeared — bar not shown")
            hidePanel("no menu to attach to")
            return
        }
        let previous = index > 0 ? Config.probeDelays[index - 1] : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.probeDelays[index] - previous) { [weak self] in
            guard let self, generation == self.probeGeneration else { return }  // superseded
            if let menu = MenuProbe.openMenuFrame(nearCursor: cursor) {
                self.nav.show(onMenuFrame: menu)
                self.startMenuWatch(menuFrame: menu)
            } else {
                self.beginProbe(index: index + 1, generation: generation, cursor: cursor)
            }
        }
    }

    // MARK: Firing navigation

    /// Post ⌘[ / ⌘] directly to Finder's process.
    private func fireNavigation(back: Bool) {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == Config.finderBundleID
        }) else {
            info("  !! Finder not running — nothing fired")
            return
        }
        let pid = finder.processIdentifier
        let key = back ? Config.keyLeftBracket : Config.keyRightBracket
        let name = back ? "⌘[ (Back)" : "⌘] (Forward)"

        // Deliberately deferred: at this instant Finder's context menu is still up and
        // its tracking loop would eat the keystroke. See Config.navigationDelay.
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.navigationDelay) {
            guard let src = CGEventSource(stateID: .hidSystemState) else {
                info("  !! could not create CGEventSource — nothing fired")
                return
            }
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
            else {
                info("  !! could not create key events — nothing fired")
                return
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.postToPid(pid)
            up.postToPid(pid)
            dbg("  FIRED \(name) → Finder pid \(pid) (after \(Int(Config.navigationDelay * 1000))ms)")
        }
    }
}
