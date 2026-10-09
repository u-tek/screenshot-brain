import Core
import DesignSystem
import Media
import Store
import SwiftUI
import UIKit

/// The cards of a Reveal, in order. Cards without data are skipped.
public enum RevealCard: String, CaseIterable, Sendable {
    case total
    case peakTime
    case busiestDay
    case categories
    case topCategory
    case oldest
    case dated
    case share

    static func cards(for story: RevealStory) -> [RevealCard] {
        let short: Set<RevealCard> = [.total, .categories, .share]
        return allCases.filter { card in
            if story.isShort, !short.contains(card) { return false }
            return switch card {
            case .total, .share: true
            case .peakTime: story.peakMinute != nil && story.total >= 5
            case .busiestDay: story.busiestDay != nil && story.busiestDayCount >= 3
            case .categories: !story.categories.isEmpty
            case .topCategory: story.topCategory != nil
            case .oldest: story.oldestUndone != nil
            case .dated: story.datedCount > 0
            }
        }
    }
}

/// The story: full-screen cards, tap to advance, progress segments across the top.
public struct RevealView: View {
    private let story: RevealStory
    private let onShare: () -> Void
    private let onFinish: () -> Void
    private let cards: [RevealCard]
    @State private var index: Int

    public init(story: RevealStory, startAt card: RevealCard? = nil, onShare: @escaping () -> Void = {}, onFinish: @escaping () -> Void) {
        self.story = story
        self.onShare = onShare
        self.onFinish = onFinish
        let cards = RevealCard.cards(for: story)
        self.cards = cards
        self._index = State(initialValue: card.flatMap { cards.firstIndex(of: $0) } ?? 0)
    }

    private var card: RevealCard {
        cards[min(index, cards.count - 1)]
    }

    public var body: some View {
        ZStack {
            LightField(composition(for: card), drifts: true)
                .ignoresSafeArea()
                .animation(SBMotion.reveal, value: index)

            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        if location.x < proxy.size.width / 3 {
                            back()
                        } else {
                            advance()
                        }
                    }
            }
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    SBStoryBars(count: cards.count, current: index)
                    HStack(spacing: 12) {
                        SBMark()
                        Spacer()
                        SBLabel("\(index + 1) / \(cards.count)")
                            .monospacedDigit()
                        SBCircleButton(.x, label: "Skip", size: 36, action: onFinish)
                    }
                }
                .padding(.horizontal, SBSpace.gutter)
                .padding(.top, 4)

                cardView(card)
                    .id(card)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 24)), removal: .opacity))
            }
        }
        .accessibilityAction(named: Text("Next card")) { advance() }
        .accessibilityAction(named: Text("Previous card")) { back() }
    }

    private func advance() {
        guard index < cards.count - 1 else {
            onFinish()
            return
        }
        Haptics.selection()
        withAnimation(SBMotion.reveal) { index += 1 }
    }

    private func back() {
        guard index > 0 else { return }
        withAnimation(SBMotion.reveal) { index -= 1 }
    }

    private func composition(for card: RevealCard) -> LightComposition {
        switch card {
        case .total, .dated: .sweep(story.palette)
        case .peakTime, .busiestDay: .sweep(story.palette).mirrored()
        case .categories, .topCategory: .sweep(story.palette.reversed).shifted(down: -0.04)
        case .oldest: .sweep(story.oldestUndone.map(Self.palette(for:)) ?? story.palette).mirrored()
        case .share: .sweep(story.palette)
        }
    }

    static func palette(for item: ScreenshotItem) -> LightPalette {
        .item(category: item.category, colors: item.palette, isSafeToDisplay: item.isSafeToDisplay)
    }

    @ViewBuilder
    private func cardView(_ card: RevealCard) -> some View {
        switch card {
        case .total: TotalCard(story: story)
        case .peakTime: PeakTimeCard(story: story)
        case .busiestDay: BusiestDayCard(story: story)
        case .categories: CategoriesCard(story: story)
        case .topCategory: TopCategoryCard(story: story)
        case .oldest: OldestCard(story: story)
        case .dated: DatedCard(story: story)
        case .share: ShareCardScreen(story: story, onShare: onShare, onFinish: onFinish)
        }
    }
}

// MARK: - Cards

/// A big number with its unit, low on the card, and room above for the light.
private struct BigNumber: View {
    let value: Int
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CountingNumber(value, font: SBFont.number(150))
            Text(unit)
                .sbText(.unit)
                .padding(.leading, 6)
        }
    }
}

