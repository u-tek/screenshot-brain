import Core
import Foundation

/// Something the planner might mention by name.
public struct NotableItem: Hashable, Sendable {
    public var id: String
    public var title: String?
    public var category: ItemCategory
    public var dueDate: Date?

    public init(id: String, title: String?, category: ItemCategory, dueDate: Date?) {
        self.id = id
        self.title = title
        self.category = category
        self.dueDate = dueDate
    }
}

/// Everything the planner needs to decide tonight's notification.
public struct NotificationContext: Sendable {
    public var now: Date
    /// Minutes after midnight.
    public var recapMinutes: Int
    /// Intentions saved since the last recap, newest first.
    public var newItems: [NotableItem]
    /// Kept or undecided things with a date coming up, soonest first.
    public var datedItems: [NotableItem]
    public var weekSaved: Int
    public var weekDone: Int
    public var lastOpenedAt: Date
    /// When the free trial ends, while one is running.
    public var trialEndsAt: Date?
    public var doneCount: Int
    public var history: NotificationHistory

    public init(
        now: Date,
        recapMinutes: Int,
        newItems: [NotableItem],
        datedItems: [NotableItem],
        weekSaved: Int,
        weekDone: Int,
        lastOpenedAt: Date,
        trialEndsAt: Date?,
        doneCount: Int,
        history: NotificationHistory
    ) {
        self.now = now
        self.recapMinutes = recapMinutes
        self.newItems = newItems
        self.datedItems = datedItems
        self.weekSaved = weekSaved
        self.weekDone = weekDone
        self.lastOpenedAt = lastOpenedAt
        self.trialEndsAt = trialEndsAt
        self.doneCount = doneCount
        self.history = history
    }
}

public struct PlannedNotification: Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case recap
        case expiry
        case digest
        case trialReminder
        case winBack
        case monthlyReveal
    }

    public var kind: Kind
    public var body: String
    public var fireAt: Date
    /// The item it's about, if any (so it isn't nudged twice).
    public var itemID: String?
    /// Where tapping it goes: a `screenshotbrain://` link.
    public var link: String
}

/// What's been sent, so one-off notifications stay one-off.
public struct NotificationHistory: Codable, Hashable, Sendable {
    public var nudgedItemIDs: Set<String> = []
    public var winBackSentAt: Date?
    public var trialReminderSent = false
    /// "2026-10" for the month whose Reveal was announced.
    public var monthlyRevealSent: String?

    public init() {}

    public mutating func record(_ plan: PlannedNotification, calendar: Calendar = .current) {
        if let id = plan.itemID {
            nudgedItemIDs.insert(id)
        }
        switch plan.kind {
        case .winBack: winBackSentAt = plan.fireAt
        case .trialReminder: trialReminderSent = true
        case .monthlyReveal: monthlyRevealSent = NotificationPlanner.monthKey(plan.fireAt, calendar: calendar)
        case .recap, .expiry, .digest: break
        }
    }
}

/// Decides the one notification (or none) for the next recap time.
///
/// At most one a day, by construction: there's one slot, at the recap time. Copy is always
/// specific. No streaks: missing a day never costs anything.
public enum NotificationPlanner {
    /// Dated things get a nudge this long before they pass.
    public static let expiryLead: TimeInterval = 2 * 86_400
    public static let winBackAfter: TimeInterval = 7 * 86_400
    public static let silentAfter: TimeInterval = 30 * 86_400

