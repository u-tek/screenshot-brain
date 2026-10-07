import Core
import Foundation
import Testing
@testable import Store
@testable import Triage

@MainActor
@Suite struct TriageModelTests {
    private func item(_ title: String, group: String? = nil, minutesAgo: Double) -> ScreenshotItem {
        ScreenshotItem(
            assetLocalID: title,
            createdAt: Date(timeIntervalSinceNow: -minutesAgo * 60),
            category: .place,
            confidence: 0.9,
            groupID: group,
            title: title,
            processedAt: Date()
        )
    }

    @Test func decidingAGroupDecidesEveryScreenshotInIt() throws {
        let database = try AppDatabase.inMemory()
        let first = item("a", group: "g", minutesAgo: 1)
        let second = item("b", group: "g", minutesAgo: 1.5)
        let other = item("c", minutesAgo: 30)
        try database.save([first, second, other])
        let deck = try database.triageDeck()
        #expect(deck.count == 2)

        let model = TriageModel(cards: deck, database: database)
        model.decide(.done)
        #expect(try database.item(id: first.id)?.state == .done)
        #expect(try database.item(id: second.id)?.state == .done)
        #expect(try database.item(id: other.id)?.state == .unreviewed)
        // The group counts once.
        #expect(try database.score() == Score(done: 1, total: 1))
        #expect(model.tally == TriageTally(done: 1))
    }

    @Test func undoPutsItBack() throws {
        let database = try AppDatabase.inMemory()
        let only = item("a", minutesAgo: 1)
        try database.save([only])
        let model = TriageModel(cards: try database.triageDeck(), database: database)
        model.decide(.drop)
        #expect(model.isFinished)
        model.undo()
        #expect(!model.isFinished)
        #expect(model.tally == TriageTally())
        #expect(try database.item(id: only.id)?.state == .unreviewed)
    }

    @Test func dropCarriesNoPenalty() throws {
        let database = try AppDatabase.inMemory()
        try database.save([item("a", minutesAgo: 1), item("b", minutesAgo: 2), item("c", minutesAgo: 3)])
        let model = TriageModel(cards: try database.triageDeck(), database: database)
        model.decide(.keep)
        model.decide(.drop)
        model.decide(.done)
        #expect(try database.score() == Score(done: 1, total: 2))
    }
}
