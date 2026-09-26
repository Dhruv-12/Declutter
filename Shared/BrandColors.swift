import SwiftUI
import UIKit

// Brand colours shared by the app and the Home Screen widget. The app's Theme uses these,
// so each colour is defined once. Light and dark versions follow the system appearance.

nonisolated enum BrandColors {
    /// Mist: the background of every screen.
    static let mist = Color(light: 0xF3F6F5, dark: 0x0B1412)
    /// Pine as text and icons. In dark mode a pale mist-green so it stays readable.
    static let pine = Color(light: 0x12332E, dark: 0xE2ECE8)
    /// Pine as a fill: main buttons, checkmarks, badges. In dark mode a deeper, brighter green.
    static let pineFill = Color(light: 0x12332E, dark: 0x2E6B5F)
    /// Mint: space freed and success only.
    static let mint = Color(light: 0x3CCB94, dark: 0x4ED6A2)
    /// Stone: cards and surfaces.
    static let stone = Color(light: 0xDDE4E1, dark: 0x16221F)
    /// A faint edge on cards, only in dark mode, so surfaces don't melt into the background.
    static let cardBorder = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0, darkAlpha: 0.07)
    static let secondaryText = Color(light: 0x12332E, dark: 0xE2ECE8, lightAlpha: 0.62, darkAlpha: 0.6)
    /// Storage bar: used space and the empty track.
    static let barUsed = Color(light: 0x12332E, dark: 0x5E8F83)
    static let barTrack = Color(light: 0xDDE4E1, dark: 0x16221F)
}

// MARK: - Colour helpers

extension Color {
    nonisolated init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha))
    }
}

extension UIColor {
    nonisolated convenience init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        }
    }

    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
