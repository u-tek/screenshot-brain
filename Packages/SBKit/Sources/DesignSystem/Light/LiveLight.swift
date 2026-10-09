import SwiftUI

/// What the light behind a screen is doing. Screens set it from their own state (how much is
/// waiting, the card being dragged, the item's kind) and the light eases from one setting to the
/// next while it slowly changes shape.
public struct SBAmbience: Equatable, Sendable {
    /// 0 is calm: dimmer, and barely changing shape. 1 is lively: brighter, and reshaping more.
    public var energy: Double
    /// The light's colours.
    public var palette: LightPalette
    /// -1...1 each way: the light leans after a drag, as if following the thumb.
    public var lean: CGSize
    /// 0...1: how far the light has dimmed (towards a drop).
    public var dim: Double
    /// Counts up by one for each brief warm-white flash (a thing marked done).
    public var flashes: Int

    public init(energy: Double = 0.35, palette: LightPalette = .ember, lean: CGSize = .zero, dim: Double = 0, flashes: Int = 0) {
        self.energy = energy
        self.palette = palette
        self.lean = lean
        self.dim = dim
        self.flashes = flashes
    }

    /// A settled screen: settings, an empty pile.
    public static let calm = SBAmbience(energy: 0.15)
    /// Most screens.
    public static let standard = SBAmbience()

    /// Lit in a kind's colours.
    public static func kind(_ kind: SBKind, energy: Double = 0.35) -> SBAmbience {
        SBAmbience(energy: energy, palette: LightPalette(colors: [RGB(hex: kind.deepHex), RGB(hex: kind.coreHex)]))
    }
}

/// The ground every screen sits on: the onboarding's sweep of light, slowly changing shape. It
/// brightens and reshapes more with `energy`, takes its colours from `palette` (fading from one
/// to the next), leans with `lean` and dims with `dim`. Still under Reduce Motion, in
/// snapshots, and whenever the screen is out of sight.
public struct SBLiveBackground: View {
    private let ambience: SBAmbience
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lightIsStill) private var lightIsStill
    @State private var isVisible = false
    @State private var light = LightEasing()

    public init(_ ambience: SBAmbience = .standard) {
        self.ambience = ambience
    }

    private var isStill: Bool {
        reduceMotion || lightIsStill
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isStill || !isVisible)) { context in
                let frame = light.frame(toward: ambience, at: context.date.timeIntervalSinceReferenceDate, still: isStill)
                LiveLight(frame: frame, size: proxy.size)
            }
        }
        .background(SBColor.ground)
        .overlay(GrainOverlay(amount: 0.1))
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One frame's light, after easing.
private struct LightFrame {
    var energy: Double
    var lean: CGSize
    var dim: Double
    var flash: Double
    /// How far through its slow change of shape the light is, in radians.
    var phase: Double
    var palette: LightPalette
    /// The colours fading out after a change, and how far the new ones have faded in (0...1).
    var fadingPalette: LightPalette?
    var fade: Double
}

/// Eases the light towards each new setting, frame by frame: it brightens and changes colour
/// over most of a second, and trails a drag a little, like light following a thumb. The change
/// of shape runs at a steady pace that only drifts with energy, so the light never jumps.
/// Only ever used from its view's body.
private final class LightEasing {
    private var current: LightFrame?
    private var lastTime: Double?
    private var flashes = 0
    private var flashStart = -Double.infinity

    func frame(toward target: SBAmbience, at time: Double, still: Bool) -> LightFrame {
        if still || current == nil {
            let frame = LightFrame(energy: target.energy, lean: target.lean, dim: target.dim, flash: 0, phase: 0, palette: target.palette, fadingPalette: nil, fade: 1)
            current = frame
            lastTime = time
            flashes = target.flashes
            return frame
        }
        guard var frame = current, let last = lastTime else { return current! }
        // A redraw between ticks repeats the last tick's time: show the same frame again.
        guard time > last else { return frame }
        let step = min(time - last, 0.25)
        let slow = 1 - exp(-step / 0.45)
        let quick = 1 - exp(-step / 0.12)

        frame.energy += (target.energy - frame.energy) * slow
        frame.dim += (target.dim - frame.dim) * quick
        frame.lean = CGSize(
            width: frame.lean.width + (target.lean.width - frame.lean.width) * quick,
            height: frame.lean.height + (target.lean.height - frame.lean.height) * quick
        )
        // One change of shape every 14 seconds or so, a little quicker when lively.
        frame.phase += step * 2 * .pi / 14 * (0.7 + 0.6 * frame.energy)

        if target.palette != frame.palette {
            frame.fadingPalette = frame.palette
            frame.palette = target.palette
            frame.fade = 0
        }
        if frame.fadingPalette != nil {
            frame.fade = min(1, frame.fade + step / 0.8)
            if frame.fade >= 1 { frame.fadingPalette = nil }
        }

        if target.flashes != flashes {
            flashes = target.flashes
            flashStart = time
        }
        // A flash peaks at once and fades over about a second.
        let sinceFlash = time - flashStart
        frame.flash = sinceFlash >= 0 && sinceFlash < 2 ? exp(-sinceFlash * 2.5) : 0

        current = frame
        lastTime = time
        return frame
    }
}

/// The sweep of light in one frame: reshaped by the phase, brighter with energy, dimmed, leaning,
/// with the old colours fading out under the new after a change.
private struct LiveLight: View {
    let frame: LightFrame
    let size: CGSize

    var body: some View {
        let amount = 0.02 + 0.03 * frame.energy
        let brightness = (0.7 + 0.3 * frame.energy) * (1 - frame.dim * 0.7)
        ZStack {
            if let fading = frame.fadingPalette {
                layer(fading, amount: amount)
                    .opacity(1 - frame.fade)
            }
            layer(frame.palette, amount: amount)
                .opacity(frame.fadingPalette == nil ? 1 : frame.fade)
            if frame.flash > 0 {
                RadialGradient(
                    colors: [SBColor.accent.opacity(0.35 * frame.flash), SBColor.accent.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: size.width * 0.9
                )
                .blendMode(.screen)
            }
        }
        .opacity(brightness)
        .offset(x: frame.lean.width * size.width * 0.12, y: frame.lean.height * size.height * 0.08)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func layer(_ palette: LightPalette, amount: Double) -> some View {
        MorphingLightLayer(composition: LightComposition.sweep(palette).morphed(phase: frame.phase, amount: frame.phase == 0 ? 0 : amount), size: size)
    }
}
