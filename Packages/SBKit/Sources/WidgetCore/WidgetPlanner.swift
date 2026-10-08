import Core
import Foundation
import Store

/// Whether the widget is part of what the user has. It's premium; locked after the trial.
public enum WidgetAccess: String, Sendable {
    case unlocked
    case locked
}

/// What one widget timeline entry shows.
public enum WidgetCard: Hashable, Sendable {
    case item(WidgetItem)
    /// Nothing left to show today.
    case caughtUp(waiting: Int)
    /// Too little kept for the widget to be useful yet.
    case screenshotSomething
    /// The trial's over: one blurred card that opens the paywall.
    case locked
}

/// The little the widget needs about an item. Read from the shared database, never the
/// screenshot itself: the thumbnail is small and pre-rendered.
public struct WidgetItem: Hashable, Sendable {
    public var id: String
    public var title: String
    public var category: ItemCategory
    public var detail: String
    public var isUnreviewed: Bool
    /// File names in the App Group's thumbnails and widget-light directories.
    public var thumbnailName: String?
    public var lightName: String

    public init(id: String, title: String, category: ItemCategory, detail: String, isUnreviewed: Bool, thumbnailName: String?, lightName: String) {
        self.id = id
        self.title = title
        self.category = category
        self.detail = detail
        self.isUnreviewed = isUnreviewed
        self.thumbnailName = thumbnailName
        self.lightName = lightName
    }

    public init(_ item: ScreenshotItem, now: Date, calendar: Calendar = .current) {
        self.init(
            id: item.id,
            title: item.title ?? "Something you saved",
            category: item.category,
            detail: Self.detail(for: item, now: now, calendar: calendar),
            isUnreviewed: item.state == .unreviewed,
            thumbnailName: item.thumbnailPath,
            lightName: WidgetLight.fileName(forItem: item.id)
        )
    }

    /// "Friday" for something dated this week, otherwise when it was saved.
    static func detail(for item: ScreenshotItem, now: Date, calendar: Calendar) -> String {
        if let due = item.dueDate, due > now {
            if calendar.isDate(due, inSameDayAs: now) { return "Today" }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
                return "Tomorrow"
            }
            if due.timeIntervalSince(now) < 6 * 86_400 {
                return due.formatted(.dateTime.weekday(.wide))
            }
            return due.formatted(.dateTime.day().month(.abbreviated))
        }
        let days = calendar.dateComponents([.day], from: item.createdAt, to: now).day ?? 0
        switch days {
        case ..<1: return "Saved today"
        case 1: return "Saved yesterday"
        case ..<14: return "Saved \(days) days ago"
        default: return "Saved \(days / 7) weeks ago"
        }
    }
}

/// Pre-rendered light images for the widget, which can't run the app's light.
public enum WidgetLight {
    public static func fileName(forItem id: String) -> String {
        // "v4-": the warm lights. Older cached files (the earlier colourful lights) are ignored.
        "v4-item-\(id).png"
    }

    public static func fileName(for category: ItemCategory) -> String {
        "v4-category-\(category.rawValue).png"
    }
}

public struct WidgetEntryPlan: Hashable, Sendable {
    public var date: Date
    public var card: WidgetCard
    public var score: Score

    public init(date: Date, card: WidgetCard, score: Score) {
        self.date = date
        self.card = card
        self.score = score
    }
}

/// Works out the widget's timeline. Rotation is pre-scheduled (one item an hour), so it costs
/// no refresh budget; a button tap reloads it straight away.
public enum WidgetPlanner {
    public static let rotation: TimeInterval = 3_600
    /// Below this many kept things, the widget nudges for more.
    public static let keptMinimum = 3
    public static let maxEntries = 8

    public static func plan(
        candidates: [ScreenshotItem],
        keptCount: Int,
        waitingCount: Int,
        score: Score,
        access: WidgetAccess,
        now: Date,
        calendar: Calendar = .current
    ) -> (entries: [WidgetEntryPlan], reloadAt: Date) {
        let tomorrow = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        guard access == .unlocked else {
            return ([WidgetEntryPlan(date: now, card: .locked, score: score)], now.addingTimeInterval(6 * 3_600))
        }
        guard !candidates.isEmpty else {
            let card: WidgetCard = keptCount < keptMinimum && waitingCount == 0 ? .screenshotSomething : .caughtUp(waiting: waitingCount)
            // Surfaced items come back tomorrow.
            return ([WidgetEntryPlan(date: now, card: card, score: score)], min(tomorrow, now.addingTimeInterval(3 * 3_600)))
        }
        var entries = candidates.prefix(maxEntries).enumerated().map { index, item in
            WidgetEntryPlan(
                date: now.addingTimeInterval(Double(index) * rotation),
                card: .item(WidgetItem(item, now: now, calendar: calendar)),
                score: score
            )
        }
        if keptCount < keptMinimum, let last = entries.last {
            entries.append(WidgetEntryPlan(date: last.date.addingTimeInterval(rotation), card: .screenshotSomething, score: score))
        }
        let reloadAt = (entries.last?.date ?? now).addingTimeInterval(rotation)
        return (entries, reloadAt)
    }

    /// Items whose entries have been on screen by `now`: they count as surfaced, so they don't
    /// come round again today.
    public static func surfaced(schedule: [ScheduledItem], now: Date) -> [ScheduledItem] {
        schedule.filter { $0.date <= now }
    }
}

/// When each item was due on the widget, kept between timeline reloads.
public struct ScheduledItem: Codable, Hashable, Sendable {
    public var id: String
    public var date: Date

    public init(id: String, date: Date) {
        self.id = id
        self.date = date
    }
}

/// The widget's schedule, in the App Group's defaults.
public enum WidgetSchedule {
    private static let key = "widget.schedule"

    public static func load(_ defaults: UserDefaults?) -> [ScheduledItem] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ScheduledItem].self, from: data)) ?? []
    }

    public static func save(_ schedule: [ScheduledItem], to defaults: UserDefaults?) {
        defaults?.set(try? JSONEncoder().encode(schedule), forKey: key)
    }
}

extension WidgetAccess {
    /// Locked once the purchase state says there's no premium (the trial has ended or was never
    /// started). Until it's known, the widget stays open rather than punish a slow first read.
    public static func current(defaults: UserDefaults? = AppGroup.defaults()) -> WidgetAccess {
        Entitlement.isPremium(defaults) == false ? .locked : .unlocked
    }
}
