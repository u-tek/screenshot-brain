import Core
import Foundation
import Testing
@testable import Store

/// Maps known words to fixed 2-D vectors: "food" words point one way, "music" words the other.
private struct FakeEmbedding: TextEmbedding {
    var supported = true

    func vector(for text: String) -> [Double]? {
        guard supported else { return nil }
        let t = text.lowercased()
        if t.contains("pasta") || t.contains("recipe") { return [1, 0] }
        if t.contains("gig") || t.contains("concert") { return [0, 1] }
        return [0.7, 0.7]
    }
}

@Suite struct MeaningSearchTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func item(
        _ id: String,
        title: String,
        category: ItemCategory = .other,
        dueDate: Date? = nil,
        nsfw: Bool = false
    ) -> ScreenshotItem {
        ScreenshotItem(
            id: id,
            assetLocalID: id,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            category: category,
            isNSFWFlagged: nsfw,
            updatedAt: Date(timeIntervalSince1970: 1_760_000_000),
            title: title,
            dueDate: dueDate,
            processedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    /// 15 November 2026, 12:00 UTC.
    private let november = Date(timeIntervalSince1970: 1_794_744_000)
    /// 15 March 2026, 12:00 UTC.
    private let march = Date(timeIntervalSince1970: 1_773_576_000)

    // MARK: - Month

    @Test func findsAMonthNameInAQuery() {
        #expect(MeaningRanking.month(in: "gigs in November") == 11)
        #expect(MeaningRanking.month(in: "dec parties") == 12)
        #expect(MeaningRanking.month(in: "that pasta thing") == nil)
    }

    @Test func boostsOnlyItemsDueInThatMonth() {
        let inNov = item("a", title: "Gig", dueDate: november)
        let inMar = item("b", title: "Gig", dueDate: march)
        let undated = item("c", title: "Gig")
        #expect(MeaningRanking.boost(for: inNov, month: 11, calendar: calendar) == MeaningRanking.monthBoost)
        #expect(MeaningRanking.boost(for: inMar, month: 11, calendar: calendar) == 0)
        #expect(MeaningRanking.boost(for: undated, month: 11, calendar: calendar) == 0)
        #expect(MeaningRanking.boost(for: inNov, month: nil, calendar: calendar) == 0)
    }

    @Test func theBoostLiftsANovemberGigAboveAnEqualMarchGig() async {
        let search = MeaningSearch(makeEmbedding: { FakeEmbedding() })
        let nov = item("nov", title: "Gig at the Enmore", dueDate: november)
        let mar = item("mar", title: "Gig at the Enmore", dueDate: march)
        let ranked = await search.rank("gigs in November", keyword: [], candidates: [mar, nov], calendar: calendar)
        #expect(ranked.map(\.id) == ["nov", "mar"])
    }

    // MARK: - Blending

    @Test func keywordHitsComeFirstThenMeaningMatches() {
        let k = item("k", title: "keyword")
        let strong = item("s", title: "strong")
        let weak = item("w", title: "weak")
        let below = item("b", title: "below")
        let out = MeaningRanking.blend(
            keyword: [k],
            scored: [(weak, 0.6), (below, 0.1), (strong, 0.9)],
            limit: 50
        )
        #expect(out.map(\.id) == ["k", "s", "w"])
    }

    @Test func anItemInBothListsAppearsOnce() {
        let a = item("a", title: "A")
        let out = MeaningRanking.blend(keyword: [a, a], scored: [(a, 0.9)], limit: 50)
        #expect(out.map(\.id) == ["a"])
    }

    @Test func blendingStopsAtTheLimit() {
        let items = (0..<10).map { item("i\($0)", title: "T") }
        let out = MeaningRanking.blend(keyword: items, scored: [], limit: 3)
        #expect(out.count == 3)
    }

    @Test func nsfwFlaggedCandidatesAreNeverReturned() async {
        let search = MeaningSearch(makeEmbedding: { FakeEmbedding() })
        let hidden = item("x", title: "Pasta recipe", nsfw: true)
        let ranked = await search.rank("pasta", keyword: [], candidates: [hidden])
        #expect(ranked.isEmpty)
    }

    @Test func meaningFindsAnItemTheKeywordsMissed() async {
        let search = MeaningSearch(makeEmbedding: { FakeEmbedding() })
        let pasta = item("p", title: "Creamy pasta bake", category: .recipe)
        let gig = item("g", title: "Concert tickets", category: .event)
        let ranked = await search.rank("that pasta thing", keyword: [], candidates: [gig, pasta])
        #expect(ranked.first?.id == "p")
    }

    // MARK: - Fallback

    @Test func withNoEmbeddingOnlyKeywordResultsReturn() async {
        let search = MeaningSearch(makeEmbedding: { FakeEmbedding(supported: false) })
        let k = item("k", title: "keyword")
        let other = item("o", title: "other")
        let ranked = await search.rank("anything", keyword: [k], candidates: [other])
        #expect(ranked.map(\.id) == ["k"])
    }

    @Test func aBlankQueryReturnsNothing() async {
        let search = MeaningSearch(makeEmbedding: { FakeEmbedding() })
        let ranked = await search.rank("   ", keyword: [], candidates: [item("a", title: "A")])
        #expect(ranked.isEmpty)
    }

    // MARK: - Representation and similarity

    @Test func representationIsTitleCategoryAndTheFirst400Characters() {
        var i = item("a", title: "Pasta")
        i.category = .recipe
        i.extractedText = String(repeating: "x", count: 1000)
        let text = MeaningRanking.representation(of: i)
        #expect(text.hasPrefix("Pasta. recipe. "))
        #expect(text.count == "Pasta. recipe. ".count + 400)
    }

    @Test func cosineOfParallelAndOrthogonalVectors() {
        #expect(abs(MeaningRanking.cosine([1, 0], [2, 0]) - 1) < 1e-9)
        #expect(MeaningRanking.cosine([1, 0], [0, 1]) == 0)
        #expect(MeaningRanking.cosine([1, 0], [1, 0, 0]) == 0)
    }
}
