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
    @State private var pulse = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                deck
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxHeight: .infinity)

                controls
                    .padding(.bottom, 12)
            }
        }
        .onChange(of: model.isFinished) { finished in
            if finished { onFinish() }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            SmallLabel(model.isFinished ? label : "\(label) · \(model.position + 1) of \(model.cards.count)")
                .monospacedDigit()
            Spacer()
            if model.canUndo {
                Button {
                    Haptics.selection()
                    withAnimation(SBMotion.snappy) { model.undo() }
                } label: {
                    Chip("Undo")
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            Button(action: onFinish) {
                Chip("Finish later", closable: true)
            }
            .buttonStyle(.plain)
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
        HStack(spacing: 22) {
            Button { commit(.drop) } label: { DropMark(size: 58) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Drop"))
            Button { commit(.keep) } label: {
                Text("Still want")
                    .font(SBFont.body(16, weight: .semibold))
                    .foregroundStyle(SBColor.ink)
                    .padding(.horizontal, 26)
                    .frame(height: 58)
                    .sbGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            Button { commit(.done) } label: { DoneMark(size: 58) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Done"))
        }
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
        guard !model.isFinished else { return }
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

/// The light behind the deck.
struct TriageLight: View {
    let palette: LightPalette
    /// 0...1 towards keep: the light warms.
    let warmth: Double
    /// 0...1 towards drop: the light fades to grey mist.
    let fade: Double
    /// 0...1: the accent pulse on done.
    let pulse: Double

    private static let warm = LightPalette.category(.place)
    private static let accent = LightPalette(colors: [RGB(hex: 0xFF6A3D), RGB(hex: 0xFFA27F), RGB(hex: 0xFFD2BD)])

    var body: some View {
        ZStack {
            LightField(.sweep(palette), drifts: true)
                .saturation(1 - fade * 0.9)
                .opacity(1 - fade * 0.55)
                .animation(SBMotion.settle, value: palette)
            LightField(.sweep(Self.warm), ground: false, grain: 0)
                .opacity(warmth * 0.55)
            LightField(.glow(Self.accent).shifted(down: 0.25), ground: false, grain: 0)
                .opacity(pulse * 0.5)
        }
    }
}

/// One card: the screenshot itself in the upper part, framed by its own light, and a frosted
/// panel with the title, when it was saved and the suggested action. Groups show as a stack.
struct TriageCardView: View {
    let card: TriageCard
    var direction: TriageDecision?
    var strength: Double = 0

    var body: some View {
        let item = card.item
        let shape = FolderTabShape(tabWidth: 124, tabHeight: 30)
        let palette = LightPalette.item(category: item.category, colors: item.palette, isSafeToDisplay: item.isSafeToDisplay)
        ZStack {
            if card.groupSize > 1 {
                StackEdge(shape: shape, palette: palette, depth: 2)
                StackEdge(shape: shape, palette: palette, depth: 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(CategoryName.title(item.category))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SBColor.ink.opacity(0.8))
                    .padding(.leading, 18)
                    .frame(height: 30)

                AssetImage(item.assetLocalID, maxPixelSize: 900)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 1))
                    .padding(.horizontal, 10)
                    .padding(.top, 4)

                panel(item)
                    .padding(8)
            }
            .background {
                LightField(.bloom(palette).shifted(down: 0.1), grain: 0.04)
                    .clipShape(shape)
            }
            .overlay {
                wash.clipShape(shape).allowsHitTesting(false)
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 0.75))
            .contentShape(shape)
        }
    }

    private func panel(_ item: ScreenshotItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallLabel(meta(item))
            Text(item.title ?? "Something you saved")
                .font(SBFont.headline(22, bold: true))
                .foregroundStyle(SBColor.ink)
                .lineLimit(2)
            if let action = ItemAction.suggested(for: item) {
                HStack(spacing: 6) {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 11, weight: .medium))
                    Text(action.title)
                        .font(.system(size: 12))
                }
                .foregroundStyle(SBColor.ink.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .sbGlass(in: Capsule(), style: .clear)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sbGlass(in: RoundedRectangle(cornerRadius: SBRadius.card - 8, style: .continuous))
    }

    private func meta(_ item: ScreenshotItem) -> String {
        var parts = ["Saved \(item.createdAt.formatted(.relative(presentation: .named)))"]
        if let due = item.dueDate {
            parts.append(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        }
        if card.groupSize > 1 {
            parts.append("\(card.groupSize) screenshots")
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
                        .font(SBFont.body(15, weight: .semibold))
                        .foregroundStyle(SBColor.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .sbGlass(in: Capsule())
                        .padding(.top, 44)
                        .padding(.leading, 18)
                        .opacity(strength)
                }
        case .drop?:
            Color(white: 0.85).opacity(0.5 * strength)
                .overlay(alignment: .topTrailing) {
                    DropMark(size: 52).padding(.top, 44).padding(.trailing, 18).opacity(strength)
                }
        case .done?:
            LinearGradient(colors: [SBColor.accent.opacity(0.3 * strength), .clear], startPoint: .top, endPoint: .center)
                .overlay(alignment: .top) {
                    DoneMark(size: 56).padding(.top, 52).opacity(strength)
                }
        case nil:
            Color.clear
        }
    }
}

/// The edge of a card behind, peeking out above: this card stands for a group of near-duplicates.
private struct StackEdge: View {
    let shape: FolderTabShape
    let palette: LightPalette
    let depth: Int

    var body: some View {
        LightField(.bloom(palette), grain: 0)
            .opacity(0.5)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 0.75))
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
