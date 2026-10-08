import Core
import Foundation

/// The colours an item's light is made from: one gradient, deepest colour first, plus pale
/// haze colours that ground a composition.
public struct LightPalette: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public var position: Double
        public var color: RGB

        public init(position: Double, color: RGB) {
            self.position = position
            self.color = color
        }
    }

    public var stops: [Stop]
    public var haze: [RGB]

    public init(stops: [Stop], haze: [RGB]) {
        precondition(stops.count >= 2, "A gradient needs at least two stops")
        self.stops = stops.sorted { $0.position < $1.position }
        self.haze = haze
    }

    /// Evenly spaced stops, deepest first. Haze defaults to a pale tint of the brightest colour.
    public init(colors: [RGB], haze: [RGB]? = nil) {
        let count = max(colors.count - 1, 1)
        let stops = colors.enumerated().map { Stop(position: Double($0.offset) / Double(count), color: $0.element) }
        self.init(stops: stops, haze: haze ?? Self.defaultHaze(for: colors))
    }

    /// The gradient at `t` (0...1), interpolated in OKLab.
    public func color(at t: Double) -> RGB {
        let t = min(max(t, stops[0].position), stops[stops.count - 1].position)
        guard let upper = stops.firstIndex(where: { $0.position >= t }), upper > 0 else {
            return stops[0].color
        }
        let a = stops[upper - 1], b = stops[upper]
        let span = b.position - a.position
        let local = span > 0 ? (t - a.position) / span : 0
        return OKLab(a.color).mix(OKLab(b.color), local).rgb
    }

    /// Dense samples of the gradient. Core Graphics interpolates between them in sRGB, so
    /// sampling densely keeps the whole ramp perceptual.
    func samples(_ count: Int = 24) -> [(location: Double, color: RGB)] {
        (0..<count).map { index -> (location: Double, color: RGB) in
            let t = Double(index) / Double(count - 1)
            return (location: t, color: color(at: t))
        }
    }

    /// The same light, reversed: brightest first.
    public var reversed: LightPalette {
        LightPalette(stops: stops.map { Stop(position: 1 - $0.position, color: $0.color) }, haze: haze)
    }

    var deepest: RGB { stops[0].color }
    var brightest: RGB { stops[stops.count - 1].color }

    static func defaultHaze(for colors: [RGB]) -> [RGB] {
        guard let brightest = colors.last else { return [] }
        let lab = OKLab(brightest)
        return [
            lab.with(lightness: 0.92, chroma: min(lab.chroma, 0.04)).rgb,
            lab.with(lightness: 0.95, chroma: min(lab.chroma, 0.025)).rgb,
        ]
    }
}

// MARK: - From a screenshot

extension LightPalette {
    /// Builds an item's light from its screenshot's dominant colours.
    ///
    /// Greys carry no light, so they're ignored. Returns nil when nothing colourful is left, and the
    /// caller falls back to the category's light.
    public init?(extracted colors: [PaletteColor]) {
        struct Candidate {
            let lab: OKLab
            let weight: Double
            var score: Double { weight * lab.chroma }
        }
        var candidates: [Candidate] = []
        for color in colors {
            let lab = OKLab(RGB(red: color.red, green: color.green, blue: color.blue))
            if lab.chroma > 0.045 && color.weight > 0.03 {
                candidates.append(Candidate(lab: lab, weight: color.weight))
            }
        }
        guard !candidates.isEmpty else { return nil }
        candidates.sort { $0.score > $1.score }

        var labs: [OKLab] = candidates.prefix(3).map { $0.lab }
        labs.sort { $0.l < $1.l }
        // A deep end gives the light its body...
        if labs[0].l > 0.42 {
            labs.insert(labs[0].with(lightness: 0.34, chroma: max(labs[0].chroma, 0.12)), at: 0)
        }
        // ...and a bright end gives it a leading edge.
        let last = labs[labs.count - 1]
        if last.l < 0.78 {
            labs.append(last.with(lightness: 0.84, chroma: last.chroma * 0.7))
        }
        // The app has one warm palette: each colour keeps its place in the light (its lightness)
        // but takes its hue from the warm ramp.
        let ramp = LightPalette(colors: Self.rampRGB)
        let rgbs: [RGB] = labs.map { lab in ramp.color(at: min(max((lab.l - 0.18) / 0.77, 0), 1)) }
        self.init(colors: rgbs)
    }

    /// The warm ramp, deep ember to bone (the same values as `SBRamp`).
    static let rampRGB: [RGB] = [0x1D0E08, 0x4A1C0C, 0x8E3415, 0xE2582B, 0xFF8A57, 0xFFB381, 0xF2D4B6, 0xF6ECE2].map(RGB.init(hex:))
}

// MARK: - Category light

extension LightPalette {
    /// The light used when an item has no colours of its own, or isn't safe to take them from.
    public static func category(_ category: ItemCategory) -> LightPalette {
        let kind = SBKind(category)
        return LightPalette(colors: [RGB(hex: kind.deepHex), RGB(hex: kind.coreHex)])
    }

    /// An item's light. Every kind is a step on the one warm ramp, so an item's light is its
    /// kind's, whatever colours its screenshot has.
    public static func item(category: ItemCategory, colors: [PaletteColor], isSafeToDisplay: Bool) -> LightPalette {
        .category(category)
    }
}

// MARK: - Samples

extension LightPalette {
    /// The light for a typical set of top screenshots: the warm ramp. Used by the design lab and
    /// previews.
    public static let sampleTopScreenshots = LightPalette(
        colors: Array(rampRGB[1...5]),
        haze: [rampRGB[6], rampRGB[7]]
    )

    /// The ember ramp.
    public static let ember = sampleTopScreenshots

    public static let sampleSunsetBar = LightPalette.category(.place)

    public static let sampleGigPoster = LightPalette.category(.event)
}
