import Core
import Foundation
import Testing
@testable import Store

@Suite struct RecapTests {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func item(daysAgo: Int, state: ItemState = .unreviewed) -> ScreenshotItem {
        ScreenshotItem(
            assetLocalID: UUID().uuidString,
            createdAt: base.addingTimeInterval(-Double(daysAgo) * 86_400),
            category: .place,
            confidence: 0.9,
            state: state,
            processedAt: base
        )
    }

    @Test func showsWhatsNewThenAFewOlderOnes() throws {
        let database = try AppDatabase.inMemory()
        let fresh = (0..<3).map { item(daysAgo: $0) }
        let older = (10..<20).map { item(daysAgo: $0) }
        try database.save(fresh + older + [item(daysAgo: 1, state: .stillWant)])

        let deck = try database.recapDeck(newSince: base.addingTimeInterval(-5 * 86_400), olderLimit: 5)
        #expect(deck.count == 8)
        #expect(deck.prefix(3).map(\.item.id) == fresh.map(\.id))
        // The older ones continue from the newest of them.
        #expect(deck.dropFirst(3).map(\.item.id) == older.prefix(5).map(\.id))
    }

    @Test func remembersTheLastRecapAcrossScans() throws {
        let database = try AppDatabase.inMemory()
        try database.markRecapped(at: base)
        var state = try database.scanState()
        state.lastScanAt = base.addingTimeInterval(60)
        try database.save(state)
        #expect(try database.scanState().lastRecapAt == base)
    }
}
