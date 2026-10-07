import DesignSystem
import SwiftUI

/// The north star's question screen: a chip at the top, light and the glass lens near the centre,
/// a small grey label, a light/bold headline, short subtext, the answer, then the action bar.
struct QuestionLayout<Answer: View>: View {
    let label: String
    let headline: String
    let subtext: String
    let light: LightComposition
    let palette: LightPalette
    /// The quiet counter above the action bar.
    let footnote: String
    var actionTitle = "Next"
    var onSkip: (() -> Void)?
    let onNext: () -> Void
    @ViewBuilder let answer: () -> Answer

    var body: some View {
        GeometryReader { proxy in
            // iPhone SE: a smaller lens and headline so everything fits without scrolling.
            let compact = proxy.size.height < 620
            ZStack {
                LightField(light, drifts: true)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Group {
                        if let onSkip {
                            Button(action: onSkip) {
                                Chip("Skip for now", closable: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(height: 33)
                        }
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 8)
                    GlassLens(diameter: compact ? 80 : 124)
                    Spacer(minLength: 8)

                    SmallLabel(label)
                        .padding(.bottom, 10)
                    MistHeadline(headline, size: compact ? 28 : 32)
                        .padding(.horizontal, 28)
                    MistBody(subtext)
                        .padding(.top, 10)
                        .padding(.horizontal, 36)

                    Spacer(minLength: compact ? 12 : 20)
                    answer()
                    Spacer(minLength: compact ? 12 : 20)

                    SmallLabel(footnote)
                        .monospacedDigit()
                        .padding(.bottom, 12)
                        .accessibilityAddTraits(.updatesFrequently)
                    ActionBar(actionTitle, palette: palette, action: onNext)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// Chips to pick one answer from. Picking carries the screen's single accent.
struct ChoiceGrid<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value?

    var body: some View {
        FlowLayout(spacing: 10, rowSpacing: 10) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                ChoiceChip(option.title, isSelected: selection == option.value) {
                    Haptics.selection()
                    withAnimation(SBMotion.snappy) {
                        selection = option.value
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }
}