    public static func plan(_ context: NotificationContext, calendar: Calendar = .current) -> PlannedNotification? {
        let fireAt = nextRecap(after: context.now, minutes: context.recapMinutes, calendar: calendar)
        let away = fireAt.timeIntervalSince(context.lastOpenedAt)
        let expiring = context.datedItems.filter { item in
            guard let due = item.dueDate, !context.history.nudgedItemIDs.contains(item.id) else { return false }
            return due > fireAt && due.timeIntervalSince(fireAt) <= expiryLead
        }

        // A month away: stop completely.
        if away >= silentAfter { return nil }

        // A week away: one nudge about something expiring, then quiet until they're back.
        if away >= winBackAfter {
            let alreadySent = (context.history.winBackSentAt ?? .distantPast) > context.lastOpenedAt
            guard !alreadySent, let item = expiring.first else { return nil }
            return PlannedNotification(kind: .winBack, body: NotificationCopy.expiry(item, at: fireAt, calendar: calendar), fireAt: fireAt, itemID: item.id, link: "screenshotbrain://item/\(item.id)")
        }

        // Day 5 of the 7-day trial.
        if let trialEnds = context.trialEndsAt, !context.history.trialReminderSent {
            let left = trialEnds.timeIntervalSince(fireAt)
            if left > 0, left <= 2.5 * 86_400 {
                return PlannedNotification(kind: .trialReminder, body: NotificationCopy.trialReminder(done: context.doneCount), fireAt: fireAt, itemID: nil, link: "screenshotbrain://paywall")
            }
        }

        // The 1st: last month's Reveal.
        if calendar.component(.day, from: fireAt) == 1, context.history.monthlyRevealSent != monthKey(fireAt, calendar: calendar) {
            return PlannedNotification(kind: .monthlyReveal, body: NotificationCopy.monthlyReveal(at: fireAt, calendar: calendar), fireAt: fireAt, itemID: nil, link: "screenshotbrain://home")
        }

        // Last chance: something passes within a day.
        if let item = expiring.first, let due = item.dueDate, due.timeIntervalSince(fireAt) <= 86_400 {
            return PlannedNotification(kind: .expiry, body: NotificationCopy.expiry(item, at: fireAt, calendar: calendar), fireAt: fireAt, itemID: item.id, link: "screenshotbrain://item/\(item.id)")
        }

        let isSunday = calendar.component(.weekday, from: fireAt) == 1

        // Something new: the recap. It names one new thing, not the same one every night.
        if let first = context.newItems.first(where: { !context.history.nudgedItemIDs.contains($0.id) }) ?? context.newItems.first {
            let body = isSunday
                ? NotificationCopy.digest(saved: context.weekSaved, done: context.weekDone, waiting: context.newItems.count)
                : NotificationCopy.recap(first, others: context.newItems.count - 1, at: fireAt, calendar: calendar)
            return PlannedNotification(kind: isSunday ? .digest : .recap, body: body, fireAt: fireAt, itemID: isSunday ? nil : first.id, link: "screenshotbrain://recap")
        }

        // Nothing new: one expiring thing instead, or nothing.
        if let item = expiring.first {
            return PlannedNotification(kind: .expiry, body: NotificationCopy.expiry(item, at: fireAt, calendar: calendar), fireAt: fireAt, itemID: item.id, link: "screenshotbrain://item/\(item.id)")
        }

        if isSunday, context.weekSaved > 0 || context.weekDone > 0 {
            return PlannedNotification(kind: .digest, body: NotificationCopy.digest(saved: context.weekSaved, done: context.weekDone, waiting: 0), fireAt: fireAt, itemID: nil, link: "screenshotbrain://home")
        }
        return nil
    }

    /// The next time the clock reads the recap time.
    public static func nextRecap(after now: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }

    static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

/// The words. Always about something specific; never "don't forget to check the app".
public enum NotificationCopy {
    static func name(_ item: NotableItem) -> String {
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 40 {
            return title
        }
        switch item.category {
        case .event: return "That gig you saved"
        case .place: return "That place you saved"
        case .product: return "That thing you saved"
        case .recipe: return "That recipe you saved"
        case .watch: return "That show you saved"
        case .listen: return "That album you saved"
        case .read: return "That book you saved"
        case .travel: return "That trip you saved"
        case .message, .post, .reference, .other: return "Something you saved"
        }
    }

    /// "Friday", "tomorrow", "tonight".
    static func day(_ date: Date, from now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "tonight" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    public static func recap(_ item: NotableItem, others: Int, at now: Date, calendar: Calendar) -> String {
        let more = others > 0 ? (others == 1 ? " 1 more waiting." : " \(others) more waiting.") : ""
        let line: String
        switch item.category {
        case .event:
            // A gig that's been and gone isn't "Saturday".
            if let due = item.dueDate, due > now {
                line = "\(name(item)) is \(day(due, from: now, calendar: calendar)). Still going?"
            } else {
                line = "\(name(item)). Going?"
            }
        case .place: line = "\(name(item)). Actually going?"
        case .product: line = "\(name(item)). Still want it?"
        case .recipe: line = "\(name(item)). Cooking it this week?"
        case .watch: line = "\(name(item)). Watching it this week?"
        case .listen: line = "\(name(item)). Given it a listen yet?"
        case .read: line = "\(name(item)). Started it yet?"
        case .travel: line = "\(name(item)). Booking it?"
        case .message, .post, .reference, .other: line = "\(name(item)). Keep it or let it go?"
        }
        return line + more
    }

    public static func expiry(_ item: NotableItem, at now: Date, calendar: Calendar) -> String {
        guard let due = item.dueDate else { return "\(name(item)). Still keen?" }
        let when = day(due, from: now, calendar: calendar)
        switch item.category {
        case .event: return "\(name(item)) is \(when). Still going?"
        case .product: return "The \(name(item)) deal ends \(when). Still want it?"
        default: return "\(name(item)) is \(when). Still keen?"
        }
    }

    public static func digest(saved: Int, done: Int, waiting: Int) -> String {
        let base = "\(saved) saved, \(done) done this week."
        return waiting > 0 ? base + " \(waiting) new to look at." : base
    }

    public static func trialReminder(done: Int) -> String {
        let ticked = done == 1 ? "1 thing" : "\(done) things"
        return "Your widget trial ends in 2 days. You've ticked off \(ticked)."
    }

    public static func monthlyReveal(at date: Date, calendar: Calendar) -> String {
        let previous = calendar.date(byAdding: .month, value: -1, to: date) ?? date
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "LLLL"
        return "Your \(formatter.string(from: previous)) Reveal is ready. Guess how many you did?"
    }
}
