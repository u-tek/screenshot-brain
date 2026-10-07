import Core
import DesignSystem
import Store
import SwiftUI

/// After the first triage: the score, and how it compares with what they reckoned.
struct ScoreMoment: View {
    var palette: LightPalette = .sampleTopScreenshots
    let score: Score
    /// Question 3's answer: how many of every ten saved things they reckoned got done.
    var guessedOutOfTen: Int?
    var onContinue: () -> Void = {}

    var body: some View {
        ZStack {
            LightField(.sweep(palette), drifts: true)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                SmallLabel("Your score")
                    .padding(.bottom, 8)
                ScoreView(done: score.done, total: score.total)
                    .padding(.bottom, 28)
                MistHeadline(headline, size: 32, alignment: .leading)
                    .padding(.bottom, 12)
                if let comparison {
                    MistBody(comparison, alignment: .leading)
                }
                Spacer()
                SmallLabel("Drops never count against you.")
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                ActionBar("Keep going", palette: palette, action: onContinue)
                    .padding(.horizontal, -12)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
        }
    }

    private var headline: String {
        if score.total == 0 { return "A clean slate. **Let's keep it moving.**" }
        if score.done == 0 { return "\(score.total) kept, none done. **We can fix that.**" }
        return "\(score.done) done already. **Nice start.**"
    }

    /// "You reckoned 3 in 10. **It's 1 in 10.**"
    private var comparison: String? {
        guard let guessed = guessedOutOfTen, score.total > 0 else { return nil }
        let actual = Int((Double(score.done) / Double(score.total) * 10).rounded())
        if actual == guessed { return "You reckoned \(guessed) in 10. **Spot on.**" }
        return "You reckoned \(guessed) in 10. **It's \(actual) in 10.**"
    }
}
