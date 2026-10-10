import Core
import DesignSystem
import Store
import SwiftUI

/// The four questions, asked while the scan runs. Each answer is saved as it's given, so
/// a crash or a new phone picks up at the first question still unanswered.
struct QuestionsFlow: View {
    @EnvironmentObject private var model: AppModel
    @State private var index: Int?

    var body: some View {
        let current = index ?? Self.firstUnanswered(model.answers)
        ZStack {
            question(current)
                .id(current)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)), removal: .opacity))
        }
    }

    @ViewBuilder
    private func question(_ number: Int) -> some View {
        let footnote = Self.footnote(isScanning: model.isScanning)
        switch number {
        case 1:
            CountQuestion(palette: model.palette, footnote: footnote, initial: model.answers.guessedScreenshotCount ?? 150) { guess in
                model.updateAnswers { $0.guessedScreenshotCount = guess }
                next(after: 1)
            } onSkip: { finish() }
        case 2:
            TopCategoryQuestion(palette: model.palette, footnote: footnote, initial: model.answers.guessedTopCategory) { category in
                model.updateAnswers { $0.guessedTopCategory = category }
                next(after: 2)
            } onSkip: { finish() }
        case 3:
            DoneQuestion(palette: model.palette, footnote: footnote, initial: model.answers.guessedDoneCount) { outOfTen in
                model.updateAnswers { $0.guessedDoneCount = outOfTen }
                next(after: 3)
            } onSkip: { finish() }
        default:
            WindDownQuestion(palette: model.palette, footnote: footnote, initial: model.answers.windDownMinutes ?? 22 * 60) { minutes in
                model.updateAnswers {
                    $0.windDownMinutes = minutes
                    $0.recapMinutes = minutes
                }
                finish()
            } onSkip: { finish() }
        }
    }

    private func next(after number: Int) {
        withAnimation(SBMotion.settle) {
            index = number + 1
        }
    }

    private func finish() {
        model.finishQuestions()
    }

    static func firstUnanswered(_ answers: OnboardingAnswers) -> Int {
        if answers.guessedScreenshotCount == nil { return 1 }
        if answers.guessedTopCategory == nil { return 2 }
        if answers.guessedDoneCount == nil { return 3 }
        return 4
    }

    /// What the scan is up to. Never a count: how many screenshots there are is the first
    /// question's answer and the Reveal's opening line, and showing it here would give both away.
    static func footnote(isScanning: Bool) -> String {
        isScanning ? "Reading your screenshots on this iPhone" : "All read. Your Reveal is ready"
    }
}

// MARK: - The questions

struct CountQuestion: View {
    let palette: LightPalette
    let footnote: String
    @State var guess: Int
    let onNext: (Int) -> Void
    let onSkip: () -> Void

    init(palette: LightPalette, footnote: String, initial: Int, onNext: @escaping (Int) -> Void, onSkip: @escaping () -> Void = {}) {
        self.palette = palette
        self.footnote = footnote
        self._guess = State(initialValue: initial)
        self.onNext = onNext
        self.onSkip = onSkip
    }

    var body: some View {
        QuestionLayout(
            label: "Question 1",
            headline: "How many **screenshots** do you reckon you took?",
            subtext: "Just the last two months. **No peeking.**",
            light: .sweep(palette),
            palette: palette,
            footnote: footnote,
            onSkip: onSkip,
            onNext: { onNext(guess) }
        ) {
            VStack(spacing: 4) {
                Text("\(guess)")
                    .font(SBFont.number(64))
                    .monospacedDigit()
                    .foregroundStyle(SBColor.ink)
                    .accessibilityHidden(true)
                TickRuler(value: $guess, in: 0...5000, step: 10)
                    .padding(.horizontal, 48)
                    .accessibilityLabel(Text("Your guess"))
            }
        }
    }
}

struct TopCategoryQuestion: View {
    let palette: LightPalette
    let footnote: String
    @State var choice: ItemCategory?
    let onNext: (ItemCategory?) -> Void
    let onSkip: () -> Void

    init(palette: LightPalette, footnote: String, initial: ItemCategory?, onNext: @escaping (ItemCategory?) -> Void, onSkip: @escaping () -> Void = {}) {
        self.palette = palette
        self.footnote = footnote
        self._choice = State(initialValue: initial)
        self.onNext = onNext
        self.onSkip = onSkip
    }

