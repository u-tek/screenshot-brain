import Foundation

/// A colour in sRGB, components 0...1 (gamma-encoded, as designers specify them).
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// OKLab: a perceptual colour space. Gradients interpolated here keep their saturation through
/// the middle (indigo to orange passes through magenta, not grey).
struct OKLab: Hashable, Sendable {
    var l: Double
    var a: Double
    var b: Double

    var chroma: Double {
        (a * a + b * b).squareRoot()
    }

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ rgb: RGB) {
        let r = Self.linear(rgb.red), g = Self.linear(rgb.green), bl = Self.linear(rgb.blue)
        let lms0 = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl
        let lms1 = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl
        let lms2 = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl
        let l_ = cbrt(lms0), m_ = cbrt(lms1), s_ = cbrt(lms2)
        l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }

    var rgb: RGB {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bl = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        return RGB(red: Self.encoded(r), green: Self.encoded(g), blue: Self.encoded(bl))
    }

    func mix(_ other: OKLab, _ t: Double) -> OKLab {
        OKLab(l: l + (other.l - l) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }

    /// Same hue, new lightness and chroma.
    func with(lightness: Double? = nil, chroma newChroma: Double? = nil) -> OKLab {
        var scale = 1.0
        if let newChroma, chroma > 0.0001 {
            scale = newChroma / chroma
        }
        return OKLab(l: lightness ?? l, a: a * scale, b: b * scale)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ c: Double) -> Double {
        let clamped = min(max(c, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}
