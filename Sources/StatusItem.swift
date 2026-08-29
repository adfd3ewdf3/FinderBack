import AppKit

// MARK: - Menu bar item
//
// The app is LSUIElement: no Dock icon, no menu bar of its own. This is the handle
// the user has on it — a way back to the settings, and a way to quit that isn't
// Activity Monitor.

final class StatusItem {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init() {
        item.button?.image = NSImage(systemSymbolName: "arrow.left.arrow.right",
                                     accessibilityDescription: "FinderBack")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        item.button?.image?.isTemplate = true   // follows the menu bar's light/dark
        item.menu = buildMenu()
        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) {
            [weak self] _ in self?.item.menu = self?.buildMenu()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "FinderBack Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self

        menu.addItem(.separator())
        let styleHeader = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleHeader.isEnabled = false
        menu.addItem(styleHeader)
        for style in BarStyle.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let entry = NSMenuItem(title: "  " + style.displayName, action: #selector(pickStyle(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = style.rawValue
            entry.state = (BarStyle.current == style) ? .on : .off
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FinderBack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openSettings() { SettingsWindow.shared.show() }

    @objc private func pickStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = BarStyle(rawValue: raw) else { return }
        if BarStyle.commandLineOverride != nil {
            info("style pick ignored — --style= on the command line wins for this run")
        }
        Preferences.shared.style = style
    }

    @objc private func toggleLogin() {
        LoginItem.set(!LoginItem.isEnabled)
        item.menu = buildMenu()
    }
}
