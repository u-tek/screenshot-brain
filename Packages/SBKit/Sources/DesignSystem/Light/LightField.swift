import SwiftUI

/// Draws a light composition: each form is a filled shape, blurred, over the mist.
///
/// The whole field renders in linear colour, so the blur falls off like real light rather than
/// leaving a muddy halo.
public struct LightField: View {
    private let composition: LightComposition
    private let showsGround: Bool
    private let grain: Double
    @Environment(\.colorScheme) private var colorScheme

    public init(_ composition: LightComposition, ground: Bool = true, grain: Double = 0.05) {
        self.composition = composition
        self.showsGround = ground
        self.grain = grain
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                if showsGround {
                    LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom)
                }
                ForEach(Array(composition.forms.enumerated()), id: \.offset) { _, form in
                    LightFormView(form: form, size: proxy.size)
                        // At night the same light glows: it adds onto the dark ground.
                        .blendMode(colorScheme == .dark ? .screen : .normal)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .drawingGroup(colorMode: .linear)
            .overlay {
                if grain > 0 {
                    GrainOverlay(amount: grain)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    var body: some View {
        form.path(in: size)
            .fill(form.gradient)
            .frame(width: size.width, height: size.height)
            .opacity(form.opacity)
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
