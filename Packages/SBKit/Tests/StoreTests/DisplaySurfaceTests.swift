import Core
import Foundation
import GRDB
import Testing
@testable import Store

/// M3's launch blocker: no flagged item can reach any display surface.
@Suite struct DisplaySurfaceTests {
    let database: AppDatabase
    let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// A safe item, and one of each kind that must be kept off some or all surfaces.
    let safe: ScreenshotItem
    let nudity: ScreenshotItem
    let sensitive: ScreenshotItem
    let uncertain: ScreenshotItem
    let reference: ScreenshotItem

    init() throws {
        database = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let due = now.addingTimeInterval(2 * 86_400)
        func item(_ name: String, category: ItemCategory, confidence: Double, safe: Bool, nsfw: Bool = false, sensitive: Bool = false) -> ScreenshotItem {
            ScreenshotItem(
                id: name,
                assetLocalID: "asset-\(name)",
                createdAt: now.addingTimeInterval(-86_400),
                category: category,
                confidence: confidence,
                state: .unreviewed,
                expiresAt: due.addingTimeInterval(86_400),
                isSafeToDisplay: safe,
                isNSFWFlagged: nsfw,
                hasSensitiveText: sensitive,
                thumbnailPath: "\(name).jpg",
                extractedText: "gig enmore tickets \(name)",
                updatedAt: now,
                title: name,
                dueDate: due,
                processedAt: now,
                hasDate: true
            )
        }
        safe = item("safe", category: .event, confidence: 0.95, safe: true)
        nudity = item("nudity", category: .event, confidence: 0.95, safe: false, nsfw: true)
        sensitive = item("sensitive", category: .reference, confidence: 0.99, safe: false, sensitive: true)
        uncertain = item("uncertain", category: .other, confidence: 0.4, safe: false)
        reference = item("reference", category: .reference, confidence: 0.95, safe: false)
        try database.save([safe, nudity, sensitive, uncertain, reference])
    }

    @Test func nudityNeverAppearsAnywhere() throws {
        try keepEverything()
        let surfaces = try allSurfaceIDs()
        for (surface, ids) in surfaces {
            #expect(!ids.contains(nudity.id), "nudity reached \(surface)")
        }
    }

    @Test func onlySafeItemsReachTheWidgetRevealAndShareables() throws {
        let widget = try database.widgetCandidates(now: now).map(\.id)
        #expect(widget == [safe.id])

        let examples = try database.revealExamples(category: .event).map(\.id)
        #expect(examples == [safe.id])

        try database.setState(.stillWant, forItem: safe.id, at: now)
        #expect(try database.oldestUndone()?.id == safe.id)
    }

    @Test func sensitiveTextStaysOutOfTriageAndTheWidget() throws {
        #expect(!(try database.triageDeck().map(\.id)).contains(sensitive.id))
        #expect(!(try database.widgetCandidates(now: now).map(\.id)).contains(sensitive.id))
    }

    @Test func triageShowsUncertainItemsButNotReference() throws {
        let deck = try database.triageDeck().map(\.id)
        #expect(deck.contains(uncertain.id))
        #expect(deck.contains(safe.id))
        #expect(!deck.contains(reference.id))
    }

    @Test func searchFindsTextButNeverNudity() throws {
        let results = try database.search("enmore").map(\.id)
        #expect(results.contains(safe.id))
        #expect(!results.contains(nudity.id))
    }

    @Test func widgetSkipsWhatItAlreadyShowedToday() throws {
        try database.markSurfaced(ids: [safe.id], at: now)
        #expect(try database.widgetCandidates(now: now).isEmpty)
        #expect(try database.widgetCandidates(now: now.addingTimeInterval(86_400)).map(\.id) == [safe.id])
    }

    // MARK: Helpers

    /// Marks every item as kept, so the kept-item surfaces have something to show.
    private func keepEverything() throws {
        for item in [safe, nudity, sensitive, uncertain, reference] {
            try database.setState(.stillWant, forItem: item.id, at: now)
        }
    }

    private func allSurfaceIDs() throws -> [String: [String]] {
        let triage = try database.triageDeck().map(\.id)
        let widget = try database.widgetCandidates(now: now).map(\.id)
        let comingUp = try database.comingUp(now: now).map(\.id)
        let stillWant = try database.stillWant().values.flatMap { $0 }.map(\.id)
        let search = try database.search("enmore").map(\.id)
        var examples: [String] = []
        for category in ItemCategory.allCases {
            examples += try database.revealExamples(category: category).map(\.id)
        }
        let oldest = try database.oldestUndone().map { [$0.id] } ?? []
        return [
            "triage": triage,
            "widget": widget,
            "coming up": comingUp,
            "still want": stillWant,
            "search": search,
            "reveal examples": examples,
            "oldest undone": oldest,
        ]
    }
}
