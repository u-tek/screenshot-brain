import Core
import Foundation

/// Finds dates, addresses, links, phone numbers and transit details (with `NSDataDetector`), and
/// prices, star ratings and review counts (with regular expressions).
public struct EntityDetector: Sendable {
    public init() {}

    public func entities(in text: String) -> [DetectedEntity] {
        dataDetectorEntities(in: text)
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

    // MARK: Prices

    static let pricePattern =
        #"(?:(?:CA|A|NZ|US|C)?\$|€|£|¥|₹)\s?\d{1,3}(?:[.,\s]\d{3})*(?:[.,]\d{2})?|\b\d{1,3}(?:[.,\s]\d{3})*(?:[.,]\d{2})?\s?(?:€|\b(?:kr|AUD|USD|EUR|GBP|NZD|CAD)\b)|\b(?:AUD|USD|EUR|GBP|NZD|CAD)\s?\d{1,3}(?:[,\s]\d{3})*(?:\.\d{2})?"#

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
    /// time of day like a chat timestamp.
    public var namesADay: Bool {
        guard kind == .date else { return false }
        let lowered = text.lowercased()
        let dayWords = ["mon", "tue", "wed", "thu", "fri", "sat", "sun", "today", "tomorrow", "tonight",
                        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        if dayWords.contains(where: { lowered.contains($0) }) { return true }
        return lowered.range(of: #"\d{1,4}[/.-]\d{1,2}"#, options: .regularExpression) != nil
    }
}
