import SwiftUI

/// What the light behind a screen is doing. Screens set it from their own state (how much is
/// waiting, the card being dragged, the item's kind) and the light eases from one setting to the
/// next while it drifts.
public struct SBAmbience: Equatable, Sendable {
    /// 0 is calm: a slow, dim drift. 1 is lively: brighter and quicker.
    public var energy: Double
    /// The main light's colour.
    public var tint: RGB
    /// -1...1 each way: the light leans after a drag, as if following the thumb.
    public var lean: CGSize
    /// 0...1: how far the light has dimmed (towards a drop).
    public var dim: Double
    /// 0...1: a brief warm-white flash (a thing marked done).
    public var flash: Double

    public init(energy: Double = 0.35, tint: RGB = SBRamp.rgb[3], lean: CGSize = .zero, dim: Double = 0, flash: Double = 0) {
        self.energy = energy
        self.tint = tint
        self.lean = lean
        self.dim = dim
        self.flash = flash
    }

    /// A settled screen: settings, an empty pile.
    public static let calm = SBAmbience(energy: 0.15)
    /// Most screens.
    public static let standard = SBAmbience()

    /// Lit in a kind's colour.
    public static func kind(_ kind: SBKind, energy: Double = 0.35) -> SBAmbience {
        SBAmbience(energy: energy, tint: RGB(hex: kind.coreHex))
    }
}

/// The ground every screen sits on: warm light that is always slowly moving. It speeds up and
/// brightens with `energy`, takes `tint` for its main glow, leans with `lean` and dims with `dim`.
/// Still under Reduce Motion, in snapshots, and whenever the screen is out of sight.
public struct SBLiveBackground: View {
    private let ambience: SBAmbience
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lightIsStill) private var lightIsStill
    @State private var isVisible = false

    public init(_ ambience: SBAmbience = .standard) {
        self.ambience = ambience
    }

    private var isStill: Bool {
        reduceMotion || lightIsStill
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isStill || !isVisible)) { context in
            LiveLightCanvas(
                time: isStill ? 0 : context.date.timeIntervalSinceReferenceDate,
                energy: ambience.energy,
                tint: ambience.tint,
                lean: ambience.lean,
                dim: ambience.dim,
                flash: ambience.flash
            )
        }
        // Settings change over most of a second, so the light swells and fades rather than jumps,
        // and trails a drag a little, like light following the thumb.
        .animation(.easeInOut(duration: 0.9), value: ambience.energy)
        .animation(.easeInOut(duration: 0.9), value: ambience.tint)
        .animation(.easeOut(duration: 0.35), value: ambience.dim)
        .overlay(GrainOverlay(amount: 0.12))
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Four soft glows on the warm ground, each on its own slow orbit, mixed like light (screen
/// blending). Drawn as radial gradients on one canvas: no blur, so it stays cheap on old phones.
private struct LiveLightCanvas: View, Animatable {
    var time: Double
    var energy: Double
    var tint: RGB
    var lean: CGSize
    var dim: Double
    var flash: Double

    // Everything but the clock eases: ((energy, dim), (flash, lean x)), ((lean y, red), (green, blue)).
    var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>,
        AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(AnimatablePair(energy, dim), AnimatablePair(flash, Double(lean.width))),
                AnimatablePair(AnimatablePair(Double(lean.height), tint.red), AnimatablePair(tint.green, tint.blue))
            )
        }
        set {
            energy = newValue.first.first.first
            dim = newValue.first.first.second
            flash = newValue.first.second.first
            lean = CGSize(width: newValue.first.second.second, height: newValue.second.first.first)
            tint = RGB(red: newValue.second.first.second, green: newValue.second.second.first, blue: newValue.second.second.second)
        }
    }

    var body: some View {
        // Plain values only inside the canvas, which may draw off the main actor.
        let glows = liveGlows
        let ground = SBColor.ground
        let white = SBColor.accent
        let energy = self.energy, tint = self.tint, lean = self.lean, dim = self.dim, flash = self.flash
        let t = time * (0.45 + energy * 0.9)
        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            context.blendMode = .screen

            let brightness = (0.3 + energy * 0.5) * (1 - dim * 0.75)
            let span = max(size.width, size.height)

            for glow in glows {
                let x = size.width * (glow.x + glow.wanderX * sin(t * glow.speedX + glow.phase))
                    + lean.width * size.width * 0.2 * glow.depth
                let y = size.height * (glow.y + glow.wanderY * cos(t * glow.speedY + glow.phase))
                    + lean.height * size.height * 0.12 * glow.depth
                // Each glow breathes a little as it moves.
                let radius = span * glow.radius * (0.92 + energy * 0.12 + 0.05 * sin(t * 0.7 + glow.phase))
                let rgb = glow.color ?? tint
                let color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
                let strength = glow.alpha * brightness
                let gradient = Gradient(stops: [
                    .init(color: color.opacity(strength), location: 0),
                    .init(color: color.opacity(strength * 0.45), location: 0.42),
                    .init(color: color.opacity(0), location: 1),
                ])
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
            }

            if flash > 0 {
                let radius = span * 0.5
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.4)
                let gradient = Gradient(colors: [white.opacity(0.4 * flash), white.opacity(0)])
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
            }
        }
    }
}

/// A glow: where it rests (unit square), how far and how fast it wanders, how big, how strong,
/// and how far it leans with a drag (nearer glows lean more). No colour means the screen's tint.
private struct LiveGlow: Sendable {
    var x, y, wanderX, wanderY, speedX, speedY, phase, radius, alpha, depth: Double
    var color: RGB?
}

private let liveGlows: [LiveGlow] = [
    // The main glow, low and centred, in the screen's tint.
    LiveGlow(x: 0.5, y: 0.8, wanderX: 0.2, wanderY: 0.07, speedX: 0.41, speedY: 0.29, phase: 0, radius: 0.78, alpha: 0.95, depth: 1, color: nil),
    // Ember, upper left.
    LiveGlow(x: 0.16, y: 0.28, wanderX: 0.14, wanderY: 0.11, speedX: 0.27, speedY: 0.37, phase: 1.9, radius: 0.55, alpha: 0.5, depth: 0.6, color: SBRamp.rgb[4]),
    // Deep rust, right.
    LiveGlow(x: 0.88, y: 0.52, wanderX: 0.1, wanderY: 0.16, speedX: 0.33, speedY: 0.23, phase: 3.7, radius: 0.66, alpha: 0.75, depth: 0.8, color: SBRamp.rgb[2]),
    // A small peach highlight that roams the top.
    LiveGlow(x: 0.62, y: 0.12, wanderX: 0.24, wanderY: 0.08, speedX: 0.53, speedY: 0.43, phase: 5.1, radius: 0.34, alpha: 0.32, depth: 1.3, color: SBRamp.rgb[5]),
]
