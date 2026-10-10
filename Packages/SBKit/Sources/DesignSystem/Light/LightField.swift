import SwiftUI

/// Draws a light composition: each form is a filled shape, blurred, over the mist.
///
/// The whole field renders in linear colour, so the blur falls off like real light rather than
/// leaving a muddy halo.
public struct LightField: View {
    private let composition: LightComposition
    private let showsGround: Bool
    private let grain: Double
    private let drifts: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lightIsStill) private var lightIsStill

    /// - Parameter drifts: Slowly moves the light on a 12-second loop. For full-screen fields;
    ///   always still under Reduce Motion.
    public init(_ composition: LightComposition, ground: Bool = true, grain: Double = 0.05, drifts: Bool = false) {
        self.composition = composition
        self.showsGround = ground
        self.grain = grain
        self.drifts = drifts
    }

    private var isDrifting: Bool {
        drifts && !reduceMotion && !lightIsStill
    }

    /// The composition in this appearance's colours: light mode takes the north star's.
    private var shown: LightComposition {
        colorScheme == .dark ? composition : composition.inLightMode()
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: nil, paused: !isDrifting)) { context in
                if isDrifting {
                    morphingField(size: proxy.size, time: context.date.timeIntervalSinceReferenceDate)
                } else {
                    field(size: proxy.size, time: 0)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// While drifting, the light slowly changes shape: one loop every `SBMotion.driftPeriod`
    /// seconds, at a steady rate so it never jumps.
    private func morphingField(size: CGSize, time: Double) -> some View {
        let phase = time / SBMotion.driftPeriod * 2 * .pi
        return ZStack {
            if showsGround {
                LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom)
            }
            MorphingLightLayer(composition: shown.morphed(phase: phase, amount: 0.035), size: size, night: colorScheme == .dark)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay {
            if grain > 0 {
                GrainOverlay(amount: grain)
            }
        }
    }

    private func field(size: CGSize, time: Double) -> some View {
        ZStack {
            if showsGround {
                LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom)
            }
            ForEach(Array(shown.forms.enumerated()), id: \.offset) { index, form in
                let phase = time / SBMotion.driftPeriod * 2 * .pi + Double(index) * 1.7
                LightFormView(form: form, size: size, night: colorScheme == .dark)
                    // Each form is filled and blurred once, in linear colour, on a canvas a
                    // little larger than the screen so the drift never shows its edge. The drift
                    // below only moves the finished layer, so it costs almost nothing per frame
                    // (an iPhone 8 can't afford to re-blur a full-screen field 30 times a second).
                    .frame(width: size.width * 1.16, height: size.height + size.width * 0.16)
                    .drawingGroup(colorMode: .linear)
                    // Drift: each form wanders a few points and turns a degree or two, on its own phase.
                    .offset(x: CGFloat(cos(phase)) * size.width * 0.018, y: CGFloat(sin(phase * 0.8)) * size.width * 0.022)
                    .rotationEffect(.degrees(sin(phase * 0.6) * 1.5))
                    // At night the same light glows: it adds onto the dark ground.
                    .blendMode(colorScheme == .dark ? .screen : .normal)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay {
            if grain > 0 {
                GrainOverlay(amount: grain)
            }
        }
    }
}

/// A whole composition drawn at a quarter of the size and scaled up. Soft light loses nothing at
/// that size, and re-blurring a quarter-size field is cheap enough to reshape the light every
/// frame, even on an iPhone 8.
struct MorphingLightLayer: View {
    let composition: LightComposition
    let size: CGSize
    var night = true

    private static let scale: CGFloat = 4

    var body: some View {
        let small = CGSize(width: size.width / Self.scale, height: size.height / Self.scale)
        ZStack {
            ForEach(Array(composition.forms.enumerated()), id: \.offset) { _, form in
                LightFormView(form: form, size: small, night: night)
                    .blendMode(night ? .screen : .normal)
            }
        }
        // A margin, so the blur fades out past the screen's edge rather than at it.
        .frame(width: small.width * 1.2, height: small.height * 1.2)
        .drawingGroup(colorMode: .linear)
        .scaleEffect(Self.scale)
        .frame(width: size.width, height: size.height)
    }
}

/// One form: the shape filled with its gradient, then a Gaussian blur stretched along the motion.
///
/// The stretch works by turning the motion direction onto the x axis, squashing x, blurring
/// evenly, then undoing the squash and the turn: the blur ends up `stretch` times longer along
/// the motion than across it.
struct LightFormView: View {
    let form: LightForm
    let size: CGSize
    var night = false

    var body: some View {
        form.path(in: size)
            .fill(form.gradient)
            .frame(width: size.width, height: size.height)
            .opacity(form.opacity * (night ? form.nightOpacity : 1))
            .rotationEffect(.radians(-form.angle))
            .scaleEffect(x: 1 / form.stretch, y: 1)
            .blur(radius: form.blur * size.width)
            .scaleEffect(x: form.stretch, y: 1)
            .rotationEffect(.radians(form.angle))
    }
}

/// Very faint film grain, to keep gradients from banding and give surfaces a physical feel.
public struct GrainOverlay: View {
    private let amount: Double
    @Environment(\.displayScale) private var displayScale

    public init(amount: Double = 0.05) {
        self.amount = amount
    }

    public var body: some View {
        Image(decorative: Grain.texture, scale: displayScale)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(amount)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum Grain {
    /// 128×128 grey noise, generated once with a fixed seed so every render matches.
    static let texture: CGImage = make()

    private static func make() -> CGImage {
        let side = 128
        var state: UInt32 = 0x9E37_79B9
        var bytes = [UInt8](repeating: 0, count: side * side)
        for index in bytes.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            bytes[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
