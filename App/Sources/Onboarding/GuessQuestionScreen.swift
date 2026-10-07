import DesignSystem
import SwiftUI

/// Question 1 of the guessing questions, asked while the scan runs.
///
/// The live "screenshots read" count is deliberately not shown on this question: it's the number
/// being guessed, and seeing it tick up would anchor the guess.
struct GuessQuestionScreen: View {
    var palette: LightPalette = .sampleTopScreenshots
    var onNext: (Int) -> Void = { _ in }
    var onSkip: () -> Void = {}
    @State private var guess = 150

    var body: some View {
        ZStack {
            LightField(.sweep(palette))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Button(action: onSkip) {
                    Chip("Skip for now", closable: true)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                Spacer(minLength: 12)
                GlassLens(diameter: 128)
                Spacer(minLength: 12)

                SmallLabel("Question 1")
                    .padding(.bottom, 10)
                MistHeadline("How many **screenshots** do you reckon you took?", size: 32)
                    .padding(.horizontal, 28)
                MistBody("Just the last two months. **No peeking.**")
                    .padding(.top, 12)

                Spacer(minLength: 16)

                Text("\(guess)")
                    .font(SBFont.number(64))
                    .monospacedDigit()
                    .foregroundStyle(SBColor.ink)
                TickRuler(value: $guess, in: 0...5000, step: 10)
                    .padding(.horizontal, 48)
                    .padding(.top, 4)
                    .accessibilityLabel(Text("Your guess"))

                Spacer(minLength: 16)

                SmallLabel("Reading your screenshots on this iPhone")
                    .padding(.bottom, 12)
                ActionBar("Next", palette: palette) { onNext(guess) }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }
}
