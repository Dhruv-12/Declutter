import SwiftUI
import UIKit

// MARK: - Brand: "Breathing room"
//
// Calm, airy, trustworthy. Every colour, font, spacing, button, haptic and animation
// the app uses is defined here, so the whole app changes together.

nonisolated enum Theme {
    // MARK: Colours (light / dark)

    /// Mist: the background of every screen.
    static let mist = Color(light: 0xF3F6F5, dark: 0x0D1614)
    /// Pine: text and main buttons. In dark mode it becomes a pale mist-green so text stays readable.
    static let pine = Color(light: 0x12332E, dark: 0xE2ECE8)
    /// Text and icons placed on a Pine fill.
    static let onPine = Color(light: 0xF3F6F5, dark: 0x0D1614)
    /// Mint: space freed and success only. Use for fills and large numbers.
    static let mint = Color(light: 0x3CCB94, dark: 0x4ED6A2)
    /// Mint dark enough to read as small text on Mist.
    static let mintText = Color(light: 0x177552, dark: 0x5FE0AE)
    /// Stone: cards and surfaces.
    static let stone = Color(light: 0xDDE4E1, dark: 0x1B2724)
    /// Coral: delete and destructive actions only.
    static let coral = Color(light: 0xFF6B5A, dark: 0xFF7A6A)
    /// Coral dark enough to read as small text on Mist or Stone.
    static let coralText = Color(light: 0xC23B2B, dark: 0xFF8C7F)
    /// Text on a Coral fill. Pine stays dark in both modes so it is readable on Coral.
    static let onCoral = Color(light: 0x12332E, dark: 0x12332E)

    static let secondaryText = Color(light: 0x12332E, dark: 0xE2ECE8, alpha: 0.62)
    static let hairline = Color(light: 0x12332E, dark: 0xE2ECE8, alpha: 0.10)

    static let mistUI = UIColor(light: 0xF3F6F5, dark: 0x0D1614)
    static let pineUI = UIColor(light: 0x12332E, dark: 0xE2ECE8)

    // MARK: Layout

    /// Side margin of every screen.
    static let page: CGFloat = 20
    /// Space between blocks.
    static let spacing: CGFloat = 16
    /// Space inside a block.
    static let gap: CGFloat = 8
    /// Cards, buttons, sheets.
    static let radius: CGFloat = 20
    /// Thumbnails and icon tiles.
    static let smallRadius: CGFloat = 12
}

// MARK: - Type
//
// SF Pro Rounded for headings and big numbers, SF Pro for everything else.

extension Font {
    /// Screen and section headings.
    static func heading(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .rounded, weight: .bold)
    }

    /// Big numbers like "3.2 GB".
    static let heroNumber = Font.system(size: 52, weight: .bold, design: .rounded)
    static let bigNumber = Font.system(size: 34, weight: .bold, design: .rounded)

    /// Button labels.
    static let button = Font.system(.headline, design: .rounded, weight: .semibold)
}

// MARK: - Colour helpers

extension Color {
    nonisolated init(light: UInt32, dark: UInt32, alpha: CGFloat = 1) {
        self.init(uiColor: UIColor(light: light, dark: dark, alpha: alpha))
    }
}

extension UIColor {
    nonisolated convenience init(light: UInt32, dark: UInt32, alpha: CGFloat = 1) {
        self.init { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
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

// MARK: - Buttons

/// Full-width buttons: Pine for main actions, Coral for deleting, Stone for secondary actions.
struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, destructive, secondary, secondaryDestructive }

    var kind: Kind = .primary
    var fullWidth = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.button)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background, in: .rect(cornerRadius: Theme.radius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.onPine
        case .destructive: Theme.onCoral
        case .secondary: Theme.pine
        case .secondaryDestructive: Theme.coralText
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.pine
        case .destructive: Theme.coral
        case .secondary, .secondaryDestructive: Theme.stone
        }
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var primary: BrandButtonStyle { BrandButtonStyle(kind: .primary) }
    static var destructive: BrandButtonStyle { BrandButtonStyle(kind: .destructive) }
    static var secondary: BrandButtonStyle { BrandButtonStyle(kind: .secondary) }
    static var secondaryDestructive: BrandButtonStyle { BrandButtonStyle(kind: .secondaryDestructive) }
    /// Small, content-sized version for buttons inside cards and banners.
    static func compact(_ kind: BrandButtonStyle.Kind) -> BrandButtonStyle {
        BrandButtonStyle(kind: kind, fullWidth: false)
    }
}

// MARK: - Surfaces

extension View {
    /// A Stone card with the standard padding and corner radius.
    func card(padding: CGFloat = Theme.spacing) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.stone, in: .rect(cornerRadius: Theme.radius))
    }

    /// Mist background for a whole screen.
    func screenBackground() -> some View {
        background(Theme.mist.ignoresSafeArea())
    }

    /// Styles a `List` to match the brand: Mist background, Stone rows, sentence-case headers.
    func brandList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.mist.ignoresSafeArea())
            .textCase(nil)
    }

    /// Animation for things that change because the user tapped. Nothing moves when Reduce Motion is on.
    func tapAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(TapAnimation(value: value))
    }
}

private struct TapAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .snappy(duration: 0.2), value: value)
    }
}

// MARK: - Haptics

enum Haptics {
    /// Selecting or deselecting an item.
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Confirming a destructive action, just before it runs.
    static func confirm() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Delete or merge finished.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Navigation bar

enum BrandAppearance {
    /// Rounded Pine titles on Mist, for every navigation bar in the app.
    static func apply() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Theme.mistUI
        appearance.shadowColor = .clear
        appearance.largeTitleTextAttributes = [.font: rounded(34, .bold), .foregroundColor: Theme.pineUI]
        appearance.titleTextAttributes = [.font: rounded(17, .semibold), .foregroundColor: Theme.pineUI]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = Theme.pineUI
    }
}
