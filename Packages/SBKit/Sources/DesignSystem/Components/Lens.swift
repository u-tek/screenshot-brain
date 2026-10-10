import QuartzCore
import SwiftUI
import UIKit

/// The hero object: a clear glass disc. It holds no colour of its own; it sits over the light
/// and bends it, so the colour you see through it is the user's own. It turns very slightly
/// with the phone (a few degrees), and holds still under Reduce Motion.
public struct GlassLens: View {
    private let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lightIsStill) private var lightIsStill

    public init(diameter: CGFloat) {
        self.diameter = diameter
    }

    public var body: some View {
        let tilts = !reduceMotion && !lightIsStill
        TimelineView(.animation(minimumInterval: nil, paused: !tilts)) { _ in
            let tilt = tilts ? DeviceTilt.shared.current : .zero
            ZStack {
                Color.clear
                    .sbGlass(in: Circle(), style: .clear)
                // A hairline of light catching the upper rim, moving with the tilt.
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [SBColor.warm(0.7), SBColor.warm(0)],
                            startPoint: UnitPoint(x: 0.5 + tilt.width * 0.6, y: 0),
                            endPoint: .center
                        ),
                        lineWidth: 0.75
                    )
            }
            .frame(width: diameter, height: diameter)
            .rotation3DEffect(.degrees(tilt.width * 4), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(-tilt.height * 4), axis: (x: 1, y: 0, z: 0))
        }
        .frame(width: diameter, height: diameter)
        .onAppear { if tilts { DeviceTilt.shared.retain() } }
        .onDisappear { if tilts { DeviceTilt.shared.release() } }
        .accessibilityHidden(true)
    }
}

/// A thin circle around the lens, with one orange dot where the active label meets it.
public struct LensOrbit: View {
    private let diameter: CGFloat
    /// Where the dot sits, in radians from the positive x axis (screen space).
    private let dotAngle: Double

    public init(diameter: CGFloat, dotAngle: Double = 0) {
        self.diameter = diameter
        self.dotAngle = dotAngle
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(SBColor.hairline, lineWidth: 0.75)
            Circle()
                .fill(SBColor.accent)
                .frame(width: 9, height: 9)
                .offset(x: CGFloat(cos(dotAngle)) * diameter / 2, y: CGFloat(sin(dotAngle)) * diameter / 2)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The app's mark: the v4 bracket mark.
public struct AppMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 16) {
        self.size = size
    }

    public var body: some View {
        SBMark(size: size)
    }
}

/// Four corner brackets, like a viewfinder.
public struct FrameCorners: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.32
        var path = Path()
        // top left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // top right
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // bottom right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        // bottom left
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return path
    }
}

/// A hairline ruler with ticks and one orange mark at the centre. Drag to change the value.
///
/// The ticks slide under the mark with the finger, point for point (not a tick at a time), coast
/// on after a flick and settle on a tick, frame by frame at the display's rate. Every tick that
/// passes the mark clicks, firmer on every fifth.
public struct TickRuler: View {
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let spokenValue: (Int) -> String
    /// The tick under the mark, counted from the start of the range. Fractional while the ruler
    /// moves; nil when it rests on `value`.
    @State private var position: CGFloat?
    @State private var dragStart: CGFloat?
    @StateObject private var coast = RulerCoast()

    private static let spacing: CGFloat = 8

    public init(value: Binding<Int>, in range: ClosedRange<Int>, step: Int, spokenValue: @escaping (Int) -> String = { "\($0)" }) {
        self._value = value
        self.range = range
        self.step = step
        self.spokenValue = spokenValue
    }

    private var lastTick: CGFloat {
        CGFloat((range.upperBound - range.lowerBound) / step)
    }

    private func tick(for value: Int) -> CGFloat {
        CGFloat((value - range.lowerBound) / step)
    }

    private func snappedValue(at tick: CGFloat) -> Int {
        min(max(range.lowerBound + Int(tick.rounded()) * step, range.lowerBound), range.upperBound)
    }

    public var body: some View {
        GeometryReader { proxy in
            let current = position ?? tick(for: value)
            ZStack {
                RulerTicks(position: current, lastTick: lastTick, firstTick: range.lowerBound / step, spacing: Self.spacing)
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                    .init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Capsule()
                    .fill(SBColor.accent)
                    .frame(width: 2, height: 28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(drag)
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityValue(Text(spokenValue(value)))
        .accessibilityAdjustableAction { direction in
            coast.stop()
            position = nil
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStart == nil {
                    // A touch catches the ruler mid-coast, where it is.
                    coast.stop()
                    Haptics.prepareDetents()
                    dragStart = position ?? tick(for: value)
                }
                let start = dragStart ?? 0
                move(to: start - gesture.translation.width / Self.spacing)
            }
            .onEnded { gesture in
                let from = position ?? tick(for: value)
                // The flick carries on about as far as the system predicts, then settles on a tick.
                let flick = -(gesture.predictedEndTranslation.width - gesture.translation.width) / Self.spacing
                let target = min(max((from + flick * 0.8).rounded(), 0), lastTick)
                dragStart = nil
                let distance = abs(target - from)
                guard distance > 0.001 else {
                    position = nil
                    return
                }
                let duration = min(max(0.22 + Double(distance) * 0.012, 0.22), 0.9)
                coast.run(duration: duration) { progress in
                    // Ease out: quick at first, like the finger's speed, then gently onto the tick.
                    let eased = 1 - pow(1 - progress, 3)
                    move(to: from + (target - from) * CGFloat(eased))
                } done: {
                    move(to: target)
                    position = nil
                }
            }
    }

    /// Moves the ruler, updating the value and clicking when it reaches a new tick.
    private func move(to tick: CGFloat) {
        let clamped = min(max(tick, 0), lastTick)
        position = clamped
        let next = snappedValue(at: clamped)
        guard next != value else { return }
        value = next
        Haptics.detent(major: (next / step).isMultiple(of: 5))
    }
}

/// The ticks in view, drawn where they fall this frame (fractions of a point included), so the
/// ruler glides rather than stepping a tick at a time.
private struct RulerTicks: View {
    /// The tick under the centre mark, fractional while moving.
    let position: CGFloat
    let lastTick: CGFloat
    /// The first tick's index on the ruler, so every fifth tick stays the major one.
    let firstTick: Int
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            let centre = size.width / 2
            let reach = centre / spacing + 1
            let first = Int(max(0, (position - reach).rounded(.down)))
            let last = Int(min(lastTick, (position + reach).rounded(.up)))
            guard first <= last else { return }
            for index in first...last {
                let major = (firstTick + index).isMultiple(of: 5)
                let height: CGFloat = major ? 18 : 10
                let x = centre + (CGFloat(index) - position) * spacing
                let rect = CGRect(x: x - 0.5, y: (size.height - height) / 2, width: 1, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(SBColor.inkSecondary.opacity(major ? 0.55 : 0.25)))
            }
        }
    }
}

/// Runs the ruler's coast after a flick, once per display frame (up to 120 a second).
@MainActor
final class RulerCoast: NSObject, ObservableObject {
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var duration: Double = 0
    private var onFrame: ((Double) -> Void)?
    private var onDone: (() -> Void)?

    func run(duration: Double, frame: @escaping (Double) -> Void, done: @escaping () -> Void) {
        stop()
        self.duration = duration
        onFrame = frame
        onDone = done
        start = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
        onDone = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let progress = min(max((link.targetTimestamp - start) / duration, 0), 1)
        onFrame?(progress)
        if progress >= 1 {
            let done = onDone
            stop()
            done?()
        }
    }
}
