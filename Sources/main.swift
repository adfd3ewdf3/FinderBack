//
//  FinderBack — a floating ← / → pair that appears on top of Finder's context menu.
//
//  The whole app is: watch the mouse, draw a small panel, post two keystrokes.
//  No filesystem access, no Apple Events, no Finder scripting.
//
//  Top-level executable code has to live in a file called main.swift, so this file
//  is only the entry point. Everything else is one concern per file:
//
//    Config.swift          every tunable knob; the design lives here
//    Logging.swift         dbg() / info(), stdout + unified log
//    Geometry.swift        the ONE display->cocoa coordinate conversion, and log formatting
//    MenuProbe.swift       read-only AX queries: what's under the cursor, where's the menu
//    Preferences.swift     UserDefaults-backed settings, and launch-at-login
//    BarStyle.swift        the .labels / .arrows enum; the single place style is decided
//    BarView.swift         the bar's shape and decoration (shared with the settings preview)
//    NavPanel.swift        the borderless panel: placement over the menu, and hit testing
//    SettingsWindow.swift  the settings window and its live style previews
//    StatusItem.swift      the menu bar item
//    Controller.swift      the event tap, and everything that reacts to an event
//
//  Read walkthrough.md first if you are picking this up cold.
//

import AppKit
import Foundation

// MARK: - Entry point

setbuf(stdout, nil)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar (also LSUIElement)
let controller = Controller()
app.delegate = controller
app.run()
