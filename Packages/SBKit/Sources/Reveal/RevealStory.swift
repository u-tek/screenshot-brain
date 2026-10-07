import Core
import DesignSystem
import Foundation
import Safety
import Store

/// Everything the Reveal shows, computed once. Leads with facts that can't be wrong (counts and
/// timestamps); category claims count only items above the confidence bar.
public struct RevealStory: Sendable {
    public struct CategoryCount: Hashable, Sendable {
        public var category: ItemCategory
        public var count: Int
    }

    public var periodStart: Date
    public var periodEnd: Date
    public var total: Int
    public var guessedTotal: Int?
    /// Screenshots per hour of the day, local time.
    public var hourCounts: [Int]
    /// Start of the busiest ten minutes of the day, in minutes after midnight.
    public var peakMinute: Int?
    public var guessedPeakPeriod: DayPeriod?
    public var busiestDay: Date?
    public var busiestDayCount: Int
    /// Confidently classified categories, largest first.
    public var categories: [CategoryCount]
    /// Read, but not confidently classified. They go to triage.
    public var unsureCount: Int
    public var guessedTopCategory: ItemCategory?
    public var topExamples: [ScreenshotItem]
    public var oldestUndone: ScreenshotItem?
    public var datedCount: Int
    public var doneCount: Int
    public var guessedDoneCount: Int?
    public var palette: LightPalette
    /// Limited photo access: the Reveal is about the handful of screenshots the user shared.
    public var isLimited: Bool

    /// The biggest category the user can act on.
    public var topCategory: ItemCategory? {
        categories.first { $0.category.isDisplayableIntention }?.category
    }

    public var peakHour: Int? {
        peakMinute.map { $0 / 60 }
    }

    public var topCategoryCount: Int {
        categories.first { $0.category == topCategory }?.count ?? 0
    }
}

public enum RevealBuilder {
    /// The first Reveal looks back as far as the first scan does.
    public static let lookback: TimeInterval = 60 * 86_400

