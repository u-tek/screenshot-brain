import SwiftUI

/// The primary action on most screens: a label on the left, a glowing glass orb on the right.
public struct ActionBar: View {
    private let title: String
    private let systemImage: String
    private let palette: LightPalette
    private let action: () -> Void

    public init(_ title: String, systemImage: String = "arrow.right", palette: LightPalette, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.palette = palette
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ActionBarLabel(title, systemImage: systemImage, palette: palette)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

/// The action bar's look, for wrapping in other controls (a `ShareLink`, a purchase button).
public struct ActionBarLabel: View {
    private let title: String
    private let systemImage: String
    private let palette: LightPalette

    public init(_ title: String, systemImage: String = "arrow.right", palette: LightPalette) {
        self.title = title
        self.systemImage = systemImage
        self.palette = palette
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SBFont.body(16))
                .foregroundStyle(SBColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 12)
            GlassOrb(palette: palette, systemImage: systemImage)
        }
        .padding(.leading, 26)
        .padding(.trailing, 8)
        .frame(height: 72)
        .contentShape(Rectangle())
        .sbGlass(in: RoundedRectangle(cornerRadius: SBRadius.actionBar, style: .continuous))
    }
}

/// A capsule of glass with the current light glowing through it, and a small mark.
public struct GlassOrb: View {
    private let palette: LightPalette
    private let systemImage: String

    public init(palette: LightPalette, systemImage: String) {
        self.palette = palette
        self.systemImage = systemImage
    }

    public var body: some View {
        ZStack {
            // The light sits behind the glass...
            LightField(.glow(palette), ground: false, grain: 0)
                .clipShape(Capsule())
            // ...the glass frosts it...
            Color.clear
                .sbGlass(in: Capsule(), style: .regular)
            // ...and the mark sits on top.
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(SBColor.ink)
        }
        .frame(width: 104, height: 56)
        .background {
            // A soft glow of the same light spills onto the bar.
            LightField(.glow(palette), ground: false, grain: 0)
                .clipShape(Capsule())
                .blur(radius: 14)
                .opacity(0.45)
        }
        .accessibilityHidden(true)
    }
}

/// A frosted pill with small text and an optional ✕.
public struct Chip: View {
    private let title: String
    private let closable: Bool

    public init(_ title: String, closable: Bool = false) {
        self.title = title
        self.closable = closable
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(SBFont.body(12))
                .lineLimit(1)
            if closable {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(SBColor.ink.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .sbGlass(in: Capsule())
    }
}

/// A 44pt frosted circle with a thin-stroke glyph.
public struct GlassIconButton: View {
    private let systemImage: String
    private let label: String
    private let action: () -> Void

    public init(_ systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(SBColor.ink)
                .frame(width: SBRadius.iconButton, height: SBRadius.iconButton)
        }
        .buttonStyle(.plain)
        .sbGlass(in: Circle())
        .accessibilityLabel(Text(label))
    }
}

/// A frosted chip that can be picked. The picked one carries the screen's single active state.
public struct ChoiceChip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    Circle().fill(SBColor.accent).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(SBFont.body(15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(SBColor.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .sbGlass(in: Capsule())
            .overlay(Capsule().strokeBorder(SBColor.accent.opacity(isSelected ? 0.6 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