private struct CardLayout<Top: View, Bottom: View>: View {
    let top: Top
    let bottom: Bottom

    init(@ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        // Content sits low on the card, as on the welcome screen; the light has the top.
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 120)
            top
            Spacer(minLength: 24)
                .frame(maxHeight: 56)
            bottom
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TotalCard: View {
    let story: RevealStory

    var body: some View {
        CardLayout {
            VStack(alignment: .leading, spacing: 12) {
                SBLabel(story.isLimited ? "From the screenshots you picked" : story.periodLabel)
                BigNumber(value: story.total, unit: story.total == 1 ? "screenshot" : "screenshots")
            }
        } bottom: {
            if let guess = story.guessedTotal {
                FrostedCard(palette: story.palette) {
                    VStack(alignment: .leading, spacing: 14) {
                        MistHeadline(verdict(guess: guess), size: 24, alignment: .leading)
                        DataRows([
                            ("Guess", guess.formatted()),
                            ("Actual", story.total.formatted()),
                            ("Off by", abs(story.total - guess).formatted()),
                        ])
                    }
                }
            }
        }
    }

    private func verdict(guess: Int) -> String {
        let ratio = guess == story.total ? 1 : Double(story.total) / Double(max(guess, 1))
        switch ratio {
        case 0.85...1.15: return "You guessed \(guess). **Scary close.**"
        case 1.5...: return "You guessed \(guess). **Not even close.**"
        case 1.15..<1.5: return "You guessed \(guess). **It's more.**"
        case ..<0.67: return "You guessed \(guess). **Bit generous.**"
        default: return "You guessed \(guess). **It's fewer.**"
        }
    }
}

private struct PeakTimeCard: View {
    let story: RevealStory

    var body: some View {
        CardLayout {
            VStack(alignment: .leading, spacing: 18) {
                SBLabel("When you screenshot")
                MistHeadline("Your peak screenshot time is **\(story.peakTimeText ?? "").**", size: 34, alignment: .leading)
                if let guessed = story.guessedPeakPeriod, let hour = story.peakHour {
                    MistBody(DayPeriod(hour: hour) == guessed
                        ? "You said \(CategoryWords.period(guessed)). **Spot on.**"
                        : "You said \(CategoryWords.period(guessed)). **Not quite.**", alignment: .leading)
                }
            }
        } bottom: {
            VStack(spacing: 8) {
                TimelineLine(values: normalised(story.hourCounts), highlight: story.peakHour ?? 0)
                HStack {
                    ForEach(["12AM", "6AM", "12PM", "6PM", "11PM"], id: \.self) { label in
                        Text(label).font(SBFont.mono(10)).foregroundStyle(SBColor.inkSecondary)
                        if label != "11PM" { Spacer() }
                    }
                }
            }
        }
    }

    private func normalised(_ counts: [Int]) -> [Double] {
        let peak = Double(max(counts.max() ?? 1, 1))
        return counts.map { Double($0) / peak }
    }
}

private struct BusiestDayCard: View {
    let story: RevealStory

    var body: some View {
        CardLayout {
            VStack(alignment: .leading, spacing: 12) {
                SBLabel("Your busiest day")
                BigNumber(value: story.busiestDayCount, unit: "in one day")
            }
        } bottom: {
            if let day = story.busiestDay {
                MistHeadline("That was **\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).**", size: 30, alignment: .leading)
            }
        }
    }
}

private struct CategoriesCard: View {
    let story: RevealStory

    var body: some View {
        CardLayout {
            VStack(alignment: .leading, spacing: 14) {
                SBLabel("What you save")
                MistHeadline(headline, size: 32, alignment: .leading)
                if story.unsureCount > 0 {
                    MistBody(story.unsureCount == 1 ? "1 we weren't sure about. **It's in triage.**" : "\(story.unsureCount) we weren't sure about. **They're in triage.**", alignment: .leading)
                }
            }
        } bottom: {
            StackedFolders(categories: Array(story.categories.prefix(4)))
                .frame(height: 260)
        }
    }

