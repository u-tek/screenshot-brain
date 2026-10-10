import DesignSystem
import SwiftUI

/// The one-screen pitch. The lens slides in from the left edge over a pocket of the user's
/// light, its rings draw themselves round it, and the kinds of things people save ride the outer
/// ring up past it, one at a time. The two rings turn idly in opposite directions.
struct WelcomeScreen: View {
    var palette: LightPalette = .sampleTopScreenshots
    var onContinue: () -> Void = {}
    @State private var showsText = false
    @State private var showsAction = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lightIsStill) private var lightIsStill

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppMark()
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            Spacer()
            Group {
                SmallLabel("For the things you meant to do")
                    .padding(.bottom, 10)
                MistHeadline("You saved it\n**for a reason.**", size: 34, alignment: .leading)
                    .padding(.bottom, 28)
            }
            .opacity(showsText ? 1 : 0)
            .offset(y: showsText ? 0 : 18)
            ActionBar("Show me", palette: palette, action: onContinue)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .opacity(showsAction ? 1 : 0)
                .offset(y: showsAction ? 0 : 24)
        }
        .padding(.horizontal, 24)
        .background {
            ZStack {
                LightField(.passage(palette), drifts: true)
                OrbitDial(isStill: reduceMotion || lightIsStill)
            }
            .ignoresSafeArea()
        }
        .onAppear(perform: enter)
    }

    /// The words follow the lens in: the headline as the rings close, the button just after.
    private func enter() {
        guard !reduceMotion, !lightIsStill else {
            showsText = true
            showsAction = true
            return
        }
        withAnimation(SBMotion.reveal.delay(0.7)) { showsText = true }
        withAnimation(SBMotion.reveal.delay(1.0)) { showsAction = true }
    }
}

/// The lens, its two rings and the things riding the outer one. Everything here moves on one
/// clock, at the display's frame rate.
private struct OrbitDial: View {
    let isStill: Bool
    @State private var start = Date()

    /// The things people screenshot, in no particular order. Enough that the list doesn't come
    /// round again while someone's reading the screen.
    static let things = [
        "That ramen place", "That gig on Friday", "Those sneakers", "The pasta recipe",
        "That rooftop bar", "The Airbnb in Byron", "That book everyone's reading", "The film Sam recommended",
        "The playlist from Saturday", "That jacket on sale", "The brunch spot", "That podcast episode",
        "The comedy show", "That hiking trail", "The new album", "That vintage lamp",
        "The banana bread recipe", "The Sunday market", "The festival lineup", "That serum",
        "The flights to Tokyo", "The wine bar in Newtown", "That show to binge", "The presale code",
        "That couch you wanted", "The dumpling place", "That article to read", "The gym timetable",
        "The art exhibition", "That cocktail recipe", "The camping spot", "That plant shop",
        "The running shoes", "The dinner party menu", "That pottery class", "The beach cafe",
        "That gift idea", "The trivia night", "That road trip route", "The bakery near work",
        "The cheap Bali flights", "That candle", "The open mic night", "That chilli oil recipe",
    ]

    /// The gap between neighbouring things (and ticks) on the outer ring.
    private static let spacing = Angle.degrees(360.0 / 28)
    /// Each thing holds in focus, then the ring turns one step.
    private static let hold = 1.5
    private static let turn = 0.7
    /// The rings drawing in and the lens arriving.
    private static let entrance = 1.6
    /// Things show this far either side of the focus.
    private static let reach = 50.0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let lensDiameter = size.width * 0.88
            let center = CGPoint(x: size.width * 0.02, y: size.height * 0.37)
            let radius = lensDiameter * 1.16 / 2

