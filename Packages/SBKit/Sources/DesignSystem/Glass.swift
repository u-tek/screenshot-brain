import SwiftUI

public enum GlassStyle: Sendable {
    /// Frosted: the light behind shows through softened.
    case regular
    /// Nearly clear: the light behind shows through, bent at the edges.
    case clear
}

extension View {
    /// Translucent glass behind this view, in `shape`. Liquid Glass on iOS 26; a frosted material
    /// with an inner stroke and a soft ambient shadow before that.
    public func sbGlass<S: InsettableShape>(in shape: S, style: GlassStyle = .regular, tint: Color? = nil) -> some View {
        modifier(GlassModifier(shape: shape, style: style, tint: tint))
    }
}

struct GlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let style: GlassStyle
    let tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background { fallback }
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        let base: Glass = style == .clear ? .clear : .regular
        if let tint {
            return base.tint(tint)
        }
        return base
    }

    private var fallback: some View {
        let dark = colorScheme == .dark
        return ZStack {
            shape.fill(style == .clear ? AnyShapeStyle(Material.ultraThinMaterial.opacity(0.6)) : AnyShapeStyle(Material.ultraThinMaterial))
            shape.fill(dark ? Color.black.opacity(style == .clear ? 0.2 : 0.45) : Color.white.opacity(style == .clear ? 0.12 : 0.55))
            if let tint {
                shape.fill(tint.opacity(0.2))
            }
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(dark ? 0.35 : 0.8), .white.opacity(dark ? 0.06 : 0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
        .shadow(color: .black.opacity(0.06), radius: 20)
    }
}
