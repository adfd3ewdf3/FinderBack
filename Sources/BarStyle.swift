import CoreGraphics
import Foundation

// MARK: - Style

enum NavDirection { case back, forward }

/// The two looks. Everything that differs between them is behind this enum, so
/// adding a third is a case here plus a branch in BarView — nothing else changes.
enum BarStyle: String, CaseIterable {
    /// One row: ←  |  →
    case arrows
    /// Two stacked rows: "Back" over "Forward", the way Chrome's context menu does it.
    case labels

    /// Shown in the settings window.
    var displayName: String {
        switch self {
        case .arrows: return "Arrows"
        case .labels: return "Labels"
        }
    }

    var summary: String {
        switch self {
        case .arrows: return "One compact row of arrows."
        case .labels: return "Two rows, like a menu item."
        }
    }

    /// A `--style=` flag, for development. When present it wins over the stored
    /// preference for this run only and is never written back to it.
    static let commandLineOverride: BarStyle? = {
        let flag = "--style="
        for arg in CommandLine.arguments where arg.hasPrefix(flag) {
            if let parsed = BarStyle(rawValue: String(arg.dropFirst(flag.count))) { return parsed }
        }
        return nil
    }()

    /// The single place the style is decided; every read goes through here.
    static var current: BarStyle {
        commandLineOverride ?? Preferences.shared.style
    }

    /// The bar's height. Its width always comes from the measured menu.
    var height: CGFloat {
        switch self {
        case .arrows: return Config.barHeight + Config.arrowsTopPadding
        case .labels: return Config.rowHeight * 2 + Config.rowsTopPadding + Config.rowsBottomPadding
        }
    }
}
