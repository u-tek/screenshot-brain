import Actions
import Core
import DesignSystem
import Media
import Store
import SwiftUI

/// The swipe deck. Right is still want, left is drop, up is done. Cards tilt and wash with colour
/// as they're dragged; the light behind is the top card's own, and it warms for keep, fades to
/// grey mist for drop, and pulses the accent once for done.
public struct TriageDeck: View {
    @ObservedObject private var model: TriageModel
    private let label: String
    private let onFinish: () -> Void
    @State private var drag: CGSize = .zero
    /// True while a decided card flies off, so a second tap can't decide the card behind it unseen.
    @State private var isCommitting = false
    @State private var pulse = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sbBottomClearance) private var bottomClearance

    /// How far a card must travel (or be flung) to count.
    private static let threshold: CGFloat = 110

    public init(model: TriageModel, label: String = "Recap", onFinish: @escaping () -> Void) {
        self.model = model
        self.label = label
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            TriageLight(palette: palette(for: model.current), warmth: warmth, fade: fade, pulse: pulse)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                deck
                    .padding(.horizontal, SBSpace.gutter)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .frame(maxHeight: .infinity)

                controls
                    .padding(.horizontal, SBSpace.gutter)
                    .padding(.bottom, bottomClearance > 0 ? bottomClearance + 12 : 12)
            }
        }
        .onChange(of: model.isFinished) { finished in
            if finished { onFinish() }
        }
    }

    // MARK: Parts

    private var header: some View {
        SBNavHeader(title: label, leading: .x, leadingLabel: "Finish later", onLeading: onFinish) {
            HStack(spacing: 12) {
                if model.canUndo {
                    SBCircleButton(.system("arrow.uturn.backward"), label: "Undo") {
                        Haptics.selection()
                        withAnimation(SBMotion.snappy) { model.undo() }
                    }
                    .transition(.opacity)
                }
                if !model.isFinished {
                    SBLabel("\(model.position + 1) / \(model.cards.count)")
                        .monospacedDigit()
                }
            }
        }
    }

    private var deck: some View {
        ZStack {
            ForEach(Array(model.visible.enumerated().reversed()), id: \.element.id) { depth, card in
                layer(card, depth: depth)
            }
        }
    }

    /// A card at `depth` in the stack: 0 is the top card, the one being dragged.
    private func layer(_ card: TriageCard, depth: Int) -> some View {
        let isTop = depth == 0
        let scale: CGFloat = 1 - CGFloat(depth) * 0.05
        let lift: CGFloat = CGFloat(depth) * -14
        let offset: CGSize = isTop ? drag : .zero
        let tilt: Double = isTop && !reduceMotion ? Double(drag.width / 22) : 0
        return TriageCardView(card: card, direction: isTop ? direction : nil, strength: isTop ? strength : 0)
            .scaleEffect(scale, anchor: .top)
            .offset(y: lift)
            .opacity(depth == 2 ? 0.6 : 1)
            .offset(offset)
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .gesture(dragGesture)
            .allowsHitTesting(isTop)
            .accessibilityHidden(!isTop)
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text("Still want")) { commit(.keep) }
            .accessibilityAction(named: Text("Done")) { commit(.done) }
            .accessibilityAction(named: Text("Drop")) { commit(.drop) }
            .zIndex(Double(3 - depth))
    }

    private var controls: some View {
        SBDecisionRow(onDrop: { commit(.drop) }, onKeep: { commit(.keep) }, onDone: { commit(.done) })
            .disabled(model.isFinished)
            .opacity(model.isFinished ? 0 : 1)
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                drag = value.translation
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation
                if let decision = decision(for: value.translation, predicted: predicted) {
                    commit(decision)
                } else {
                    withAnimation(SBMotion.snappy) { drag = .zero }
                }
            }
    }

    private func decision(for translation: CGSize, predicted: CGSize) -> TriageDecision? {
        let x = abs(translation.width) > abs(predicted.width) ? translation.width : predicted.width
        let y = abs(translation.height) > abs(predicted.height) ? translation.height : predicted.height
        if -y > Self.threshold, -y > abs(x) { return .done }
        if x > Self.threshold { return .keep }
        if x < -Self.threshold { return .drop }
        return nil
    }

    private func commit(_ decision: TriageDecision) {
        guard !model.isFinished, !isCommitting else { return }
        switch decision {
        case .keep: Haptics.keep()
        case .done: Haptics.done()
        case .drop: Haptics.drop()
        }
        let exit: CGSize
        switch decision {
        case .keep: exit = CGSize(width: 640, height: drag.height + 40)
        case .drop: exit = CGSize(width: -640, height: drag.height + 40)
        case .done: exit = CGSize(width: drag.width, height: -900)
        }
        if reduceMotion {
            drag = .zero
            withAnimation(.easeInOut(duration: 0.2)) { model.decide(decision) }
            return
        }
        isCommitting = true
        withAnimation(SBMotion.fling) { drag = exit }
        if decision == .done {
            withAnimation(.easeOut(duration: 0.18)) { pulse = 1 }
            withAnimation(.easeIn(duration: 0.7).delay(0.18)) { pulse = 0 }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.decide(decision)
                drag = .zero
            }
            isCommitting = false
        }
    }

    // MARK: Light

    private var direction: TriageDecision? {
        if -drag.height > abs(drag.width), drag.height < -12 { return .done }
        if drag.width > 12 { return .keep }
        if drag.width < -12 { return .drop }
        return nil
    }

    private var strength: Double {
        let distance = max(abs(drag.width), direction == .done ? -drag.height : 0)
        return min(Double(distance / Self.threshold), 1)
    }

    private var warmth: Double {
        direction == .keep ? strength : 0
    }

    private var fade: Double {
        direction == .drop ? strength : 0
    }

    private func palette(for card: TriageCard?) -> LightPalette {
        guard let item = card?.item else { return .sampleTopScreenshots }
        return .item(category: item.category, colors: item.palette, isSafeToDisplay: item.isSafeToDisplay)
    }
}

