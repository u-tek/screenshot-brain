import Core
import Foundation

/// Something the planner might mention by name.
public struct NotableItem: Hashable, Sendable {
    public var id: String
    public var title: String?
    public var category: ItemCategory
    public var dueDate: Date?
    /// When it was kept, for things brought back up from what's been kept.
    public var keptAt: Date?

    public init(id: String, title: String?, category: ItemCategory, dueDate: Date?, keptAt: Date? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.dueDate = dueDate
        self.keptAt = keptAt
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
    /// Things kept and not yet done, kept longest first: what a quiet night or a win-back brings
    /// back up.
    public var keptItems: [NotableItem]

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
        history: NotificationHistory,
        keptItems: [NotableItem] = []
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
        self.keptItems = keptItems
    }
}

public struct PlannedNotification: Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case recap
        case expiry
        case digest
        case trialReminder
        case winBack
        /// The second and last win-back, three weeks away.
        case lateWinBack
        /// A quiet night: something kept a while, brought back up.
        case resurface
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
    /// Items an expiry or win-back nudge has been about.
    public var nudgedItemIDs: Set<String> = []
    /// Items a recap has named. Kept apart so naming one never blocks its later expiry nudge.
    public var recappedItemIDs: Set<String> = []
    /// When the last notification was planned for, so a changed recap time can't make a second
    /// one on the same calendar day.
    public var lastPlannedAt: Date?
    public var winBackSentAt: Date?
    public var lateWinBackSentAt: Date?
    public var lastResurfacedAt: Date?
    public var trialReminderSent = false
    /// "2026-10" for the month whose Reveal was announced.
    public var monthlyRevealSent: String?

    public init() {}

    // Histories saved before a field existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nudgedItemIDs = try container.decodeIfPresent(Set<String>.self, forKey: .nudgedItemIDs) ?? []
        recappedItemIDs = try container.decodeIfPresent(Set<String>.self, forKey: .recappedItemIDs) ?? []
        lastPlannedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlannedAt)
        winBackSentAt = try container.decodeIfPresent(Date.self, forKey: .winBackSentAt)
        lateWinBackSentAt = try container.decodeIfPresent(Date.self, forKey: .lateWinBackSentAt)
        lastResurfacedAt = try container.decodeIfPresent(Date.self, forKey: .lastResurfacedAt)
        trialReminderSent = try container.decodeIfPresent(Bool.self, forKey: .trialReminderSent) ?? false
        monthlyRevealSent = try container.decodeIfPresent(String.self, forKey: .monthlyRevealSent)
    }

    public mutating func record(_ plan: PlannedNotification, calendar: Calendar = .current) {
        lastPlannedAt = plan.fireAt
        if let id = plan.itemID {
            if plan.kind == .recap {
                recappedItemIDs.insert(id)
            } else {
                nudgedItemIDs.insert(id)
            }
        }
        switch plan.kind {
        case .winBack: winBackSentAt = plan.fireAt
        case .lateWinBack: lateWinBackSentAt = plan.fireAt
        case .resurface: lastResurfacedAt = plan.fireAt
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
///
/// Quiet nights aren't always silent: every few days, something kept a while comes back up, so
/// what was saved gets done rather than forgotten. Someone who stops opening the app hears twice,
/// at a week and at three weeks, then nothing.
public enum NotificationPlanner {
    /// Dated things get a nudge this long before they pass.
    public static let expiryLead: TimeInterval = 2 * 86_400
    public static let winBackAfter: TimeInterval = 7 * 86_400
    public static let lateWinBackAfter: TimeInterval = 21 * 86_400
    public static let silentAfter: TimeInterval = 30 * 86_400
    /// Things kept more recently than this aren't brought back up yet.
    public static let resurfaceAfterKept: TimeInterval = 7 * 86_400
    /// Quiet-night resurfacing happens at most this often (less an hour or two for clock changes).
    public static let resurfaceGap: TimeInterval = 3 * 86_400 - 2 * 3_600

    public static func plan(_ context: NotificationContext, calendar: Calendar = .current) -> PlannedNotification? {
        var fireAt = nextRecap(after: context.now, minutes: context.recapMinutes, calendar: calendar)
        // One a day, even if the recap time moved: a day that already has one waits for tomorrow.
        if let last = context.history.lastPlannedAt, calendar.isDate(last, inSameDayAs: fireAt) {
            fireAt = calendar.date(byAdding: .day, value: 1, to: fireAt) ?? fireAt.addingTimeInterval(86_400)
        }
        let away = fireAt.timeIntervalSince(context.lastOpenedAt)
        let expiring = context.datedItems.filter { item in
            guard let due = item.dueDate, !context.history.nudgedItemIDs.contains(item.id) else { return false }
            return due > fireAt && due.timeIntervalSince(fireAt) <= expiryLead
        }

        // Kept a week or more, not nudged before, and not already been and gone.
        let resurfaceable = context.keptItems.filter { item in
            guard let keptAt = item.keptAt, !context.history.nudgedItemIDs.contains(item.id) else { return false }
            if let due = item.dueDate, due <= fireAt { return false }
            return fireAt.timeIntervalSince(keptAt) >= resurfaceAfterKept
        }

        // A month away: stop completely.
        if away >= silentAfter { return nil }

        // Away a while: one nudge at a week (something expiring, else something kept), one more at
        // three weeks, then quiet until they're back.
        if away >= winBackAfter {
            let firstSent = (context.history.winBackSentAt ?? .distantPast) > context.lastOpenedAt
            if !firstSent {
                if let item = expiring.first {
                    return PlannedNotification(kind: .winBack, body: NotificationCopy.expiry(item, at: fireAt, calendar: calendar), fireAt: fireAt, itemID: item.id, link: "screenshotbrain://item/\(item.id)")
                }
                guard let item = resurfaceable.first else { return nil }
                return PlannedNotification(kind: .winBack, body: NotificationCopy.stillOnYourList(item), fireAt: fireAt, itemID: item.id, link: "screenshotbrain://item/\(item.id)")
            }
            let lateSent = (context.history.lateWinBackSentAt ?? .distantPast) > context.lastOpenedAt
            guard !lateSent, away >= lateWinBackAfter, let item = resurfaceable.first else { return nil }
            return PlannedNotification(kind: .lateWinBack, body: NotificationCopy.lateWinBack(item, kept: context.keptItems.count), fireAt: fireAt, itemID: item.id, link: "screenshotbrain://item/\(item.id)")
        }

        // Day 5 of the 7-day trial.
        if let trialEnds = context.trialEndsAt, !context.history.trialReminderSent {
            let left = trialEnds.timeIntervalSince(fireAt)
            if left > 0, left <= 2.5 * 86_400 {
                return PlannedNotification(kind: .trialReminder, body: NotificationCopy.trialReminder(done: context.doneCount, endsAt: trialEnds, at: fireAt, calendar: calendar), fireAt: fireAt, itemID: nil, link: "screenshotbrain://paywall")
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
        if let first = context.newItems.first(where: { !context.history.recappedItemIDs.contains($0.id) && !context.history.nudgedItemIDs.contains($0.id) }) ?? context.newItems.first {
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

        // A quiet night: every few days, something kept a while.
        let lastResurfaced = context.history.lastResurfacedAt ?? .distantPast
        if fireAt.timeIntervalSince(lastResurfaced) >= resurfaceGap, let item = resurfaceable.first, let keptAt = item.keptAt {
            return PlannedNotification(kind: .resurface, body: NotificationCopy.resurface(item, keptAt: keptAt, at: fireAt), fireAt: fireAt, itemID: item.id, link: "screenshotbrain://item/\(item.id)")
        }
        return nil
    }

    /// The next time the clock reads the recap time.
    public static func nextRecap(after now: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        // The calendar knows daylight-saving days (and times that don't exist on them).
        let wanted = DateComponents(hour: minutes / 60, minute: minutes % 60, second: 0)
        if let next = calendar.nextDate(after: now, matching: wanted, matchingPolicy: .nextTime) {
            return next
        }
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
        formatter.locale = .current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    public static func recap(_ item: NotableItem, others: Int, at now: Date, calendar: Calendar) -> String {
        let more = others > 0 ? (others == 1 ? " 1 more waiting." : " \(others) more waiting.") : ""
        // A gig that's been and gone isn't "Saturday".
        if item.category == .event, let due = item.dueDate, due > now {
            return "\(name(item)) is \(day(due, from: now, calendar: calendar)). Still going?" + more
        }
        return "\(name(item)). \(question(item.category))" + more
    }

    /// The question each kind of thing gets asked.
    static func question(_ category: ItemCategory) -> String {
        switch category {
        case .event: "Going?"
        case .place: "Actually going?"
        case .product: "Still want it?"
        case .recipe: "Cooking it this week?"
        case .watch: "Watching it this week?"
        case .listen: "Given it a listen yet?"
        case .read: "Started it yet?"
        case .travel: "Booking it?"
        case .message, .post, .reference, .other: "Keep it or let it go?"
        }
    }

    /// A quiet night. "You kept Ramen Ikkyu 3 weeks ago. Actually going?"; without a name that's
    /// safe to show, "That place you saved 3 weeks ago. Actually going?"
    public static func resurface(_ item: NotableItem, keptAt: Date, at now: Date) -> String {
        let ago = keptAgo(keptAt, now: now)
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let opening = !title.isEmpty && title.count <= 40 ? "You kept \(title) \(ago)." : "\(name(item)) \(ago)."
        return "\(opening) \(question(item.category))"
    }

    /// The first win-back when nothing's expiring: "Ramen Ikkyu is still on your list. This weekend?"
    public static func stillOnYourList(_ item: NotableItem) -> String {
        "\(name(item)) is still on your list. This weekend?"
    }

    /// The last win-back: "You've still got 9 things saved to do. Ramen Ikkyu is one of them."
    public static func lateWinBack(_ item: NotableItem, kept: Int) -> String {
        guard kept > 1 else { return "You've still got 1 thing saved to do: \(name(item))." }
        return "You've still got \(kept) things saved to do. \(name(item)) is one of them."
    }

    /// "last week", "3 weeks ago", "2 months ago", "over a year ago".
    static func keptAgo(_ keptAt: Date, now: Date) -> String {
        let days = max(Int(now.timeIntervalSince(keptAt) / 86_400), 0)
        switch days {
        case ..<14: return "last week"
        case ..<60: return "\(days / 7) weeks ago"
        case ..<365: return days < 90 ? "2 months ago" : "\(days / 30) months ago"
        default: return "over a year ago"
        }
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

    public static func trialReminder(done: Int, endsAt: Date, at now: Date, calendar: Calendar) -> String {
        let ticked = done == 1 ? "1 thing" : "\(done) things"
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: endsAt)).day ?? 2
        let when: String
        switch days {
        case ...0: when = "today"
        case 1: when = "tomorrow"
        default: when = "in \(days) days"
        }
        return "Your free week of Premium ends \(when). You've ticked off \(ticked)."
    }

    public static func monthlyReveal(at date: Date, calendar: Calendar) -> String {
        let previous = calendar.date(byAdding: .month, value: -1, to: date) ?? date
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.dateFormat = "LLLL"
        return "Your \(formatter.string(from: previous)) Reveal is ready. Guess how many you did?"
    }
}
