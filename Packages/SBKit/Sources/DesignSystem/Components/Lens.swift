import SwiftUI

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
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !tilts)) { _ in
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
public struct TickRuler: View {
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let spokenValue: (Int) -> String
    @State private var dragStart: Int?

    public init(value: Binding<Int>, in range: ClosedRange<Int>, step: Int, spokenValue: @escaping (Int) -> String = { "\($0)" }) {
        self._value = value
        self.range = range
        self.step = step
        self.spokenValue = spokenValue
    }

    public var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 8
            let count = Int(proxy.size.width / spacing) + 2
            let offset = CGFloat(value / step % 5) * spacing
            ZStack {
                HStack(spacing: spacing - 1) {
                    ForEach(0..<count, id: \.self) { index in
                        let major = (index + value / step) % 5 == 0
                        Capsule()
                            .fill(SBColor.inkSecondary.opacity(major ? 0.55 : 0.25))
                            .frame(width: 1, height: major ? 18 : 10)
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .offset(x: -offset)
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
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        let steps = Int((-gesture.translation.width / spacing).rounded())
                        let next = min(max(start + steps * step, range.lowerBound), range.upperBound)
                        if next != value {
                            value = next
                            if (next / step).isMultiple(of: 5) { Haptics.tick() }
                        }
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityValue(Text(spokenValue(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}
