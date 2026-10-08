import SwiftUI

extension LightComposition {
    /// Light blooming down from the top edge of a surface and fading into the mist.
    public static func bloom(_ palette: LightPalette) -> LightComposition {
        LightComposition(forms: [
            LightForm(
                points: [LightPoint(-0.20, -0.35), LightPoint(0.50, -0.45), LightPoint(1.20, -0.35),
                         LightPoint(1.15, 0.30), LightPoint(0.60, 0.48), LightPoint(-0.15, 0.36)],
                axisStart: LightPoint(0.1, -0.2),
                axisEnd: LightPoint(0.9, 0.45),
                palette: palette,
                blur: 0.12,
                stretch: 1.3,
                angle: 0
            ),
        ])
    }
}

/// A tile: a neutral surface with its own light glowing in one corner, 28pt corners.
public struct FrostedCard<Content: View>: View {
    private let palette: LightPalette
    private let content: Content

    public init(palette: LightPalette, @ViewBuilder content: () -> Content) {
        self.palette = palette
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous)
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    SBColor.surface
                    SBLight(Color(palette.color(at: 1)), width: 220, height: 170, opacity: 0.5)
                        .offset(x: 80, y: 80)
                }
                .clipShape(shape)
            }
    }
}

/// A card with a tab on its top edge, like a folder.
public struct FolderTabShape: InsettableShape {
    public var tabWidth: CGFloat
    public var tabHeight: CGFloat
    public var radius: CGFloat
    private var inset: CGFloat = 0

    public init(tabWidth: CGFloat = 132, tabHeight: CGFloat = 30, radius: CGFloat = SBRadius.card) {
        self.tabWidth = tabWidth
        self.tabHeight = tabHeight
        self.radius = radius
    }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let body = r.minY + tabHeight
        let tabRadius = min(radius * 0.6, tabHeight)
        let slope = tabHeight * 1.4
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.maxY - radius))
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tabRadius, y: r.minY), radius: tabRadius)
        path.addLine(to: CGPoint(x: r.minX + tabWidth, y: r.minY))
        // A smooth S-curve down from the tab to the body.
        path.addCurve(
            to: CGPoint(x: r.minX + tabWidth + slope, y: body),
            control1: CGPoint(x: r.minX + tabWidth + slope * 0.5, y: r.minY),
            control2: CGPoint(x: r.minX + tabWidth + slope * 0.5, y: body)
        )
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: body), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: radius)
        path.closeSubpath()
        return path
    }

    public func inset(by amount: CGFloat) -> FolderTabShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// The item card: the item's light in the upper part, a frosted panel below with title and
/// meta, and the category on the tab. Used for triage and the widget.
public struct FolderTabCard<Content: View>: View {
    private let tab: String
    private let palette: LightPalette
    private let content: Content

    public init(tab: String, palette: LightPalette, @ViewBuilder content: () -> Content) {
        self.tab = tab
        self.palette = palette
        self.content = content()
    }

    public var body: some View {
        let shape = FolderTabShape()
        VStack(alignment: .leading, spacing: 0) {
            Text(tab)
                .sbText(.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.leading, 18)
                .frame(height: 30)
            Spacer(minLength: 56)
            content
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SBRadius.tile - 8, style: .continuous).fill(SBColor.surface))
                .padding(8)
        }
        .background {
            ZStack {
                SBColor.surface2
                LightField(.bloom(palette).shifted(down: 0.12), ground: false, grain: 0.04)
            }
            .clipShape(shape)
        }
        .contentShape(shape)
    }
}

extension LightComposition {
    /// The same light, flipped left to right.
    public func mirrored() -> LightComposition {
        LightComposition(forms: forms.map { form in
            var form = form
            form.points = form.points.map { LightPoint(1 - $0.x, $0.y) }
            form.axisStart.x = 1 - form.axisStart.x
            form.axisEnd.x = 1 - form.axisEnd.x
            form.angle = .pi - form.angle
            return form
        })
    }

    /// The same light, moved down by a fraction of the surface's height.
    public func shifted(down amount: Double) -> LightComposition {
        LightComposition(forms: forms.map { form in
            var form = form
            form.points = form.points.map { LightPoint($0.x, $0.y + amount) }
            form.axisStart.y += amount
            form.axisEnd.y += amount
            return form
        })
    }
}

/// A tile with its category's light blooming down from the top edge and the name low down.
public struct LightTile: View {
    private let title: String
    private let detail: String
    private let palette: LightPalette

    public init(_ title: String, detail: String, palette: LightPalette) {
        self.title = title
        self.detail = detail
        self.palette = palette
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous)
        let core = Color(palette.color(at: 1)), deep = Color(palette.color(at: 0))
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text(title)
                .sbText(.title)
            Text(detail)
                .sbText(.labelDim)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background {
            ZStack {
                SBColor.surface
                GeometryReader { proxy in
                    Ellipse()
                        .fill(RadialGradient(stops: [
                            .init(color: core, location: 0),
                            .init(color: core, location: 0.4),
                            .init(color: deep, location: 0.75),
                            .init(color: deep.opacity(0), location: 1),
                        ], center: .center, startRadius: 0, endRadius: proxy.size.width * 1.1))
                        .frame(width: proxy.size.width * 2.2, height: 200)
                        .position(x: proxy.size.width / 2, y: 0)
                        .blur(radius: 36)
                }
            }
            .clipShape(shape)
        }
        .overlay {
            shape.strokeBorder(core.opacity(0.35), lineWidth: 1)
        }
    }
}
