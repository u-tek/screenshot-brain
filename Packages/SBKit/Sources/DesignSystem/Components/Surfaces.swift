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

/// A frosted card: its own light behind glass, 28pt corners.
public struct FrostedCard<Content: View>: View {
    private let palette: LightPalette
    private let content: Content

    public init(palette: LightPalette, @ViewBuilder content: () -> Content) {
        self.palette = palette
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: SBRadius.card, style: .continuous)
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LightField(.bloom(palette), grain: 0.04)
                    Color.clear.sbGlass(in: shape)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SBColor.ink.opacity(0.8))
                .padding(.leading, 18)
                .frame(height: 30)
            Spacer(minLength: 56)
            content
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sbGlass(in: RoundedRectangle(cornerRadius: SBRadius.card - 8, style: .continuous))
                .padding(8)
        }
        .background {
            LightField(.bloom(palette).shifted(down: 0.12), grain: 0.04)
                .clipShape(shape)
        }
        .contentShape(shape)
    }
}

extension LightComposition {
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

/// A frosted tile with its category's light blooming from the top and a small label low down.
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
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(title)
                .font(SBFont.body(15, weight: .semibold))
                .foregroundStyle(SBColor.ink)
            Text(detail)
                .font(SBFont.mono(11))
                .foregroundStyle(SBColor.inkSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background {
            LightField(.bloom(palette), grain: 0.04)
                .clipShape(shape)
        }
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 0.75)
        }
    }
}