    public static func build(
        database: AppDatabase,
        answers: OnboardingAnswers?,
        isLimited: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> RevealStory {
        let start = isLimited ? .distantPast : now.addingTimeInterval(-lookback)
        let summaries = try database.summaries(since: isLimited ? nil : start)
        var story = build(summaries: summaries, answers: answers, isLimited: isLimited, start: start, end: now, calendar: calendar)
        if let top = story.topCategory {
            story.topExamples = try database.revealExamples(category: top, limit: 3)
        }
        story.oldestUndone = try database.oldestUndone()
        story.palette = palette(from: try database.recentSafeItems(limit: 12), fallback: story.topCategory)
        return story
    }

    /// The pure part: counts and timestamps from summaries.
    public static func build(
        summaries: [ItemSummary],
        answers: OnboardingAnswers?,
        isLimited: Bool,
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> RevealStory {
        var hourCounts = Array(repeating: 0, count: 24)
        var slotCounts = Array(repeating: 0, count: 144)
        var dayCounts: [Date: Int] = [:]
        for summary in summaries {
            let parts = calendar.dateComponents([.hour, .minute], from: summary.createdAt)
            let hour = parts.hour ?? 0, minute = parts.minute ?? 0
            hourCounts[hour] += 1
            slotCounts[(hour * 60 + minute) / 10] += 1
            dayCounts[calendar.startOfDay(for: summary.createdAt), default: 0] += 1
        }

        // The peak is the busiest ten minutes inside the busiest hour: precise enough to be
        // surprising ("12:40am"), steady enough not to be noise.
        var peakMinute: Int?
        if let peakHour = hourCounts.indices.max(by: { hourCounts[$0] < hourCounts[$1] }), hourCounts[peakHour] > 0 {
            let slots = (peakHour * 6)..<(peakHour * 6 + 6)
            let slot = slots.max { slotCounts[$0] < slotCounts[$1] } ?? peakHour * 6
            peakMinute = slot * 10
        }
        let busiest = dayCounts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }

        let visible = summaries.filter { !$0.isNSFWFlagged && $0.processedAt != nil }
        let confident = visible.filter { $0.confidence >= Safety.confidenceBar && $0.category != .other }
        var counts: [ItemCategory: Int] = [:]
        for summary in confident {
            counts[summary.category, default: 0] += 1
        }
        let categories = counts
            .map { RevealStory.CategoryCount(category: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.category.rawValue < $1.category.rawValue : $0.count > $1.count }

        return RevealStory(
            periodStart: start,
            periodEnd: end,
            total: summaries.count,
            guessedTotal: answers?.guessedScreenshotCount,
            hourCounts: hourCounts,
            peakMinute: peakMinute,
            guessedPeakPeriod: answers?.guessedPeakPeriod,
            busiestDay: busiest?.key,
            busiestDayCount: busiest?.value ?? 0,
            categories: categories,
            unsureCount: visible.count - confident.count,
            guessedTopCategory: answers?.guessedTopCategory,
            topExamples: [],
            oldestUndone: nil,
            datedCount: summaries.filter(\.hasDate).count,
            doneCount: summaries.filter { $0.state == .done }.count,
            guessedDoneCount: answers?.guessedDoneCount,
            palette: .sampleTopScreenshots,
            isLimited: isLimited
        )
    }

    /// The light of the Reveal: the user's own colours, merged from their recent safe screenshots.
    static func palette(from items: [ScreenshotItem], fallback: ItemCategory?) -> LightPalette {
        let colors = items.flatMap { item in
            item.palette.map { PaletteColor(red: $0.red, green: $0.green, blue: $0.blue, weight: $0.weight / Double(max(items.count, 1))) }
        }
        if let extracted = LightPalette(extracted: colors) {
            return extracted
        }
        return fallback.map(LightPalette.category) ?? .sampleTopScreenshots
    }
}

// MARK: - Copy

/// How each category is said out loud.
public enum CategoryWords {
    public static func plural(_ category: ItemCategory) -> String {
        switch category {
        case .place: "places"
        case .event: "events"
        case .product: "things to buy"
        case .recipe: "recipes"
        case .reference: "receipts and chats"
        case .other: "random stuff"
        }
    }

    public static func meantTo(_ category: ItemCategory) -> String {
        switch category {
        case .place: "you meant to go"
        case .event: "you meant to get to"
        case .product: "you meant to buy"
        case .recipe: "you meant to cook"
        case .reference: "you kept for later"
        case .other: "you saved anyway"
        }
    }

    public static func period(_ period: DayPeriod) -> String {
        switch period {
        case .morning: "mornings"
        case .afternoon: "afternoons"
        case .evening: "evenings"
        case .lateNight: "late at night"
        }
    }
}

extension RevealStory {
    /// "12:40am"
    public var peakTimeText: String? {
        guard let peakMinute else { return nil }
        let hour = peakMinute / 60, minute = peakMinute % 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d%@", hour12, minute, hour < 12 ? "am" : "pm")
    }

    /// For previews, the design lab and snapshots.
    public static let sample = RevealStory(
        periodStart: Date(timeIntervalSinceReferenceDate: 780_000_000),
        periodEnd: Date(timeIntervalSinceReferenceDate: 785_184_000),
        total: 214,
        guessedTotal: 150,
        hourCounts: [9, 6, 3, 1, 0, 0, 1, 3, 6, 8, 9, 11, 14, 12, 9, 8, 10, 12, 13, 15, 17, 16, 14, 7],
        peakMinute: 40,
        guessedPeakPeriod: .evening,
        busiestDay: Date(timeIntervalSinceReferenceDate: 782_870_400),
        busiestDayCount: 19,
        categories: [
            CategoryCount(category: .place, count: 61),
            CategoryCount(category: .product, count: 40),
            CategoryCount(category: .event, count: 22),
            CategoryCount(category: .recipe, count: 14),
            CategoryCount(category: .reference, count: 31),
        ],
        unsureCount: 46,
        guessedTopCategory: .product,
        topExamples: [],
        oldestUndone: ScreenshotItem(
            assetLocalID: "sample",
            createdAt: Date(timeIntervalSinceReferenceDate: 780_400_000),
            category: .place,
            confidence: 0.92,
            state: .stillWant,
            isSafeToDisplay: true,
            palette: [PaletteColor(red: 0.95, green: 0.55, blue: 0.25, weight: 0.6), PaletteColor(red: 0.45, green: 0.15, blue: 0.10, weight: 0.4)],
            title: "Bar Sazerac"
        ),
        datedCount: 23,
        doneCount: 4,
        guessedDoneCount: 20,
        palette: .sampleTopScreenshots,
        isLimited: false
    )
}
