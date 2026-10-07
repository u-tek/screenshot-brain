import SwiftUI

/// A point in a view's unit space: x and y run 0...1 across its width and height.
public struct LightPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// One form of light: a closed shape, filled with one gradient, then blurred.
///
/// The blur is a Gaussian stretched along `angle`, so the form reads as a long exposure of
/// something moving rather than a static blob.
public struct LightForm: Hashable, Sendable {
    /// Control points of a closed Catmull-Rom spline.
    public var points: [LightPoint]
    /// The gradient runs from `axisStart` (deepest colour) to `axisEnd` (brightest).
    public var axisStart: LightPoint
    public var axisEnd: LightPoint
    public var palette: LightPalette
    /// Gaussian blur, as a fraction of the view's width.
    public var blur: Double
    /// How many times longer the blur is along the motion than across it.
    public var stretch: Double
    /// Direction of motion in radians, screen space (y down).
    public var angle: Double
    public var opacity: Double

    public init(
        points: [LightPoint],
        axisStart: LightPoint,
        axisEnd: LightPoint,
        palette: LightPalette,
        blur: Double,
        stretch: Double = 1,
        angle: Double = 0,
        opacity: Double = 1
    ) {
        self.points = points
        self.axisStart = axisStart
        self.axisEnd = axisEnd
        self.palette = palette
        self.blur = blur
        self.stretch = stretch
        self.angle = angle
        self.opacity = opacity
    }

    /// The shape, as a smooth closed path through the control points.
    public func path(in size: CGSize) -> Path {
        let pts = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var path = Path()
        let n = pts.count
        guard n >= 3 else { return path }
        path.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    var gradient: LinearGradient {
        LinearGradient(
            stops: palette.samples().map { Gradient.Stop(color: Color($0.color), location: CGFloat($0.location)) },
            startPoint: UnitPoint(x: axisStart.x, y: axisStart.y),
            endPoint: UnitPoint(x: axisEnd.x, y: axisEnd.y)
        )
    }
}

/// The light behind a screen or a surface: a few forms over the mist.
public struct LightComposition: Hashable, Sendable {
    public var forms: [LightForm]

    public init(forms: [LightForm]) {
        self.forms = forms
    }
}

// MARK: - Compositions

extension LightComposition {
    /// One sweep of light through the upper half, grounded by a soft haze below. Question screens.
    public static func sweep(_ palette: LightPalette) -> LightComposition {
        LightComposition(forms: [
            haze(palette, points: [(-0.10, 0.60), (0.45, 0.55), (0.95, 0.65), (0.90, 0.85), (0.30, 0.90), (-0.15, 0.78)],
                 from: (0, 0.60), to: (1, 0.83), opacity: 0.8),
            LightForm(
                points: points([(1.04, 0.166), (0.74, 0.111), (0.46, 0.166), (0.24, 0.323), (0.05, 0.535),
                                (0.20, 0.544), (0.40, 0.406), (0.60, 0.314), (0.84, 0.341), (1.06, 0.424)]),
                axisStart: LightPoint(1.0, 0.185),
                axisEnd: LightPoint(0.08, 0.53),
                palette: palette,
                blur: 0.048,
                stretch: 2.4,
                angle: -0.95
            ),
        ])
    }

    /// A pocket of light for a lens to hold, centred on `center`, with faint drifts around it.
    /// The welcome screen.
    public static func pocket(_ palette: LightPalette, center: LightPoint, radius: Double, aspect: Double) -> LightComposition {
        LightComposition(forms: [
            haze(palette, points: [(0.30, 0.30), (0.85, 0.26), (1.10, 0.50), (0.80, 0.62), (0.40, 0.55)],
                 from: (0.3, 0.3), to: (1, 0.6), opacity: 0.55, blur: 0.16),
            haze(palette, points: [(-0.10, 0.74), (0.55, 0.70), (1.05, 0.82), (0.80, 1.02), (0.10, 1.02)],
                 from: (0, 0.7), to: (1, 1), opacity: 0.6, blur: 0.16),
            LightForm(
                points: blob(center: center, radius: radius, aspect: aspect),
                axisStart: LightPoint(center.x - radius * 0.7, center.y - radius * 0.7 / aspect),
                axisEnd: LightPoint(center.x + radius * 0.9, center.y + radius * 0.9 / aspect),
                palette: palette,
                blur: 0.05,
                stretch: 1.5,
                angle: -0.6
            ),
        ])
    }

    /// Light filling a small surface, such as the action bar's orb.
    public static func glow(_ palette: LightPalette) -> LightComposition {
        LightComposition(forms: [
            LightForm(
                points: points([(0.05, 0.20), (0.50, -0.10), (0.98, 0.25), (0.95, 0.85), (0.45, 1.10), (0.02, 0.80)]),
                axisStart: LightPoint(0, 0),
                axisEnd: LightPoint(1, 1),
                palette: palette,
                blur: 0.10,
                stretch: 1.3,
                angle: -0.3
            ),
        ])
    }

    // MARK: Helpers

    private static func points(_ values: [(Double, Double)]) -> [LightPoint] {
        values.map { LightPoint($0.0, $0.1) }
    }

    private static func haze(
        _ palette: LightPalette,
        points values: [(Double, Double)],
        from: (Double, Double),
        to: (Double, Double),
        opacity: Double,
        blur: Double = 0.14
    ) -> LightForm {
        let colors = palette.haze.count >= 2 ? palette.haze : LightPalette.defaultHaze(for: [palette.brightest])
        return LightForm(
            points: points(values),
            axisStart: LightPoint(from.0, from.1),
            axisEnd: LightPoint(to.0, to.1),
            palette: LightPalette(colors: colors),
            blur: blur,
            stretch: 1.3,
            angle: -0.4,
            opacity: opacity
        )
    }

    /// A slightly irregular round shape, so a pocket of light never looks like a perfect circle.
    private static func blob(center: LightPoint, radius: Double, aspect: Double) -> [LightPoint] {
        let wobble: [Double] = [1.0, 0.92, 1.06, 0.95, 1.08, 0.90, 1.03, 0.97]
        return wobble.enumerated().map { index, scale in
            let angle = Double(index) / Double(wobble.count) * 2 * .pi
            return LightPoint(
                center.x + cos(angle) * radius * scale,
                center.y + sin(angle) * radius * scale / aspect
            )
        }
    }
}