    var body: some View {
        QuestionLayout(
            label: "Question 2",
            headline: "What do you save **the most?**",
            subtext: "Go with your gut.",
            light: .sweep(palette.reversed).mirrored(),
            palette: palette,
            footnote: footnote,
            onSkip: onSkip,
            onNext: { onNext(choice) }
        ) {
            ChoiceGrid(options: [
                (ItemCategory.message, "Messages"),
                (.place, "Places to go"),
                (.event, "Gigs and events"),
                (.product, "Things to buy"),
                (.recipe, "Recipes"),
                (.post, "Memes and posts"),
                (.watch, "Shows and films"),
                (.listen, "Music"),
                (.read, "Books"),
                (.travel, "Trips"),
            ], selection: $choice)
        }
    }
}

struct DoneQuestion: View {
    /// Answers as "out of every ten saved things".
    static let options: [(value: Int, title: String)] = [
        (1, "Hardly any"),
        (3, "A few"),
        (5, "About half"),
        (8, "Most of them"),
    ]

    let palette: LightPalette
    let footnote: String
    @State var choice: Int?
    let onNext: (Int?) -> Void
    let onSkip: () -> Void

    init(palette: LightPalette, footnote: String, initial: Int?, onNext: @escaping (Int?) -> Void, onSkip: @escaping () -> Void = {}) {
        self.palette = palette
        self.footnote = footnote
        self._choice = State(initialValue: initial)
        self.onNext = onNext
        self.onSkip = onSkip
    }

    var body: some View {
        QuestionLayout(
            label: "Question 3",
            headline: "How many of those have you **actually done?**",
            subtext: "The restaurants, the gigs, the recipes. **Honestly.**",
            light: .sweep(palette.reversed),
            palette: palette,
            footnote: footnote,
            onSkip: onSkip,
            onNext: { onNext(choice) }
        ) {
            ChoiceGrid(options: Self.options, selection: $choice)
        }
    }
}

struct WindDownQuestion: View {
    let palette: LightPalette
    let footnote: String
    /// Minutes after 5pm, so the ruler runs from early evening to past midnight.
    @State var minutesAfterFive: Int
    let onNext: (Int) -> Void
    let onSkip: () -> Void

    init(palette: LightPalette, footnote: String, initial: Int, onNext: @escaping (Int) -> Void, onSkip: @escaping () -> Void = {}) {
        self.palette = palette
        self.footnote = footnote
        self._minutesAfterFive = State(initialValue: Self.rulerValue(minutesAfterMidnight: initial))
        self.onNext = onNext
        self.onSkip = onSkip
    }

    var body: some View {
        QuestionLayout(
            label: "Question 4",
            headline: "What time do you **wind down?**",
            subtext: "That's when your recap turns up. One a night, tops.",
            light: .sweep(palette).mirrored(),
            palette: palette,
            footnote: footnote,
            actionTitle: "That's everything",
            onSkip: onSkip,
            onNext: { onNext(Self.minutesAfterMidnight(rulerValue: minutesAfterFive)) }
        ) {
            VStack(spacing: 4) {
                Text(Self.timeText(Self.minutesAfterMidnight(rulerValue: minutesAfterFive)))
                    .font(SBFont.number(64))
                    .monospacedDigit()
                    .foregroundStyle(SBColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityHidden(true)
                TickRuler(value: $minutesAfterFive, in: 0...(9 * 60), step: 15) { value in
                    Self.timeText(Self.minutesAfterMidnight(rulerValue: value))
                }
                .padding(.horizontal, 48)
                .accessibilityLabel(Text("Wind-down time"))
            }
        }
    }

    static func rulerValue(minutesAfterMidnight minutes: Int) -> Int {
        min(max((minutes - 17 * 60 + 24 * 60) % (24 * 60), 0), 9 * 60)
    }

    static func minutesAfterMidnight(rulerValue: Int) -> Int {
        (17 * 60 + rulerValue) % (24 * 60)
    }

    /// "9:30pm", "midnight".
    static func timeText(_ minutes: Int) -> String {
        if minutes == 0 { return "Midnight" }
        let hour24 = minutes / 60, minute = minutes % 60
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "am" : "pm"
        return minute == 0 ? "\(hour)\(suffix)" : String(format: "%d:%02d%@", hour, minute, suffix)
    }
}
