import Core
import Foundation

/// A shelf that builds itself from what's been kept. Each one is a plain rule over an item's
/// title, text, entities and category, so it is always possible to say why something is on it.
/// An item can sit on several shelves. Nothing here leaves the phone.
public enum SmartShelf: String, CaseIterable, Identifiable, Sendable {
    case free
    case dateNight
    case rainyDay
    case cheap
    case withFriends
    case lateNight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .free: "Free"
        case .dateNight: "Date night"
        case .rainyDay: "Rainy day"
        case .cheap: "Under 20"
        case .withFriends: "With friends"
        case .lateNight: "Late night"
        }
    }

    // MARK: - Assigning

    /// The shelves an item belongs on, in the fixed shelf order.
    public static func shelves(for item: ScreenshotItem) -> [SmartShelf] {
        let words = Words(item)
        return allCases.filter { $0.accepts(item, words) }
    }

    /// Kept items grouped by shelf, in the fixed shelf order. Shelves with nothing on them are
    /// left out, and so is anything that isn't still wanted.
    public static func group(_ items: [ScreenshotItem]) -> [(SmartShelf, [ScreenshotItem])] {
        let kept = items.filter { $0.state == .stillWant }
        let assigned = kept.map { (item: $0, shelves: shelves(for: $0)) }
        return allCases.compactMap { shelf in
            let members = assigned.filter { $0.shelves.contains(shelf) }.map { $0.item }
            return members.isEmpty ? nil : (shelf, members)
        }
    }

    // MARK: - Rules

    private func accepts(_ item: ScreenshotItem, _ words: Words) -> Bool {
        switch self {
        case .free:
            return words.has(#"\bfree\b[\s\S]{0,25}\b(?:entry|admission|events?|tickets?)\b"#)
                || words.has(#"\b(?:entry|admission|events?|tickets?)\b[\s\S]{0,15}\bfree\b"#)
                || words.prices.contains(0)
        case .dateNight:
            guard item.category == .place || item.category == .event else { return false }
            return words.has(#"\b(?:wine|cocktails?|dinner|bistro|bar|rooftop|omakase|tasting|candlelit|jazz)\b"#)
        case .rainyDay:
            switch item.category {
            case .watch, .listen, .read, .recipe:
                return true
            default:
                return words.has(#"\b(?:museums?|galler(?:y|ies)|cinemas?|bookshops?|exhibitions?)\b"#)
            }
        case .cheap:
            return words.prices.contains { $0 <= 20 }
        case .withFriends:
            return words.has(#"\b(?:groups?|share|sharing|trivia|karaoke|bowling|festivals?)\b"#)
                || words.has(#"\bfor (?:4|6)(?![\w:]|\.\d)"#)
        case .lateNight:
            if words.has(#"\bopen late\b|\b(?:until|till|til) midnight\b|\blate[- ]night\b|\bafter dark\b"#)
                || words.has(#"\b(?:until|till|til)\s+(?:12|1|2|3|4|5)(?::\d\d)?\s?am\b"#) {
                return true
            }
            if item.dueDateHasTime, let due = item.dueDate {
                return Calendar.current.component(.hour, from: due) >= 21
            }
            return false
        }
    }

    /// Everything an item says in words, gathered once so each rule can look through it.
    private struct Words {
        let all: String

        init(_ item: ScreenshotItem) {
            var parts: [String] = []
            if let title = item.title { parts.append(title) }
            if let text = item.extractedText { parts.append(text) }
            parts.append(contentsOf: item.entities.map { $0.text })
            all = parts.joined(separator: "\n")
        }

        func has(_ pattern: String) -> Bool {
            all.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        /// Every price written with a $, £ or € sign, before or after the number: "$12", "£8.50",
        /// "12€". "$1,200" reads as 1200.
        var prices: [Decimal] {
            let number = #"\d+(?:,\d{3})*(?:\.\d+)?"#
            let patterns = [
                #"[$£€]\s?("# + number + #")"#,
                #"(?<![\d.,])("# + number + #")\s?[$£€]"#,
            ]
            var found: [Decimal] = []
            let whole = NSRange(all.startIndex..., in: all)
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: all, range: whole) {
                    guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: all) else { continue }
                    let digits = String(all[range]).replacingOccurrences(of: ",", with: "")
                    if let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) {
                        found.append(value)
                    }
                }
            }
            return found
        }
    }
}
