import Core
import Foundation
import NaturalLanguage

/// Turns text into a vector. Injectable so tests need no language model.
public protocol TextEmbedding {
    /// Nil when the text can't be embedded (unsupported language, no known words).
    func vector(for text: String) -> [Double]?
}

/// Apple's on-device embeddings: the sentence model, or an average of word vectors when the
/// sentence model isn't available. Nothing leaves the phone.
public struct SystemTextEmbedding: TextEmbedding {
    private let sentence: NLEmbedding?
    private let word: NLEmbedding?

    public init() {
        let sentence = NLEmbedding.sentenceEmbedding(for: .english)
        self.sentence = sentence
        self.word = sentence == nil ? NLEmbedding.wordEmbedding(for: .english) : nil
    }

    public func vector(for text: String) -> [Double]? {
        if let sentence {
            return sentence.vector(for: text)
        }
        guard let word else { return nil }
        var sum: [Double] = []
        var count = 0
        for piece in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            guard let v = word.vector(for: String(piece)) else { continue }
            if sum.isEmpty {
                sum = v
            } else if sum.count == v.count {
                for i in 0..<sum.count { sum[i] += v[i] }
            } else {
                continue
            }
            count += 1
        }
        guard count > 0 else { return nil }
        return sum.map { $0 / Double(count) }
    }
}

/// The pure parts of meaning search: what an item is represented as, cosine similarity, the month
/// boost and the blend with keyword hits.
enum MeaningRanking {
    static let threshold = 0.5
    static let monthBoost = 0.2
    static let textPrefixLength = 400

    static func representation(of item: ScreenshotItem) -> String {
        var parts: [String] = []
        if let title = item.title, !title.isEmpty { parts.append(title) }
        parts.append(item.category.rawValue)
        if let text = item.extractedText, !text.isEmpty {
            parts.append(String(text.prefix(textPrefixLength)))
        }
        return parts.joined(separator: ". ")
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0
        var na = 0.0
        var nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    private static let months: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
        "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "apr": 4, "jun": 6, "jul": 7, "aug": 8,
        "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// The first month named in the query ("gigs in November" is 11), or nil.
    static func month(in query: String) -> Int? {
        for word in query.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let month = months[String(word)] { return month }
        }
        return nil
    }

    /// `monthBoost` when the item's due date falls in the month, else 0.
    static func boost(for item: ScreenshotItem, month: Int?, calendar: Calendar) -> Double {
        guard let month, let due = item.dueDate else { return 0 }
        return calendar.component(.month, from: due) == month ? monthBoost : 0
    }

    /// Keyword hits first, in their order, then meaning matches at or above the threshold by
    /// descending score. Each id once. At most `limit`.
    static func blend(
        keyword: [ScreenshotItem],
        scored: [(item: ScreenshotItem, score: Double)],
        threshold: Double = MeaningRanking.threshold,
        limit: Int
    ) -> [ScreenshotItem] {
        var seen = Set<String>()
        var out: [ScreenshotItem] = []
        for item in keyword where seen.insert(item.id).inserted {
            out.append(item)
        }
        let meaning = scored
            .filter { $0.score >= threshold }
            .sorted { $0.score > $1.score }
        for entry in meaning where seen.insert(entry.item.id).inserted {
            out.append(entry.item)
        }
        return Array(out.prefix(limit))
    }
}

/// "Ask your screenshots": finds items by meaning as well as by keyword. Item vectors are cached
/// by id and `updatedAt`, so repeat searches only embed the query. The actor keeps the model and
/// the cache off the main actor.
public actor MeaningSearch {
    private struct Cached {
        let updatedAt: Date
        let vector: [Double]?
    }

    private let makeEmbedding: @Sendable () -> any TextEmbedding
    private var embedding: (any TextEmbedding)?
    private var cache: [String: Cached] = [:]

    public init(makeEmbedding: @escaping @Sendable () -> any TextEmbedding = { SystemTextEmbedding() }) {
        self.makeEmbedding = makeEmbedding
    }

    /// Reads candidates from the database and ranks them. Falls back to keyword results alone when
    /// nothing can be embedded.
    public func search(
        _ query: String,
        in database: AppDatabase,
        limit: Int = 50,
        calendar: Calendar = .current
    ) throws -> [ScreenshotItem] {
        let keyword = (try? database.search(query, limit: limit)) ?? []
        let candidates = try database.meaningCandidates()
        return rank(query, keyword: keyword, candidates: candidates, limit: limit, calendar: calendar)
    }

    /// The ranking without the database, for tests.
    func rank(
        _ query: String,
        keyword: [ScreenshotItem],
        candidates: [ScreenshotItem],
        limit: Int = 50,
        calendar: Calendar = .current
    ) -> [ScreenshotItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let embedder = currentEmbedding()
        guard let queryVector = embedder.vector(for: trimmed) else {
            return Array(keyword.prefix(limit))
        }
        let month = MeaningRanking.month(in: trimmed)
        var scored: [(item: ScreenshotItem, score: Double)] = []
        for item in candidates where !item.isNSFWFlagged {
            guard let vector = vector(for: item, using: embedder) else { continue }
            let score = MeaningRanking.cosine(queryVector, vector)
                + MeaningRanking.boost(for: item, month: month, calendar: calendar)
            scored.append((item, score))
        }
        return MeaningRanking.blend(keyword: keyword, scored: scored, limit: limit)
    }

    private func currentEmbedding() -> any TextEmbedding {
        if let embedding { return embedding }
        let made = makeEmbedding()
        embedding = made
        return made
    }

    private func vector(for item: ScreenshotItem, using embedder: any TextEmbedding) -> [Double]? {
        if let hit = cache[item.id], hit.updatedAt == item.updatedAt { return hit.vector }
        let vector = embedder.vector(for: MeaningRanking.representation(of: item))
        cache[item.id] = Cached(updatedAt: item.updatedAt, vector: vector)
        return vector
    }
}
