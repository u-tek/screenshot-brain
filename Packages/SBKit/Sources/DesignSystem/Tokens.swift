import Core
import SwiftUI
import UIKit

/// Colour tokens. The app is dark-only: one warm near-black ground, warm ink, and one warm ramp.
/// Every colour is a neutral or a step on the ramp; warm white (`accent`) is the only white.
public enum SBColor {
    // Ground and surfaces
    public static let ground = Color(hex: 0x0B0A09)
    /// Tiles and panels.
    public static let surface = Color(hex: 0x161412)
    /// Circle buttons and dark controls.
    public static let surface2 = Color(hex: 0x211E1B)
    public static let line = warm(0.12)
    // Ink
    public static let ink = Color(hex: 0xF6F1EA)
    public static let ink2 = Color(hex: 0xA39B92)
    /// Non-essential text only.
    public static let ink3 = Color(hex: 0x69635D)
    /// Done, progress, the live point, the selected chip, the primary pill and the CTA circle.
    public static let accent = Color(hex: 0xF6ECE2)
    /// Text and controls sitting on the light ramp card.
    public static let inkOnLight = Color(hex: 0x1D0E08)
    public static let inkOnLight2 = Color(hex: 0x1D0E08, opacity: 0.7)
    /// Every translucent white is warm: rgba(255, 240, 225, a).
    public static func warm(_ alpha: Double) -> Color {
        Color(.sRGB, red: 1, green: 240 / 255, blue: 225 / 255, opacity: alpha)
    }
    /// Ground-coloured scrims.
    public static func shade(_ alpha: Double) -> Color {
        Color(hex: 0x0B0A09, opacity: alpha)
    }
    public static let ctaFill = Color(hex: 0x161412, opacity: 0.72)
    public static let tabBarFill = Color(hex: 0x211E1B, opacity: 0.72)
    /// Chips and buttons sitting on imagery.
    public static let chipOnImage = Color(hex: 0x1D0E08, opacity: 0.72)

    // Older names, kept so every screen inherits the new look.
    public static let mistTop = ground
    public static let mistBottom = ground
    public static let inkLight = ink2
    public static let inkSecondary = ink2
    public static let hairline = line
}

/// One warm ramp, deep ember to bone.
public enum SBRamp {
    public static let r0 = Color(hex: 0x1D0E08)
    public static let r1 = Color(hex: 0x4A1C0C)
    public static let r2 = Color(hex: 0x8E3415)
    public static let r3 = Color(hex: 0xE2582B)
    public static let r4 = Color(hex: 0xFF8A57)
    public static let r5 = Color(hex: 0xFFB381)
    public static let r6 = Color(hex: 0xF2D4B6)
    public static let r7 = Color(hex: 0xF6ECE2)
    /// The light card behind the setup scan and the recap time.
    public static let card = Color(hex: 0xFAA67B)
    public static let rgb: [RGB] = [0x1D0E08, 0x4A1C0C, 0x8E3415, 0xE2582B, 0xFF8A57, 0xFFB381, 0xF2D4B6, 0xF6ECE2].map(RGB.init(hex:))
}

/// The five kinds of thing, each a step on the ramp: a lit core and a deep edge.
public enum SBKind: String, CaseIterable, Sendable {
    case events, places, products, recipes, reference

    public init(_ category: ItemCategory) {
        switch category {
        case .event: self = .events
        case .place: self = .places
        case .product: self = .products
        case .recipe: self = .recipes
        case .reference, .other: self = .reference
        }
    }

    public var coreHex: UInt32 {
        switch self {
        case .events: 0xEC5F2E
        case .places: 0xFF8A57
        case .products: 0xFFB381
        case .recipes: 0xE8C49E
        case .reference: 0xD9C7B4
        }
    }

    public var deepHex: UInt32 {
        switch self {
        case .events: 0x5A1707
        case .places: 0x7C2C10
        case .products: 0x7F4520
        case .recipes: 0x5F442C
        case .reference: 0x4A3B30
        }
    }

    public var core: Color { Color(hex: coreHex) }
    public var deep: Color { Color(hex: deepHex) }
}

/// Type tokens. System fonts only: SF Pro Display at large sizes, SF Pro Text below, SF Mono for
/// data rows. Everything below headline size is a Dynamic Type text style whose default size
/// matches the brief (13pt labels, 15pt body), so it scales with the user's text size.
public enum SBFont {
    public static func headline(_ size: CGFloat, bold: Bool) -> Font {
        .system(size: size, weight: bold ? .semibold : .light)
    }

    public static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size), design: .default, weight: weight)
    }

    public static let label = Font.system(.footnote, design: .default, weight: .regular)

    /// Huge Reveal numbers. Fixed size: they're already as large as the screen allows.
    public static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light)
    }

    public static func mono(_ size: CGFloat = 12) -> Font {
        .system(textStyle(for: size), design: .monospaced, weight: .medium)
    }

    /// The Dynamic Type style whose default size is closest to `size`.
    public static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<14: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<18.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }
}

public enum SBRadius {
    public static let tile: CGFloat = 28
    /// Cards that are objects: the recap card, the score card, the light card.
    public static let objectCard: CGFloat = 34
    public static let cta: CGFloat = 26
    public static let scenario: CGFloat = 18
    public static let shot: CGFloat = 24
    public static let cell: CGFloat = 16
    // Older names.
    public static let card: CGFloat = tile
    public static let actionBar: CGFloat = cta
    public static let iconButton: CGFloat = 44
}

public enum SBSpace {
    public static let gutter: CGFloat = 16
    public static let gap: CGFloat = 8
    /// The header row's top, below the safe area.
    public static let headerTop: CGFloat = 3
    /// The tab bar, the decision row and the CTA sit this far from the bottom of the screen.
    public static let bottomBar: CGFloat = 24
    public static let tabBarHeight: CGFloat = 64
}

extension Color {
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(_ rgb: RGB, opacity: Double = 1) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
