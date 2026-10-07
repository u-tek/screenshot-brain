import SwiftUI
import UIKit

/// Colour tokens. Light-first; every token has a night variant.
public enum SBColor {
    public static let mistTop = Color(light: 0xF2F2F5, dark: 0x0B0B0D)
    public static let mistBottom = Color(light: 0xECEBF3, dark: 0x0E0D12)
    /// Bold phrases and primary text.
    public static let ink = Color(light: 0x16161A, dark: 0xF3F3F6)
    /// The airy words of a headline. Large sizes only.
    public static let inkLight = Color(light: 0x5E5E68, dark: 0xA7A7B2)
    /// Small labels. Passes 4.5:1 on the mist.
    public static let inkSecondary = Color(light: 0x6B6B76, dark: 0x9A9AA6)
    /// The only accent: done, progress, and the one active state per screen.
    public static let accent = Color(.sRGB, red: 1, green: 106 / 255, blue: 61 / 255, opacity: 1)
    public static let hairline = Color(light: 0x16161A, dark: 0xFFFFFF).opacity(0.14)
}

/// Type tokens. System fonts only: SF Pro Display at large sizes, SF Pro Text below, SF Mono for data rows.
public enum SBFont {
    public static func headline(_ size: CGFloat, bold: Bool) -> Font {
        .system(size: size, weight: bold ? .semibold : .light)
    }

    public static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    public static let label = Font.system(size: 13, weight: .regular)

    /// Huge Reveal numbers.
    public static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .ultraLight)
    }

    public static func mono(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

public enum SBRadius {
    public static let actionBar: CGFloat = 32
    public static let card: CGFloat = 28
    public static let iconButton: CGFloat = 44
}

extension Color {
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
