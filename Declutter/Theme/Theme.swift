import CoreText
import SwiftUI
import UIKit

// MARK: - Brand: "Breathing room"
//
// Calm, airy, trustworthy. Every colour, font, spacing, button, haptic and animation
// the app uses is defined here, so the whole app changes together.

nonisolated enum Theme {
    // MARK: Colours (light / dark)

    // Dark mode is designed, not inverted: a deep forest background, slightly raised Stone
    // surfaces with a faint edge, pale mist-green text, and a deeper Pine green for buttons.

    /// Mist: the background of every screen.
    static let mist = BrandColors.mist
    /// Pine as text and icons. In dark mode a pale mist-green so it stays readable.
    static let pine = BrandColors.pine
    /// Pine as a fill: main buttons, checkmarks, badges. In dark mode a deeper, brighter green,
    /// so buttons read as Pine instead of turning into pale slabs.
    static let pineFill = BrandColors.pineFill
    /// Text and icons placed on a Pine fill.
    static let onPine = Color(light: 0xF3F6F5, dark: 0xF3F6F5)
    /// Mint: space freed and success only. Use for fills and large numbers.
    static let mint = BrandColors.mint
    /// Icons and text on a Mint fill.
    static let onMint = Color(light: 0x12332E, dark: 0x12332E)
    /// Mint dark enough to read as small text on Mist.
    static let mintText = Color(light: 0x177552, dark: 0x5FE0AE)
    /// Stone: cards and surfaces.
    static let stone = BrandColors.stone
    /// A faint edge on cards, only in dark mode, so surfaces don't melt into the background.
    static let cardBorder = BrandColors.cardBorder
    /// Coral: delete and destructive actions only.
    static let coral = Color(light: 0xFF6B5A, dark: 0xFF7A6A)
    /// Coral dark enough to read as small text on Mist or Stone.
    static let coralText = Color(light: 0xC23B2B, dark: 0xFF8C7F)
    /// Text on a Coral fill. Pine stays dark in both modes so it is readable on Coral.
    static let onCoral = Color(light: 0x12332E, dark: 0x12332E)

    static let secondaryText = BrandColors.secondaryText
    static let hairline = Color(light: 0x12332E, dark: 0xE2ECE8, lightAlpha: 0.10, darkAlpha: 0.08)

    // Storage bar: used space, space you can free, and the empty track.
    static let barUsed = BrandColors.barUsed
    static let barCleanable = Color(light: 0x7D9A93, dark: 0x2F4A44)
    static let barTrack = BrandColors.barTrack

    // Soft category colours for icons on the home screen. Chosen to stay clear of Mint
    // (success) and Coral (delete), so those keep their meaning.
    static let lake = Color(light: 0x3A74D8, dark: 0x7FA9F2)
    static let amber = Color(light: 0xC47F06, dark: 0xF0B44A)
    static let plum = Color(light: 0x9150BA, dark: 0xC592E8)
    static let teal = Color(light: 0x13869A, dark: 0x5CC6D8)
    static let iris = Color(light: 0x5A5FD6, dark: 0x9EA2F5)
    static let slate = Color(light: 0x56708F, dark: 0x9DB3CE)

    static let mistUI = UIColor(light: 0xF3F6F5, dark: 0x0B1412)
    static let pineUI = UIColor(light: 0x12332E, dark: 0xE2ECE8)

    /// Exact brand colours that never change with dark mode, for the launch screen and intro.
    enum Brand {
        static let pine = Color(uiColor: UIColor(hex: 0x12332E))
        static let mist = Color(uiColor: UIColor(hex: 0xF3F6F5))
        static let mint = Color(uiColor: UIColor(hex: 0x3CCB94))
    }

    // MARK: Layout

    /// Side margin of every screen.
    static let page: CGFloat = 20
    /// Space between blocks.
    static let spacing: CGFloat = 16
    /// Space inside a block.
    static let gap: CGFloat = 8
    /// Cards, buttons, sheets.
    static let radius: CGFloat = 20
    /// Icon tiles and small surfaces.
    static let smallRadius: CGFloat = 12
    /// Photo thumbnails.
    static let thumbRadius: CGFloat = 10
    /// Gap between photos in a grid.
    static let gridGap: CGFloat = 3
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
    static let heroNumber = Font.system(size: 60, weight: .bold, design: .rounded)
    static let bigNumber = Font.system(size: 34, weight: .bold, design: .rounded)

    /// Button labels.
    static let button = Font.system(.headline, design: .rounded, weight: .semibold)
}

// MARK: - Buttons

/// Full-width buttons: Pine for main actions, Coral for deleting, Stone for secondary actions,
/// Mist for secondary actions that sit on a Stone card.
struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, destructive, secondary, secondaryDestructive, onCard }

    var kind: Kind = .primary
    var fullWidth = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.button)
            // One line normally. With the largest text sizes a label wraps instead of being cut off.
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
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
        case .secondary, .onCard: Theme.pine
        case .secondaryDestructive: Theme.coralText
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.pineFill
        case .destructive: Theme.coral
        case .secondary, .secondaryDestructive: Theme.stone
        case .onCard: Theme.mist
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

// MARK: - Layout helpers

/// Side by side normally; stacked with the largest text sizes, so text gets the full width
/// instead of wrapping in the middle of words and numbers.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout(content)
    }
}

// MARK: - Surfaces

extension View {
    /// A Stone surface with the standard corner radius (and a faint edge in dark mode).
    func surface(radius: CGFloat = Theme.radius) -> some View {
        self
            .background(Theme.stone, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.cardBorder, lineWidth: 1)
            }
    }

    /// A Stone card with the standard padding and corner radius.
    func card(padding: CGFloat = Theme.spacing) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
    }

    /// A category's colour icon in a soft tinted circle.
    func tintedCircle(_ tint: Color, size: CGFloat = 44) -> some View {
        modifier(TintedCircle(tint: tint, size: size))
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

private struct TintedCircle: ViewModifier {
    let tint: Color
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(colorScheme == .dark ? 0.2 : 0.13), in: .circle)
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
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)

    /// Wakes the Taptic Engine so the intro's tap fires without delay.
    static func prepareLight() {
        lightGenerator.prepare()
    }

    /// A soft tap, used when the intro's letters settle.
    static func light() {
        lightGenerator.impactOccurred()
    }

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

// MARK: - Warm-up

nonisolated enum FontWarmer {
    /// Loads SF Pro Rounded and lays out the intro word once, in the background, so the
    /// intro's first frame doesn't pay for loading the font.
    static func warm() {
        let base = UIFont.systemFont(ofSize: 58, weight: .bold)
        let rounded = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 58) } ?? base
        for font in [rounded, UIFont.preferredFont(forTextStyle: .body)] {
            let text = NSAttributedString(string: "Declutter 0123456789 GB", attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(text)
            _ = CTLineGetTypographicBounds(line, nil, nil, nil)
        }
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
