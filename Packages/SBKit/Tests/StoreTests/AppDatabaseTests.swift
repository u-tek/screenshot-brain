import CloudKit
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
            AccuracyRecord.databaseTableName,
            ScanState.databaseTableName,
            SyncState.databaseTableName,
            PendingRemoteState.databaseTableName,
            AppDatabase.searchTableName,
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

    @Test func savingReadResultsKeepsWhatChangedMeanwhile() throws {
        let unread = Fixture.item(state: .unreviewed)
        try database.save(unread)
        // While the screenshot was being read: it was decided, shown, grouped and given a cloud ID.
        let group = ItemGroup(createdAt: Fixture.date(days: 0), itemCount: 2, updatedAt: Fixture.date(days: 0))
        try database.writer.write { db in try group.insert(db) }
        try database.setState(.stillWant, forItem: unread.id, at: Fixture.date(days: 1))
        try database.markSurfaced(ids: [unread.id], at: Fixture.date(days: 1))
        try database.saveGroups([group.id: [unread, Fixture.item()]])

        var result = unread
        result.category = .place
        result.extractedText = "Bar Sazerac"
        result.processedAt = Fixture.date(days: 2)
        result.updatedAt = Fixture.date(days: 2)
        try database.saveReadResults([result])

        let saved = try #require(try database.item(id: unread.id))
        #expect(saved.category == .place)
        #expect(saved.extractedText == "Bar Sazerac")
        #expect(saved.processedAt == Fixture.date(days: 2))
        #expect(saved.state == .stillWant)
        #expect(saved.stateChangedAt == Fixture.date(days: 1))
        #expect(saved.lastSurfacedAt == Fixture.date(days: 1))
        #expect(saved.groupID == group.id)
    }

    @Test func savingReadResultsFilesAwayWhatIsNothingToDo() throws {
        let item = Fixture.item(category: .other, state: .unreviewed)
        try database.save(item)
        var result = item
        result.category = .message
        result.processedAt = Fixture.date(days: 1)
        try database.saveReadResults([result])
        let saved = try #require(try database.item(id: item.id))
        #expect(saved.state == .reference)
        #expect(saved.stateChangedAt == nil)
    }

    @Test func savingReadResultsDoesNotBringBackADeletedItem() throws {
        let item = Fixture.item(assetLocalID: "gone")
        try database.save(item)
        try database.deleteItems(assetLocalIDs: ["gone"], thumbnailDirectory: FileManager.default.temporaryDirectory)
        try database.saveReadResults([item])
        #expect(try database.item(id: item.id) == nil)
    }

    @Test func deletingItemsRemovesTheirThumbnails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["a.jpg", "b.jpg"] {
            try Data([0x00]).write(to: directory.appendingPathComponent(name))
        }
        var dropped = Fixture.item(assetLocalID: "asset-a", state: .dropped)
        dropped.thumbnailPath = "a.jpg"
        var kept = Fixture.item(assetLocalID: "asset-b", state: .stillWant)
        kept.thumbnailPath = "b.jpg"
        try database.save([dropped, kept])

        try database.deleteItems(assetLocalIDs: ["asset-a"], thumbnailDirectory: directory)

        #expect(try database.item(id: dropped.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("b.jpg").path))
    }

    @Test func cloudIDsAreFilledInLaterAndNeverOverwritten() throws {
        let missing = Fixture.item(assetLocalID: "asset-1")
        var known = Fixture.item(assetLocalID: "asset-2")
        known.cloudID = "cloud-2"
        try database.save([missing, known])
        let since = Fixture.date(days: -10)
        #expect(try database.assetIDsWithoutCloudID(createdAfter: since) == ["asset-1"])

        try database.setCloudIDs(["asset-1": "cloud-1", "asset-2": "other"], now: Fixture.date(days: 1))

        #expect(try database.item(id: missing.id)?.cloudID == "cloud-1")
        #expect(try database.item(id: missing.id)?.updatedAt == Fixture.date(days: 1))
        #expect(try database.item(id: known.id)?.cloudID == "cloud-2")
        #expect(try database.assetIDsWithoutCloudID(createdAfter: since).isEmpty)
    }

    @Test func markingAScanKeepsTheRecapTime() throws {
        try database.markRecapped(at: Fixture.date(days: 1))
        try database.markScanned(at: Fixture.date(days: 2))
        let state = try database.scanState()
        #expect(state.lastRecapAt == Fixture.date(days: 1))
        #expect(state.lastScanAt == Fixture.date(days: 2))
    }

    @Test func groupsCountEveryMemberInTheDatabase() throws {
        let first = Fixture.item(), second = Fixture.item(), third = Fixture.item()
        try database.save([first, second, third])
        try database.saveGroups(["g": [first, second]])
        try database.saveGroups(["g": [second, third]])
        let group = try database.reader.read { db in try ItemGroup.fetchOne(db, key: "g") }
        #expect(group?.itemCount == 3)
        #expect(try database.item(id: third.id)?.groupID == "g")
    }

    @Test func widgetCandidatesAreOrderedAndLimitedInTheDatabase() throws {
        let now = Fixture.date(days: 0)
        func safe(_ name: String, state: ItemState, expires: Date?, changed: Date?) -> ScreenshotItem {
            var item = Fixture.item(assetLocalID: name, state: state)
            item.isSafeToDisplay = true
            item.thumbnailPath = "\(name).jpg"
            item.expiresAt = expires
            item.stateChangedAt = changed
            return item
        }
        let kept = safe("kept", state: .stillWant, expires: nil, changed: Fixture.date(days: -9))
        let later = safe("later", state: .unreviewed, expires: Fixture.date(days: 6), changed: nil)
        let sooner = safe("sooner", state: .unreviewed, expires: Fixture.date(days: 3), changed: nil)
        let open = safe("open", state: .unreviewed, expires: nil, changed: nil)
        let expired = safe("expired", state: .unreviewed, expires: Fixture.date(days: -1), changed: nil)
        try database.save([kept, later, sooner, open, expired])

        #expect(try database.widgetCandidates(now: now).map(\.assetLocalID) == ["sooner", "later", "open", "kept"])
        #expect(try database.widgetCandidates(now: now, limit: 2).map(\.assetLocalID) == ["sooner", "later"])
    }

    @Test func rejectedPushesAreNotRetriedButFlakyOnesAre() {
        #expect(CloudSync.isRetryable(CKError(.networkUnavailable)))
        #expect(CloudSync.isRetryable(CKError(.requestRateLimited)))
        #expect(!CloudSync.isRetryable(CKError(.invalidArguments)))
        #expect(!CloudSync.isRetryable(CKError(.serverRejectedRequest)))
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
