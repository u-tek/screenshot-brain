import SwiftUI

/// The primary action on most screens: the v4 CTA (a dark capsule, a warm white circle).
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
        .buttonStyle(SBPressStyle())
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
        SBCTALabel(title, icon: SBIcon(systemName: systemImage), fillsWidth: true)
    }
}

/// The CTA's circle on its own.
public struct GlassOrb: View {
    private let palette: LightPalette
    private let systemImage: String

    public init(palette: LightPalette, systemImage: String) {
        self.palette = palette
        self.systemImage = systemImage
    }

    public var body: some View {
        // The v4 CTA's circle: warm white with the glyph in ground.
        SBIconView(SBIcon(systemName: systemImage), size: 18)
            .foregroundStyle(SBColor.ground)
            .frame(width: 36, height: 36)
            .background(Circle().fill(SBColor.accent))
            .accessibilityHidden(true)
    }
}

/// An outlined chip in mono caps, with an optional ✕.
public struct Chip: View {
    private let title: String
    private let closable: Bool

    public init(_ title: String, closable: Bool = false) {
        self.title = title
        self.closable = closable
    }

    public var body: some View {
        SBChip(title, icon: closable ? .x : nil)
    }
}

/// A 44pt round button with a thin-stroke glyph.
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
        SBCircleButton(SBIcon(systemName: systemImage), label: label, action: action)
    }
}

/// A pill that can be picked. The picked one is warm white.
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
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? SBColor.ground : SBColor.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 46)
                .background(SBPillBackground(isPrimary: isSelected))
                .contentShape(Capsule())
        }
        .buttonStyle(SBPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
