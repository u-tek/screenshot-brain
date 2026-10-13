import Core
import Foundation

/// Today's pick: one kept thing that fits today, and one line of why. It's chosen only from what
/// was saved, on the phone, and stays the same all day, so it's a suggestion, not a slot machine.
/// Premium can ask for another (`reroll`); free gets the one.
public struct DailyPick: Hashable, Sendable {
    public let item: ScreenshotItem
    public let reason: String

    /// How many of the best fits a day rotates through.
    static let shortlist = 5

    public static func pick(
        from kept: [ScreenshotItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        reroll: Int = 0
    ) -> DailyPick? {
        let ranked = candidates(kept, now: now)
            .map { (item: $0, fit: fit($0, now: now, calendar: calendar)) }
            .sorted { $0.fit.score == $1.fit.score ? $0.item.id < $1.item.id : $0.fit.score > $1.fit.score }
            .prefix(shortlist)
        guard !ranked.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let chosen = ranked[ranked.startIndex + (day + max(reroll, 0)) % ranked.count]
        return DailyPick(item: chosen.item, reason: chosen.fit.reason)
    }

    /// Kept, named, safe to show, and not already been and gone.
    static func candidates(_ kept: [ScreenshotItem], now: Date) -> [ScreenshotItem] {
        kept.filter { item in
            guard item.state == .stillWant, item.category.isIntention, !item.isNSFWFlagged,
                  let title = item.title, !title.isEmpty else { return false }
            if let due = item.dueDate, due < now { return false }
            return true
        }
    }

    struct Fit {
        var score: Int
        var reason: String
    }

    /// How well a thing suits right now, and the line that says why. The strongest reason wins
    /// the line.
    static func fit(_ item: ScreenshotItem, now: Date, calendar: Calendar) -> Fit {
        var reasons: [(score: Int, line: String)] = []
        let hour = calendar.component(.hour, from: now)
        let evening = hour >= 17
        let weekend = isWeekend(now, calendar: calendar)

        if let due = item.dueDate, due.timeIntervalSince(now) <= 7 * 86_400 {
            reasons.append((6, "It's on \(dayName(due, from: now, calendar: calendar))."))
        }
        switch item.category {
        case .place where weekend: reasons.append((4, "It's the weekend. Go on."))
        case .event where weekend: reasons.append((3, "Something to do this weekend."))
        case .travel where weekend: reasons.append((2, "A weekend to plan it."))
        case .recipe where evening && !weekend: reasons.append((4, "Something to cook tonight."))
        case .recipe where weekend: reasons.append((3, "A weekend to cook something new."))
        case .watch where evening: reasons.append((4, "Tonight's watch, sorted."))
        case .listen where evening: reasons.append((3, "One for tonight."))
        case .read where !evening: reasons.append((2, "One to start today."))
        default: break
        }
        let season = Season(now, calendar: calendar)
        if season.matches(item) {
            reasons.append((3, "Made for \(season.rawValue)."))
        }
        let kept = item.stateChangedAt ?? item.createdAt
        let weeks = Int(now.timeIntervalSince(kept) / (7 * 86_400))
        if weeks >= 3 {
            reasons.append((min(weeks / 2, 3), "Kept since \(monthName(kept, calendar: calendar)). Still want it?"))
        }

        let total = reasons.reduce(0) { $0 + $1.score }
        let line = reasons.max { $0.score < $1.score }?.line ?? "One you saved. Still want it?"
        return Fit(score: total, reason: line)
    }

    /// Friday after five through Sunday.
    static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        switch calendar.component(.weekday, from: date) {
        case 1, 7: return true
        case 6: return calendar.component(.hour, from: date) >= 17
        default: return false
        }
    }

    static func dayName(_ date: Date, from now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return formatted(date, "EEEE", calendar: calendar)
    }

    static func monthName(_ date: Date, calendar: Calendar) -> String {
        formatted(date, "LLLL", calendar: calendar)
    }

    private static func formatted(_ date: Date, _ format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Northern-hemisphere seasons by month. Only used when a saved thing names the season itself.
    enum Season: String {
        case spring, summer, autumn, winter

        init(_ date: Date, calendar: Calendar) {
            switch calendar.component(.month, from: date) {
            case 3...5: self = .spring
            case 6...8: self = .summer
            case 9...11: self = .autumn
            default: self = .winter
            }
        }

        private var words: [String] {
            switch self {
            case .spring: ["spring"]
            case .summer: ["summer", "beach", "bbq", "barbecue", "rooftop", "outdoor"]
            case .autumn: ["autumn", "fall", "cosy", "cozy", "pumpkin", "halloween"]
            case .winter: ["winter", "christmas", "festive", "mulled", "ski"]
            }
        }

        func matches(_ item: ScreenshotItem) -> Bool {
            let body = String((item.extractedText ?? "").prefix(400))
            let text = "\(item.title ?? "") \(body)".lowercased()
            let tokens = Set(text.split { !$0.isLetter }.map(String.init))
            return words.contains { tokens.contains($0) }
        }
    }
}

/// The weekend plan: from Thursday evening to Sunday, two or three kept things for the weekend,
/// dated things on those days first, then places and events, kept longest first. Free sees it;
/// Premium can swap it for another set (`reroll`).
public enum WeekendPlan {
    public static let size = 3

    /// Thursday from five until Sunday night.
    public static func isOn(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch calendar.component(.weekday, from: date) {
        case 1, 6, 7: return true
        case 5: return calendar.component(.hour, from: date) >= 17
        default: return false
        }
    }

    /// Fewer than two fits and there's no plan: one thing is just today's pick.
    public static func pick(
        from kept: [ScreenshotItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        reroll: Int = 0
    ) -> [ScreenshotItem] {
        let end = weekendEnd(after: now, calendar: calendar)
        let candidates = DailyPick.candidates(kept, now: now)
        let dated = candidates
            .filter { item in item.dueDate.map { $0 <= end } ?? false }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let outings = candidates
            .filter { $0.dueDate == nil && [.place, .event, .travel].contains($0.category) }
            .sorted { ($0.stateChangedAt ?? $0.createdAt) < ($1.stateChangedAt ?? $1.createdAt) }
        // Dated things stay put; a swap rotates the undated ones.
        var plan = Array(dated.prefix(size))
        if !outings.isEmpty, plan.count < size {
            let shift = max(reroll, 0) * (size - plan.count) % outings.count
            let rotated = Array(outings[shift...] + outings[..<shift])
            plan += rotated.prefix(size - plan.count)
        }
        return plan.count >= 2 ? plan : []
    }

    /// The end of the coming Sunday.
    static func weekendEnd(after now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now)
        let daysToMonday = weekday == 1 ? 1 : 9 - weekday
        return calendar.date(byAdding: .day, value: daysToMonday, to: start) ?? now.addingTimeInterval(4 * 86_400)
    }
}
