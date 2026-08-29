import Foundation
import ServiceManagement

// MARK: - Preferences
//
// Stored in UserDefaults under the bundle id, so they survive a rebuild and a
// reboot. Everything reads the style through BarStyle.current, never from here
// directly, so a --style= flag can still override it for a development run.

final class Preferences {
    static let shared = Preferences()

    /// Posted when a setting changes. The Controller listens and rebuilds the bar;
    /// the settings window and the menu bar item listen and re-sync their controls.
    static let didChange = Notification.Name("com.github.adfd3ewdf3.FinderBack.prefsDidChange")

    private enum Key {
        static let style = "barStyle"
    }

    private let defaults = UserDefaults.standard
    private init() {}

    var style: BarStyle {
        get { BarStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .labels }
        set {
            guard newValue != style else { return }
            defaults.set(newValue.rawValue, forKey: Key.style)
            info("style changed to \(newValue.rawValue)")
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}

// MARK: - Launch at login
//
// SMAppService is the modern replacement for the old login-item APIs: it registers
// THIS app bundle with launchd, needs no helper target and no user trip to System
// Settings. macOS shows the result in Settings → General → Login Items, where the
// user can also turn it off behind our back — hence always reading `isEnabled` back
// from the service rather than caching a bool of our own.

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or a human-readable reason it failed.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                // .requiresApproval means the user has it switched OFF in System
                // Settings; re-registering will not override that, so say so plainly.
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    return "Turn FinderBack on in System Settings → General → Login Items."
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            info("launch at login: \(enabled ? "enabled" : "disabled")")
            return nil
        } catch {
            info("!! launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
