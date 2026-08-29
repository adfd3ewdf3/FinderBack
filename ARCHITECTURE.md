# FinderBack architecture

FinderBack is a small native macOS menu-bar utility written in Swift. It has no package dependencies, Xcode project, network client, analytics, or updater.

## Security boundaries

The app requires Accessibility permission. Its permitted behavior is deliberately narrow:

- Use a listen-only `CGEventTap` to observe mouse position and a short menu-dismiss key list.
- Query Accessibility roles and geometry to distinguish Finder's empty space from files and to locate the open context menu.
- Post Finder's standard Back and Forward shortcuts, ⌘[ and ⌘].

The event tap must remain `.listenOnly`. FinderBack must not inspect filenames, paths, menu contents, or filesystem data, and must not add network requests or telemetry.

## Event flow

1. `Controller` maintains whether Finder is the foreground application.
2. A right-click is ignored unless Finder is active.
3. `MenuProbe` checks the Accessibility role under the pointer. File and folder roles suppress the navigation panel.
4. Finder creates its context menu after the mouse event, so FinderBack briefly polls for its measured Accessibility frame.
5. `NavPanel` places a non-activating panel over the menu's upper edge.
6. A click on the panel is handled through the listen-only tap because Finder's modal menu loop consumes ordinary window clicks.
7. `Controller` dismisses the panel and posts ⌘[ or ⌘] directly to Finder after a short delay.
8. A lightweight watchdog hides the panel when Finder's menu disappears.

Display coordinates use a top-left origin while AppKit uses a bottom-left origin. All conversion stays in `Geometry.swift`.

## Source layout

| File | Responsibility |
| --- | --- |
| `main.swift` | Application entry point |
| `Config.swift` | Timing, geometry, color, and role constants |
| `Logging.swift` | Standard and unified logging |
| `Geometry.swift` | Coordinate conversion and formatting |
| `MenuProbe.swift` | Read-only Accessibility role and frame queries |
| `Preferences.swift` | Saved style and launch-at-login state |
| `BarStyle.swift` | Label and arrow style selection |
| `BarView.swift` | Navigation bar drawing and layout |
| `NavPanel.swift` | Panel placement and hit testing |
| `SettingsWindow.swift` | Settings interface and previews |
| `StatusItem.swift` | Menu-bar controls |
| `Controller.swift` | Event tap and application behavior |

## Application lifecycle

FinderBack is an `LSUIElement` application: it has no Dock icon and lives in the menu bar. If Accessibility permission is missing, it opens Settings and polls until permission is granted. Closing Settings does not quit the application.

`SMAppService.mainApp` manages Open at Login. The application should be moved to `/Applications` before enabling it.

## Rendering

`BarView` owns the visual design so the live navigation panel and Settings previews use the same implementation. `NavPanel` owns only placement and hit testing.

The panel is non-activating and sits above Finder's context menu. Its lower strip overlaps the menu to hide the original upper border; that overlap is excluded from hit testing so Finder's first menu item remains usable.

## Building

`build.sh` compiles `Sources/*.swift`, assembles the `.app` bundle, copies `Info.plist` and the icon, then applies an ad-hoc signature. There are no external dependencies.

Ad-hoc signatures are not Developer ID signatures. Downloaded builds display Apple's unidentified-developer warning, and rebuilding or updating can require Accessibility permission to be granted again.

## Current limitations

- Tested only on Apple Silicon and macOS 26.
- Multi-monitor behavior is not yet verified.
- The navigation bar is deliberately dark in both appearances.
- Fixed row geometry does not scale with macOS large-text settings.