/// The light behind the deck: the warm ground with one soft glow of the card's kind under it. It
/// warms for keep, dims for drop, and pulses warm white once for done.
struct TriageLight: View {
    let palette: LightPalette
    /// 0...1 towards keep: the light warms.
    let warmth: Double
    /// 0...1 towards drop: the light dims.
    let fade: Double
    /// 0...1: the pulse on done.
    let pulse: Double

    var body: some View {
        ZStack {
            SBGround()
            SBLight(Color(rgb: palette.color(at: 1)), width: 380, height: 460, opacity: 0.22 * (1 - fade * 0.8), blur: 90)
                .offset(y: 60)
                .animation(SBMotion.settle, value: palette)
            SBLight(SBRamp.r4, width: 380, height: 460, opacity: warmth * 0.3, blur: 90)
                .offset(y: 60)
            SBLight(SBColor.accent, width: 300, height: 300, opacity: pulse * 0.35, blur: 80)
                .offset(y: -40)
        }
    }
}

/// One card: the screenshot filling the upper part, lit by its kind, and a folder panel with the
/// kind, the title, when, and the date or the suggested action. Groups show as a stack.
struct TriageCardView: View {
    let card: TriageCard
    var direction: TriageDecision?
    var strength: Double = 0

    var body: some View {
        let item = card.item
        let shape = RoundedRectangle(cornerRadius: SBRadius.objectCard, style: .continuous)
        let kind = SBKind(item.category)
        ZStack {
            if card.groupSize > 1 {
                StackEdge(shape: shape, depth: 2)
                StackEdge(shape: shape, depth: 1)
            }
            ZStack(alignment: .bottom) {
                // The screenshot fills the card above the panel, lit by its kind behind.
                ZStack {
                    kind.deep
                    SBLight(kind.core, width: 300, height: 360, opacity: 0.55, blur: 60)
                    AssetImage(item.assetLocalID, maxPixelSize: 900)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                    LinearGradient(colors: [SBColor.shade(0.12), .clear, .clear, SBColor.shade(0.5)], startPoint: .top, endPoint: .bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                panel(item, kind: kind)
            }
            .clipShape(shape)
            .overlay {
                wash.clipShape(shape).allowsHitTesting(false)
            }
            .overlay(shape.strokeBorder(SBColor.warm(0.12), lineWidth: 1))
            .contentShape(shape)
        }
    }

    /// The folder panel: kind, name, when, and the date or what to do, low down.
    private func panel(_ item: ScreenshotItem, kind: SBKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(kind.core)
                        .frame(width: 6, height: 6)
                        .shadow(color: kind.core, radius: 4)
                    SBLabel(CategoryName.title(item.category), dim: false)
                }
                Text(item.title ?? "Something you saved")
                    .sbText(.title)
                    .lineLimit(2)
                Text(meta(item))
                    .sbText(.body)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            HStack(alignment: .firstTextBaseline) {
                if let due = item.dueDate {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(due.formatted(.dateTime.day()))
                            .sbText(.numL)
                        Text(due.formatted(.dateTime.month(.abbreviated)))
                            .sbText(.unit)
                    }
                } else {
                    SBLabel("Saved \(item.createdAt.formatted(.relative(presentation: .named)))")
                }
                Spacer(minLength: 8)
                if card.groupSize > 1 {
                    SBLabel("\(card.groupSize) screenshots")
                } else if let action = ItemAction.suggested(for: item) {
                    SBLabel(action.title)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22 + 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
        // Its own height, not the card's: the screenshot has the rest.
        .fixedSize(horizontal: false, vertical: true)
        .background(SBFolderPanelShape().fill(SBColor.surface))
    }

    private func meta(_ item: ScreenshotItem) -> String {
        var parts: [String] = []
        if let due = item.dueDate {
            parts.append(due.formatted(.dateTime.weekday(.wide)))
            parts.append(due.formatted(.dateTime.hour().minute()))
        } else {
            parts.append("Saved \(item.createdAt.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var wash: some View {
        switch direction {
        case .keep?:
            LinearGradient(colors: [SBColor.accent.opacity(0.35 * strength), .clear], startPoint: .trailing, endPoint: .leading)
                .overlay(alignment: .topLeading) {
                    Text("Still want")
                        .font(.system(size: 15))
                        .foregroundStyle(SBColor.ground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(SBColor.accent))
                        .padding(.top, 24)
                        .padding(.leading, 20)
                        .opacity(strength)
                }
        case .drop?:
            SBColor.ground.opacity(0.55 * strength)
                .overlay(alignment: .topTrailing) {
                    DropMark(size: 52).padding(.top, 24).padding(.trailing, 20).opacity(strength)
                }
        case .done?:
            LinearGradient(colors: [SBColor.accent.opacity(0.3 * strength), .clear], startPoint: .top, endPoint: .center)
                .overlay(alignment: .top) {
                    DoneMark(size: 56).padding(.top, 32).opacity(strength)
                }
        case nil:
            Color.clear
        }
    }
}

/// The edge of a card behind, peeking out above: this card stands for a group of near-duplicates.
private struct StackEdge: View {
    let shape: RoundedRectangle
    let depth: Int

    var body: some View {
        shape
            .fill(SBColor.surface2)
            .overlay(shape.strokeBorder(SBColor.warm(0.12), lineWidth: 1))
            .scaleEffect(1 - CGFloat(depth) * 0.04, anchor: .top)
            .offset(y: CGFloat(depth) * -10)
            .accessibilityHidden(true)
    }
}

/// Category names as people say them.
public enum CategoryName {
    public static func title(_ category: ItemCategory) -> String {
        switch category {
        case .place: "Places"
        case .event: "Events"
        case .product: "Products"
        case .recipe: "Recipes"
        case .reference: "Reference"
        case .other: "Not sure yet"
        }
    }
}
