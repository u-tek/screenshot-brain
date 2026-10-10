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
    /// Read, but not confidently classified. Filed away, or sorted by their best guess.
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
    /// "In the last two months", "In September", "All time".
    public var periodLabel: String = "In the last two months"
    /// The free monthly Reveal: the count, the categories and the share card. Premium gets the
    /// full set.
    public var isShort = false

    /// The biggest category the user can act on.
    public var topCategory: ItemCategory? {
        categories.first { $0.category.isDisplayableIntention }?.category
    }

    /// What's saved most, chats and posts included: the answer to "what do you save the most?".
    public var mostSaved: ItemCategory? {
        categories.first { $0.category != .reference }?.category
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
        try build(database: database, period: isLimited ? .allTime : .firstScan, answers: answers, isLimited: isLimited, now: now, calendar: calendar)
    }

    /// A Reveal over any period: the first one, a month, or every screenshot ever read.
    public static func build(
        database: AppDatabase,
        period: RevealPeriod,
        answers: OnboardingAnswers?,
        isLimited: Bool,
        isShort: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> RevealStory {
        let range = period.range(now: now, calendar: calendar)
        let summaries = try database.summaries(since: range.start == .distantPast ? nil : range.start)
            .filter { $0.createdAt < range.end }
        // The guesses were about the first two months; later Reveals stand on their own.
        let guesses = period == .firstScan ? answers : nil
        var story = build(summaries: summaries, answers: guesses, isLimited: isLimited, start: range.start, end: range.end, calendar: calendar)
        story.periodLabel = period.label(calendar: calendar, now: now)
        story.isShort = isShort
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
        // Each colour keeps its weight within its own screenshot: dividing by the number of
        // screenshots pushed nearly every colour under the extractor's cut-off.
        let colors = items.flatMap { item in
            item.palette.map { PaletteColor(red: $0.red, green: $0.green, blue: $0.blue, weight: $0.weight) }
        }
        if let extracted = LightPalette(extracted: colors) {
            return extracted
        }
        return fallback.map(LightPalette.category) ?? .sampleTopScreenshots
    }
}

/// What a Reveal covers.
public enum RevealPeriod: Hashable, Sendable {
    /// The first Reveal: as far back as the first scan looked.
    case firstScan
    /// A calendar month, starting on its first day.
    case month(Date)
    /// Every screenshot ever read. Premium.
    case allTime

    /// The month that just ended.
    public static func lastMonth(now: Date = Date(), calendar: Calendar = .current) -> RevealPeriod {
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return .month(calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth)
    }

    func range(now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        switch self {
        case .firstScan: (now.addingTimeInterval(-RevealBuilder.lookback), now)
        case .month(let start): (start, calendar.date(byAdding: .month, value: 1, to: start) ?? now)
        case .allTime: (.distantPast, now)
        }
    }

    public func label(calendar: Calendar = .current, now: Date = Date()) -> String {
        switch self {
        case .firstScan: return "In the last two months"
        case .allTime: return "All time"
        case .month(let start):
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = calendar.isDate(start, equalTo: now, toGranularity: .year) ? "LLLL" : "LLLL yyyy"
            return "In " + formatter.string(from: start)
        }
    }

    /// "September" for the home screen tile.
    public func name(calendar: Calendar = .current, now: Date = Date()) -> String {
        label(calendar: calendar, now: now).replacingOccurrences(of: "In ", with: "")
    }
}

extension RevealStory {
    /// The numbers, for keeping in history.
    public func snapshot(kind: RevealSnapshot.Kind) -> RevealSnapshot {
        RevealSnapshot(
            kind: kind,
            periodStart: periodStart,
            periodEnd: periodEnd,
            stats: RevealStats(
                totalScreenshots: total,
                peakHour: peakHour,
                busiestDay: busiestDay,
                busiestDayCount: busiestDayCount,
                categoryCounts: Dictionary(uniqueKeysWithValues: categories.map { ($0.category.rawValue, $0.count) }),
                datedCount: datedCount,
                oldestUndoneItemID: oldestUndone?.id
            )
        )
    }
}

// MARK: - Copy

/// How each category is said out loud.
public enum CategoryWords {
    /// A tab or tile title: "Places".
    public static func title(_ category: ItemCategory) -> String {
        switch category {
        case .place: "Places"
        case .event: "Events"
        case .product: "Products"
        case .recipe: "Recipes"
        case .watch: "Watch"
        case .listen: "Listen"
        case .read: "Read"
        case .travel: "Trips"
        case .message: "Messages"
        case .post: "Posts"
        case .reference: "Reference"
        case .other: "Other"
        }
    }

    public static func plural(_ category: ItemCategory) -> String {
        switch category {
        case .place: "places"
        case .event: "events"
        case .product: "things to buy"
        case .recipe: "recipes"
        case .watch: "shows and films"
        case .listen: "songs and podcasts"
        case .read: "books and articles"
        case .travel: "trips"
        case .message: "chats"
        case .post: "posts and memes"
        case .reference: "receipts and codes"
        case .other: "random stuff"
        }
    }

    /// "1 place", "3 places".
    public static func count(_ count: Int, _ category: ItemCategory) -> String {
        guard count == 1 else { return "\(count.formatted()) \(plural(category))" }
        switch category {
        case .place: return "1 place"
        case .event: return "1 event"
        case .product: return "1 thing to buy"
        case .recipe: return "1 recipe"
        case .watch: return "1 show or film"
        case .listen: return "1 song or podcast"
        case .read: return "1 book or article"
        case .travel: return "1 trip"
        case .message: return "1 chat"
        case .post: return "1 post"
        case .reference: return "1 receipt or code"
        case .other: return "1 random thing"
        }
    }

    public static func meantTo(_ category: ItemCategory) -> String {
        switch category {
        case .place: "you meant to go"
        case .event: "you meant to get to"
        case .product: "you meant to buy"
        case .recipe: "you meant to cook"
        case .watch: "you meant to watch"
        case .listen: "you meant to listen to"
        case .read: "you meant to read"
        case .travel: "you meant to take"
        case .message, .post: "you kept to look back on"
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
            CategoryCount(category: .message, count: 72),
            CategoryCount(category: .place, count: 61),
            CategoryCount(category: .product, count: 40),
            CategoryCount(category: .event, count: 22),
            CategoryCount(category: .recipe, count: 14),
            CategoryCount(category: .reference, count: 31),
        ],
        unsureCount: 46,
        guessedTopCategory: .product,
        topExamples: [
            (0.96, 0.52, 0.24, "Bar Sazerac"),
            (0.98, 0.70, 0.45, "Ramen Ikkyu"),
            (0.85, 0.35, 0.30, "Lune Croissanterie"),
        ].map { red, green, blue, title in
            ScreenshotItem(
                assetLocalID: "sample-\(title)",
                createdAt: Date(timeIntervalSinceReferenceDate: 784_000_000),
                category: .place,
                confidence: 0.94,
                isSafeToDisplay: true,
                palette: [
                    PaletteColor(red: red, green: green, blue: blue, weight: 0.6),
                    PaletteColor(red: red * 0.45, green: green * 0.3, blue: blue * 0.6, weight: 0.4),
                ],
                title: title
            )
        },
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
