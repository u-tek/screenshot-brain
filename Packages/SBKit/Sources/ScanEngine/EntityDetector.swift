import Core
import Foundation

/// Finds dates, addresses, links, phone numbers and transit details (with `NSDataDetector`), and
/// prices, star ratings and review counts (with regular expressions).
public struct EntityDetector: Sendable {
    public init() {}

    /// - Parameters:
    ///   - capturedAt: When the screenshot was taken. `NSDataDetector` reads "tomorrow" and "Friday"
    ///     against today, so once a screenshot is more than a day old the dates that depend on
    ///     the day it was read are dropped rather than guessed.
    ///   - now: Today, for that comparison.
    public func entities(in text: String, capturedAt: Date? = nil, now: Date = Date()) -> [DetectedEntity] {
        var found = dataDetectorEntities(in: text)
        if let capturedAt, now.timeIntervalSince(capturedAt) > 86_400 {
            found.removeAll { $0.kind == .date && Self.isRelativeDate($0.text) }
        }
        return found
            + prices(in: text)
            + matches(of: Self.ratingPattern, in: text).map { DetectedEntity(kind: .rating, text: $0) }
            + matches(of: Self.reviewCountPattern, in: text).map { DetectedEntity(kind: .reviewCount, text: $0) }
    }

    // MARK: NSDataDetector

    private func dataDetectorEntities(in text: String) -> [DetectedEntity] {
        let types: NSTextCheckingResult.CheckingType = [.date, .address, .link, .phoneNumber, .transitInformation]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: text) else { return nil }
            let matched = String(text[matchRange])
            switch result.resultType {
            case .date:
                return DetectedEntity(kind: .date, text: matched, date: result.date, duration: result.duration)
            case .address:
                return DetectedEntity(kind: .address, text: matched)
            case .link:
                return DetectedEntity(kind: .link, text: matched, url: result.url)
            case .phoneNumber:
                return DetectedEntity(kind: .phoneNumber, text: result.phoneNumber ?? matched)
            case .transitInformation:
                return DetectedEntity(kind: .transit, text: matched)
            default:
                return nil
            }
        }
    }

    /// A date said relative to the day it was written: "tomorrow", "tonight", "next Friday",
    /// "in 3 days", "this weekend".
    static func isRelativeDate(_ text: String) -> Bool {
        let pattern = #"(?i)\b(?:today|tonight|tomorrow|yesterday|now|this|next|last|coming|in\s+\d+\s+(?:minutes?|hours?|days?|weeks?|months?)|\d+\s+(?:minutes?|hours?|days?|weeks?|months?)\s+ago)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: Prices

    /// Separators inside a price are spaces, never line breaks: "$25\n128 reviews" is not 25128.
    static let pricePattern =
        #"(?:(?:CA|A|NZ|US|C)?\$|€|£|¥|₹)[ \x{00A0}]?\d{1,3}(?:[., \x{00A0}\x{202F}]\d{3})*(?:[.,]\d{2})?|\b\d{1,3}(?:[., \x{00A0}\x{202F}]\d{3})*(?:[.,]\d{2})?[ \x{00A0}]?(?:€|\b(?:kr|AUD|USD|EUR|GBP|NZD|CAD)\b)|\b(?:AUD|USD|EUR|GBP|NZD|CAD)[ \x{00A0}]?\d{1,3}(?:[, \x{00A0}\x{202F}]\d{3})*(?:\.\d{2})?"#

    private func prices(in text: String) -> [DetectedEntity] {
        matches(of: Self.pricePattern, in: text).map { matched in
            DetectedEntity(kind: .price, text: matched, amount: Self.amount(in: matched), currencyCode: Self.currency(in: matched))
        }
    }

    static func amount(in price: String) -> Decimal? {
        let digits = price.filter { $0.isNumber || $0 == "." || $0 == "," }
        // The last separator before exactly two digits marks the decimals, either way round
        // ("1,299.00", "1.299,00", "12,50"); every other separator groups thousands.
        var whole = digits
        var decimals = ""
        if let separator = digits.lastIndex(where: { $0 == "." || $0 == "," }), digits.distance(from: separator, to: digits.endIndex) == 3 {
            whole = String(digits[..<separator])
            decimals = String(digits[digits.index(after: separator)...])
        }
        whole.removeAll { $0 == "." || $0 == "," }
        return Decimal(string: decimals.isEmpty ? whole : "\(whole).\(decimals)")
    }

    static func currency(in price: String) -> String? {
        let upper = price.uppercased()
        for code in ["AUD", "NZD", "USD", "CAD", "EUR", "GBP"] where upper.contains(code) {
            return code
        }
        if price.contains("CA$") || price.contains("C$") { return "CAD" }
        if price.contains("A$") { return "AUD" }
        if price.contains("NZ$") { return "NZD" }
        if price.contains("US$") { return "USD" }
        if price.contains("€") { return "EUR" }
        if price.contains("£") { return "GBP" }
        if price.contains("¥") { return "JPY" }
        if price.contains("₹") { return "INR" }
        return nil
    }

    // MARK: Ratings and reviews

    static let ratingPattern = #"(?i)(?:★|⭐){3,5}|\b[1-5][.,]\d\s*(?:★|⭐|stars?\b|out of 5|/\s?5)"#
    static let reviewCountPattern = #"(?i)\b\d{1,3}(?:[,.]\d{3})*(?:\.\d)?[kK]?\+?\s*(?:reviews?|ratings?|Google reviews)\b"#

    private func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            Range(result.range, in: text).map { String(text[$0]) }
        }
    }
}

extension DetectedEntity {
    /// True when a detected date names a day (a weekday, a month, or a numeric date), not just a
    /// time of day like a chat timestamp. Whole words only ("month" isn't Mon, "satisfied" isn't
    /// Sat), and "today" doesn't count: a chat's "Today 9:41" says nothing about which day.
    public var namesADay: Bool {
        guard kind == .date else { return false }
        let lowered = text.lowercased()
        let dayWords = #"\b(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?|tomorrow|tonight|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#
        if lowered.range(of: dayWords, options: .regularExpression) != nil { return true }
        return lowered.range(of: #"\d{1,4}[/.-]\d{1,2}"#, options: .regularExpression) != nil
    }
}
