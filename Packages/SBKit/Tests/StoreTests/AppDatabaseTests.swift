import Core
import Foundation
import GRDB
import Testing
@testable import Store

@Suite struct AppDatabaseTests {
    let database: AppDatabase

    init() throws {
        database = try AppDatabase.inMemory()
    }

    @Test func migrationsCreateEveryTable() throws {
        let tables = [
            ScreenshotItem.databaseTableName,
            ItemGroup.databaseTableName,
            OnboardingAnswers.databaseTableName,
            ScoreSnapshot.databaseTableName,
            RevealSnapshot.databaseTableName,
        ]
        let existing = try database.reader.read { db in
            try tables.filter { try db.tableExists($0) }
        }
        #expect(existing == tables)
    }

    @Test func itemRoundTripKeepsEntitiesAndPalette() throws {
        let item = Fixture.item(
            entities: [
                DetectedEntity(kind: .date, text: "Fri 14 Nov, 8pm", date: Fixture.date(days: 9)),
                DetectedEntity(kind: .price, text: "$24", amount: 24, currencyCode: "AUD"),
                DetectedEntity(kind: .link, text: "tix.example.com", url: URL(string: "https://tix.example.com")),
            ],
            palette: [
                PaletteColor(red: 0.91, green: 0.27, blue: 0.55, weight: 0.6),
                PaletteColor(red: 0.29, green: 0.25, blue: 0.82, weight: 0.4),
            ]
        )
        try database.save(item)

        let fetched = try #require(try database.item(id: item.id))
        #expect(fetched == item)
    }

    @Test func newItemsAreNotSafeToDisplayUntilSafetyClearsThem() {
        let item = ScreenshotItem(assetLocalID: "asset", createdAt: Fixture.date(days: 0))
        #expect(item.isSafeToDisplay == false)
        #expect(item.state == .unreviewed)
        #expect(item.category == .other)
    }

    @Test func assetLocalIDIsUnique() throws {
        try database.save(Fixture.item(assetLocalID: "same"))
        #expect(throws: DatabaseError.self) {
            try database.save(Fixture.item(assetLocalID: "same"))
        }
    }

    @Test func setStateRecordsWhenItChanged() throws {
        let item = Fixture.item()
        try database.save(item)
        let changedAt = Fixture.date(days: 3)

        try database.setState(.done, forItem: item.id, at: changedAt)

        let fetched = try #require(try database.item(id: item.id))
        #expect(fetched.state == .done)
        #expect(fetched.stateChangedAt == changedAt)
        #expect(fetched.updatedAt == changedAt)
    }

    @Test func scoreCountsKeptAndDoneOncePerGroupAndIgnoresDropped() throws {
        let group = ItemGroup(createdAt: Fixture.date(days: 0), itemCount: 2, updatedAt: Fixture.date(days: 0))
        try database.writer.write { db in try group.insert(db) }

        try database.save(Fixture.item(state: .done))
        try database.save(Fixture.item(groupID: group.id, state: .done))
        try database.save(Fixture.item(groupID: group.id, state: .done))
        try database.save(Fixture.item(state: .stillWant))
        try database.save(Fixture.item(state: .stillWant))
        try database.save(Fixture.item(state: .dropped))
        try database.save(Fixture.item(state: .unreviewed))
        try database.save(Fixture.item(category: .reference, state: .reference))

        #expect(try database.score() == Score(done: 2, total: 4))
    }

    @Test func keptNearDuplicatesShowOnce() throws {
        let group = ItemGroup(createdAt: Fixture.date(days: 0), itemCount: 2, updatedAt: Fixture.date(days: 0))
        try database.writer.write { db in try group.insert(db) }
        for _ in 0..<2 {
            var item = Fixture.item(groupID: group.id, state: .stillWant)
            item.dueDate = Fixture.date(days: 2)
            item.processedAt = Fixture.date(days: 0)
            try database.save(item)
        }
        try database.save(Fixture.item(state: .stillWant))

        #expect(try database.score() == Score(done: 0, total: 2))
        #expect(try database.stillWant()[.event]?.count == 2)
        #expect(try database.comingUp(now: Fixture.date(days: 0)).count == 1)
    }

    @Test func onboardingResumesFromTheSavedStep() throws {
        #expect(try database.onboardingAnswers() == nil)

        var answers = OnboardingAnswers(step: .questions, guessedScreenshotCount: 150, updatedAt: Fixture.date(days: 0))
        try database.save(answers)
        answers.step = .reveal
        answers.guessedTopCategory = .product
        try database.save(answers)

        let fetched = try #require(try database.onboardingAnswers())
        #expect(fetched.step == .reveal)
        #expect(fetched.guessedScreenshotCount == 150)
        #expect(fetched.guessedTopCategory == .product)
        let rowCount = try database.reader.read { db in try OnboardingAnswers.fetchCount(db) }
        #expect(rowCount == 1)
    }

    @Test func revealSnapshotStoresItsStats() throws {
        let snapshot = RevealSnapshot(
            kind: .firstOpen,
            periodStart: Fixture.date(days: -60),
            periodEnd: Fixture.date(days: 0),
            createdAt: Fixture.date(days: 0),
            stats: RevealStats(
                totalScreenshots: 214,
                peakHour: 0,
                busiestDay: Fixture.date(days: -12),
                busiestDayCount: 19,
                categoryCounts: [ItemCategory.place.rawValue: 61, ItemCategory.product.rawValue: 40],
                datedCount: 23
            )
        )
        try database.writer.write { db in try snapshot.insert(db) }

        let fetched = try database.reader.read { db in try RevealSnapshot.fetchOne(db, key: snapshot.id) }
        #expect(fetched == snapshot)
        #expect(fetched?.stats.count(for: .place) == 61)
        #expect(fetched?.stats.count(for: .recipe) == 0)
    }
}

private enum Fixture {
    /// Whole seconds, so dates survive the database's millisecond precision exactly.
    static func date(days: Int) -> Date {
        Date(timeIntervalSince1970: 1_760_000_000 + TimeInterval(days * 86_400))
    }

    static func item(
        assetLocalID: String = UUID().uuidString,
        category: ItemCategory = .event,
        entities: [DetectedEntity] = [],
        groupID: String? = nil,
        state: ItemState = .unreviewed,
        palette: [PaletteColor] = []
    ) -> ScreenshotItem {
        ScreenshotItem(
            assetLocalID: assetLocalID,
            createdAt: date(days: 0),
            category: category,
            confidence: 0.97,
            entities: entities,
            groupID: groupID,
            state: state,
            palette: palette,
            updatedAt: date(days: 0)
        )
    }
}
