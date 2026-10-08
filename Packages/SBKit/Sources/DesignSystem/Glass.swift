import SwiftUI

public enum GlassStyle: Sendable {
    /// Frosted: the light behind shows through softened.
    case regular
    /// Nearly clear: the light behind shows through, bent at the edges.
    case clear
}

extension View {
    /// Warm translucent glass behind this view, in `shape`: a frosted material, a faint warm fill,
    /// a warm hairline and a highlight along the top. The same on every iOS version.
    public func sbGlass<S: InsettableShape>(in shape: S, style: GlassStyle = .regular, tint: Color? = nil) -> some View {
        modifier(GlassModifier(shape: shape, style: style, tint: tint))
    }
}

struct GlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let style: GlassStyle
    let tint: Color?

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if style == .regular {
                    shape.fill(.ultraThinMaterial)
                }
                shape.fill(SBColor.warm(style == .clear ? 0.04 : 0.06))
                if let tint {
                    shape.fill(tint.opacity(0.2))
                }
                shape.strokeBorder(SBColor.warm(0.14), lineWidth: 1)
                shape.strokeBorder(
                    LinearGradient(colors: [SBColor.warm(0.12), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.15)),
                    lineWidth: 1
                )
            }
        }
    }
}
