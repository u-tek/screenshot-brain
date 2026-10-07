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
        let rgbs: [RGB] = labs.map { $0.rgb }
        self.init(colors: rgbs)
    }
}

// MARK: - Category light

extension LightPalette {
    /// The light used when an item has no colours of its own, or isn't safe to take them from.
    public static func category(_ category: ItemCategory) -> LightPalette {
        switch category {
        case .place: ramp(0xFF7A3D, 0xFFC29A, deepLightness: 0.45)
        case .event: ramp(0xE8458B, 0xFFA3C7, deepLightness: 0.38)
        case .product: ramp(0x4B3FD1, 0xA9A3FF, deepLightness: 0.30)
        case .recipe: ramp(0x7FA83A, 0xD4EBA0, deepLightness: 0.42)
        case .reference: ramp(0x9AA0AA, 0xE4E6EB, deepLightness: 0.55)
        case .other: ramp(0x8F8BB4, 0xE3E0F0, deepLightness: 0.45)
        }
    }

    /// An item's light: its own colours when it's safe to show, otherwise its category's.
    public static func item(category: ItemCategory, colors: [PaletteColor], isSafeToDisplay: Bool) -> LightPalette {
        if isSafeToDisplay, let own = LightPalette(extracted: colors) {
            return own
        }
        return .category(category)
    }

    /// Brief's two-colour category ramp, with a deeper version of the first colour added for body.
    private static func ramp(_ strong: UInt32, _ pale: UInt32, deepLightness: Double) -> LightPalette {
        let strongLab = OKLab(RGB(hex: strong))
        let deep = strongLab.with(lightness: deepLightness, chroma: strongLab.chroma * 0.9).rgb
        return LightPalette(colors: [deep, RGB(hex: strong), RGB(hex: pale)])
    }
}

// MARK: - Samples

extension LightPalette {
    /// What extraction yields for a typical set of top screenshots (a product page, a gig poster,
    /// a sunset bar). Used by the design lab and previews.
    public static let sampleTopScreenshots = LightPalette(
        colors: [0x24206F, 0x4A3BB8, 0xC34FA0, 0xF57E74, 0xFFB07A].map(RGB.init(hex:)),
        haze: [RGB(hex: 0xE2D6F5), RGB(hex: 0xF6DCE6)]
    )

    public static let sampleSunsetBar = LightPalette(extracted: [
        PaletteColor(red: 0.95, green: 0.65, blue: 0.25, weight: 0.35),
        PaletteColor(red: 0.55, green: 0.18, blue: 0.11, weight: 0.20),
        PaletteColor(red: 0.73, green: 0.65, blue: 0.84, weight: 0.15),
        PaletteColor(red: 0.20, green: 0.20, blue: 0.20, weight: 0.30),
    ]) ?? .category(.place)

    public static let sampleGigPoster = LightPalette(extracted: [
        PaletteColor(red: 0.84, green: 0.14, blue: 0.43, weight: 0.40),
        PaletteColor(red: 0.07, green: 0.07, blue: 0.07, weight: 0.40),
        PaletteColor(red: 0.23, green: 0.70, blue: 0.79, weight: 0.10),
    ]) ?? .category(.event)
}