            TimelineView(.animation(minimumInterval: nil, paused: isStill)) { timeline in
                let elapsed = isStill ? 1_000 : timeline.date.timeIntervalSince(start)
                let entered = Self.ease(min(max(elapsed / Self.entrance, 0), 1))
                let step = isStill ? 0 : Self.step(at: elapsed - Self.entrance)

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        Self.drawRings(in: &context, center: center, radius: radius, lensRadius: lensDiameter / 2, step: step, elapsed: elapsed, entered: entered)
                    }
                    GlassLens(diameter: lensDiameter)
                        .position(center)
                        .offset(x: -(1 - entered) * size.width * 0.6)
                        .opacity(entered)
                    labels(center: center, radius: radius, width: size.width, step: step, entered: entered)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("That ramen place, that gig on Friday, those sneakers"))
        .onAppear { start = Date() }
    }

    /// Where the outer ring is, in steps: whole numbers while a thing is held in focus, eased in
    /// between.
    static func step(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        let period = hold + turn
        let whole = (time / period).rounded(.down)
        let into = time - whole * period
        return whole + ease(min(max((into - hold) / turn, 0), 1))
    }

    private static func ease(_ x: Double) -> Double {
        x * x * (3 - 2 * x)
    }

    /// The outer ring with its ticks, turning up (anticlockwise) a step at a time with the
    /// things; the inner one dashed, turning steadily the other way.
    private static func drawRings(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, lensRadius: CGFloat, step: Double, elapsed: Double, entered: Double) {
        let full = Double.pi * 2
        // The outer ring draws itself round from the top as the lens arrives.
        var outer = Path()
        outer.addArc(center: center, radius: radius, startAngle: .radians(-.pi / 2), endAngle: .radians(-.pi / 2 + full * entered), clockwise: false)
        context.stroke(outer, with: .color(SBColor.hairline), lineWidth: 0.75)

        // The inner ring, between the lens and the outer one, turning clockwise.
        let innerRadius = (radius + lensRadius) / 2
        var inner = Path()
        inner.addArc(center: center, radius: innerRadius, startAngle: .zero, endAngle: .radians(full * entered), clockwise: false)
        let spin = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(elapsed * 0.14))
            .translatedBy(x: -center.x, y: -center.y)
        context.stroke(inner.applying(spin), with: .color(SBColor.hairline.opacity(0.8)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round, dash: [1.5, 7]))

        // A tick for every slot on the outer ring; the one at the focus swells into the dot.
        let count = Int((360 / spacing.degrees).rounded())
        for index in 0..<count {
            let degrees = (Double(index) - step) * spacing.degrees
            let angle = degrees * .pi / 180
            // Ticks appear as the ring reaches them.
            let reached = (angle + .pi / 2).truncatingRemainder(dividingBy: full)
            let along = reached < 0 ? reached + full : reached
            guard along <= full * entered else { continue }
            let focus = max(0, 1 - abs(wrapped(degrees)) / (spacing.degrees * 0.6))
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let diameter = 3 + 6 * focus
            let dot = Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter))
            context.fill(dot, with: .color(SBColor.hairline.opacity(1 - focus)))
            context.fill(dot, with: .color(SBColor.accent.opacity(focus)))
        }

        // The hairline from the dot to the thing in focus.
        let settled = 1 - min(1, abs(step - step.rounded()) * 3)
        var line = Path()
        line.move(to: CGPoint(x: center.x + radius + 8, y: center.y))
        line.addLine(to: CGPoint(x: center.x + radius + 28, y: center.y))
        context.stroke(line, with: .color(SBColor.accent.opacity(0.7 * settled * entered)), lineWidth: 1)
    }

    /// Degrees into -180...180.
    private static func wrapped(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    /// The things near the focus, each riding its slot on the ring: fading in from below,
    /// brightest at the focus, fading out above.
    private func labels(center: CGPoint, radius: CGFloat, width screenWidth: CGFloat, step: Double, entered: Double) -> some View {
        let span = Int((Self.reach / Self.spacing.degrees).rounded(.up))
        let focusIndex = Int(step.rounded(.down))
        let shown = max(0, (entered - 0.5) * 2)
        let labelRadius = radius + 36
        // As wide as the screen allows at the focus, the widest point of the arc.
        let width = max(120, screenWidth - (center.x + labelRadius) - 12)
        return ForEach((focusIndex - span)...(focusIndex + span + 1), id: \.self) { slot in
            let degrees = (Double(slot) - step) * Self.spacing.degrees
            let angle = degrees * .pi / 180
            let focus = max(0, 1 - abs(Double(slot) - step) * 1.4)
            let edge = max(0, 1 - pow(abs(degrees) / Self.reach, 2))
            let things = Self.things
            let text = things[((slot % things.count) + things.count) % things.count]
            Text(text)
                .font(SBFont.body(13 + 2 * focus, weight: focus > 0.5 ? .semibold : .regular))
                .foregroundStyle(SBColor.ink.opacity((0.4 * edge + 0.6 * focus) * shown))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: width, alignment: .leading)
                .position(x: center.x + labelRadius * cos(angle) + width / 2, y: center.y + labelRadius * sin(angle))
        }
    }
}