    private var headline: String {
        guard let top = story.topCategory else { return "Here's **what you save.**" }
        guard let guessed = story.guessedTopCategory else { return "Mostly, **\(CategoryWords.plural(top)).**" }
        if guessed == top {
            return "You guessed \(CategoryWords.plural(guessed)). **Nailed it.**"
        }
        return "You guessed \(CategoryWords.plural(guessed)). **It's \(CategoryWords.plural(top)).**"
    }
}

/// Frosted folder-tab cards stacked in soft perspective, the biggest category in front.
private struct StackedFolders: View {
    let categories: [RevealStory.CategoryCount]

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(categories.enumerated().reversed()), id: \.element.category) { index, entry in
                FolderTabCard(tab: CategoryWords.title(entry.category), palette: .category(entry.category)) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.count.formatted())
                            .font(SBFont.number(44))
                            .foregroundStyle(SBColor.ink)
                        Text("saved")
                            .font(SBFont.body(15, weight: .semibold))
                            .foregroundStyle(SBColor.ink)
                        Spacer()
                    }
                }
                .frame(height: 170)
                .scaleEffect(1 - CGFloat(index) * 0.06, anchor: .bottom)
                .offset(y: -CGFloat(index) * 34)
                .rotation3DEffect(.degrees(10), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
                .opacity(1 - Double(index) * 0.12)
            }
        }
    }
}

private struct TopCategoryCard: View {
    let story: RevealStory

    var body: some View {
        CardLayout {
            if let top = story.topCategory {
                VStack(alignment: .leading, spacing: 14) {
                    SBLabel("Your top category")
                    Text(CategoryWords.plural(top))
                        .sbText(.story)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    MistHeadline("**\(CategoryWords.count(story.topCategoryCount, top))** \(CategoryWords.meantTo(top)).", size: 32, alignment: .leading)
                }
            }
        } bottom: {
            HStack(spacing: -28) {
                ForEach(Array(story.topExamples.enumerated()), id: \.element.id) { index, item in
                    // The item's own light shows until (or unless) its thumbnail loads.
                    ZStack {
                        LightField(.glow(RevealView.palette(for: item)), grain: 0.04)
                        ThumbnailImage(url: thumbnailURL(item))
                    }
                        .frame(width: 118, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(SBColor.warm(0.14), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
                        .offset(y: index == 1 ? -14 : 0)
                        .zIndex(index == 1 ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
    }

    private func thumbnailURL(_ item: ScreenshotItem) -> URL? {
        guard let path = item.thumbnailPath, let directory = try? AppGroup.directory(.thumbnails) else { return nil }
        return directory.appendingPathComponent(path)
    }
}

private struct OldestCard: View {
    let story: RevealStory

    var body: some View {
        CardLayout {
            if let item = story.oldestUndone {
                VStack(alignment: .leading, spacing: 14) {
                    SBLabel("The oldest thing you never did")
                    MistHeadline("Saved **\(item.createdAt.formatted(.relative(presentation: .named)))**", size: 34, alignment: .leading)
                }
            }
        } bottom: {
            if let item = story.oldestUndone {
                FolderTabCard(tab: CategoryWords.title(item.category), palette: RevealView.palette(for: item)) {
                    VStack(alignment: .leading, spacing: 6) {
                        MistHeadline("**\(item.title ?? "Something you saved")**", size: 22, alignment: .leading)
                        DataRows([("Saved", item.createdAt.formatted(date: .abbreviated, time: .omitted))])
                    }
                }
                .frame(height: 230)
            }
        }
    }
}

private struct DatedCard: View {
    let story: RevealStory

    var body: some View {
        CardLayout {
            VStack(alignment: .leading, spacing: 12) {
                SBLabel("Screenshots with a date in them")
                BigNumber(value: story.datedCount, unit: "had a date")
            }
        } bottom: {
            MistHeadline("Gigs, sales, bookings. **Dates are what slip.**", size: 28, alignment: .leading)
        }
    }
}

private struct ShareCardScreen: View {
    let story: RevealStory
    let onShare: () -> Void
    let onFinish: () -> Void
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            ShareCardView(story: story)
                .frame(width: 216, height: 384)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(SBColor.warm(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 20)
                .accessibilityLabel(Text("Your share card"))
            MistHeadline("Post it. **Go on.**", size: 28)
            Spacer(minLength: 12)
            VStack(spacing: 10) {
                if let image {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview("My screenshot Reveal", image: Image(uiImage: image))
                    ) {
                        ActionBarLabel("Share my Reveal", systemImage: "square.and.arrow.up", palette: story.palette)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded(onShare))
                }
                Button(action: onFinish) {
                    SBChip("Keep going")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .task {
            image = ShareCardView.render(story: story)
        }
    }
}
