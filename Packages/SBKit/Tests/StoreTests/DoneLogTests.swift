import Core
import Foundation
import GRDB
import Testing
@testable import Store

@Suite struct DoneLogTests {
    let database: AppDatabase

    init() throws {
        database = try AppDatabase.inMemory()
    }

    // MARK: - Recording

    @Test func decidingAnItemDoneAddsOneEntryWithItsTitleAndKind() throws {
        let item = DoneLogFixture.item(title: "Gig at the Enmore", category: .event)
        try database.save(item)
        let decidedAt = DoneLogFixture.date(days: 1)

        try database.decide(.done, forItem: item.id, at: decidedAt)

        let log = try database.doneLog()
        #expect(log.count == 1)
        let entry = try #require(log.first)
        #expect(entry.itemID == item.id)
        #expect(entry.title == "Gig at the Enmore")
        #expect(entry.category == .event)
        #expect(entry.doneAt == decidedAt)
    }

    /// A group is done once, and the entry remembers the item that was decided, not the first of
    /// the group.
    @Test func decidingAGroupDoneAddsOneEntryMadeFromTheItemDecided() throws {
        let group = try insertGroup()
        let first = DoneLogFixture.item(title: "First shot", groupID: group.id)
        let second = DoneLogFixture.item(title: "Second shot", groupID: group.id)
        let third = DoneLogFixture.item(title: "Third shot", groupID: group.id)
        try database.save([first, second, third])

        try database.decide(.done, forItem: third.id, at: DoneLogFixture.date(days: 1))

        let members = try database.items(ids: [first.id, second.id, third.id])
        #expect(members.allSatisfy { $0.state == .done })
        let log = try database.doneLog()
        #expect(log.count == 1)
        let entry = try #require(log.first)
        #expect(entry.itemID == third.id)
        #expect(entry.groupKey == group.id)
        #expect(entry.title == "Third shot")
    }

    @Test func settingTheStateToDoneAlsoRecordsAnEntry() throws {
        let item = DoneLogFixture.item(title: "Try the ramen place", category: .place)
        try database.save(item)
        let changedAt = DoneLogFixture.date(days: 2)

        try database.setState(.done, forItem: item.id, at: changedAt)

        let entry = try #require(try database.doneLog().first)
        #expect(entry.itemID == item.id)
        #expect(entry.title == "Try the ramen place")
        #expect(entry.category == .place)
        #expect(entry.doneAt == changedAt)
    }

    @Test func aDoneStateFromAnotherDeviceRecordsAnEntry() throws {
        let item = DoneLogFixture.item(
            title: "Try the ramen place",
            category: .place,
            cloudID: "cloud-ramen",
            stateChangedAt: DoneLogFixture.date(days: 1)
        )
        try database.save(item)
        let changedAt = DoneLogFixture.date(days: 2)

        try database.applyRemoteState(cloudID: "cloud-ramen", state: .done, changedAt: changedAt)

        let entry = try #require(try database.doneLog().first)
        #expect(entry.itemID == item.id)
        #expect(entry.title == "Try the ramen place")
        #expect(entry.doneAt == changedAt)
    }

    @Test func anItemFlaggedForNudityWhenDecidedDoneGetsNoEntry() throws {
        let item = DoneLogFixture.item(isNSFWFlagged: true)
        try database.save(item)

        try database.decide(.done, forItem: item.id, at: DoneLogFixture.date(days: 1))

        let entryCount = try database.reader.read { db in try DoneEntry.fetchCount(db) }
        #expect(entryCount == 0)
        #expect(try database.doneLog().isEmpty)
    }

    // MARK: - Undoing

    @Test func decidingItSomethingElseAfterwardsRemovesTheEntry() throws {
        let item = DoneLogFixture.item()
        try database.save(item)
        try database.decide(.done, forItem: item.id, at: DoneLogFixture.date(days: 1))
        #expect(try database.doneLog().count == 1)

        try database.decide(.stillWant, forItem: item.id, at: DoneLogFixture.date(days: 2))

        #expect(try database.doneLog().isEmpty)
    }

    @Test func undoingADoneDecisionRemovesTheEntry() throws {
        let item = DoneLogFixture.item()
        try database.save(item)
        let previous = try database.decide(.done, forItem: item.id, at: DoneLogFixture.date(days: 1))
        #expect(try database.doneLog().count == 1)

        try database.undoDecision(restoring: previous, at: DoneLogFixture.date(days: 2))

        #expect(try database.doneLog().isEmpty)
        let fetched = try #require(try database.item(id: item.id))
        #expect(fetched.state == .unreviewed)
    }

    @Test func undoingAnUndoneDecisionRestoresTheEntry() throws {
        let item = DoneLogFixture.item(title: "Book the Enmore gig")
        try database.save(item)
        let doneAt = DoneLogFixture.date(days: 1)
        try database.decide(.done, forItem: item.id, at: doneAt)
        let previous = try database.decide(.stillWant, forItem: item.id, at: DoneLogFixture.date(days: 2))
        #expect(try database.doneLog().isEmpty)

        try database.undoDecision(restoring: previous, at: DoneLogFixture.date(days: 3))

        let entry = try #require(try database.doneLog().first)
        #expect(entry.itemID == item.id)
        #expect(entry.title == "Book the Enmore gig")
        // It was done when it was done, not when the undo happened.
        #expect(entry.doneAt == doneAt)
    }

    // MARK: - Reading

    /// People delete a screenshot once they've done the thing; the log keeps what they did.
    @Test func deletingTheScreenshotKeepsTheEntryWithoutAnItem() throws {
        let item = DoneLogFixture.item(title: "Book the Enmore gig")
        try database.save(item)
        try database.decide(.done, forItem: item.id, at: DoneLogFixture.date(days: 1))

        try database.deleteItems(assetLocalIDs: [item.assetLocalID])

        #expect(try database.item(id: item.id) == nil)
        let log = try database.doneLog()
        #expect(log.count == 1)
        let entry = try #require(log.first)
        #expect(entry.itemID == nil)
        #expect(entry.title == "Book the Enmore gig")
    }

    @Test func theLogListsNewestFirst() throws {
        let early = DoneLogFixture.item(title: "Early")
        let late = DoneLogFixture.item(title: "Late")
        let middle = DoneLogFixture.item(title: "Middle")
        try database.save([early, late, middle])

        try database.decide(.done, forItem: early.id, at: DoneLogFixture.date(days: 1))
        try database.decide(.done, forItem: late.id, at: DoneLogFixture.date(days: 5))
        try database.decide(.done, forItem: middle.id, at: DoneLogFixture.date(days: 3))

        #expect(try database.doneLog().map(\.title) == ["Late", "Middle", "Early"])
    }

    @Test func theLogLeavesOutAnEntryWhoseItemIsLaterFlaggedForNudity() throws {
        let kept = DoneLogFixture.item(title: "Kept")
        let flagged = DoneLogFixture.item(title: "Flagged")
        try database.save([kept, flagged])
        try database.decide(.done, forItem: kept.id, at: DoneLogFixture.date(days: 1))
        try database.decide(.done, forItem: flagged.id, at: DoneLogFixture.date(days: 2))
        #expect(try database.doneLog().count == 2)

        var rescanned = try #require(try database.item(id: flagged.id))
        rescanned.isNSFWFlagged = true
        try database.save(rescanned)

        #expect(try database.doneLog().map(\.title) == ["Kept"])
    }

    @Test func aNearDuplicateFindsTheEntryItsGroupMade() throws {
        let group = try insertGroup()
        let decided = DoneLogFixture.item(title: "The one decided", groupID: group.id)
        let lookalike = DoneLogFixture.item(title: "The lookalike", groupID: group.id)
        let stranger = DoneLogFixture.item(title: "Not in the group")
        try database.save([decided, lookalike, stranger])
        try database.decide(.done, forItem: decided.id, at: DoneLogFixture.date(days: 1))

        let made = try #require(try database.doneEntry(forItem: decided.id))
        let found = try #require(try database.doneEntry(forItem: lookalike.id))
        #expect(found.id == made.id)
        #expect(found.itemID == decided.id)
        #expect(try database.doneEntry(forItem: stranger.id) == nil)
    }

    // MARK: - Remembering

    @Test func aNoteIsTrimmedAndABlankOneClearsIt() throws {
        let entry = try newEntry()
        let notedAt = DoneLogFixture.date(days: 2)

        try database.setNote("  Loved the second set \n", forEntry: entry.id, at: notedAt)

        let noted = try stored(entry)
        #expect(noted.note == "Loved the second set")
        #expect(noted.updatedAt == notedAt)
        #expect(noted.hasMemory)

        try database.setNote(" \n  ", forEntry: entry.id, at: DoneLogFixture.date(days: 3))

        let cleared = try stored(entry)
        #expect(cleared.note == nil)
        #expect(!cleared.hasMemory)
    }

    @Test func settingAPhotoReturnsTheFileNameItReplaced() throws {
        let entry = try newEntry()

        #expect(try database.setPhoto("first.jpg", forEntry: entry.id) == nil)
        #expect(try database.setPhoto("second.jpg", forEntry: entry.id) == "first.jpg")
        #expect(try stored(entry).photoName == "second.jpg")

        // The same name again replaces nothing, so there is no file for the caller to delete.
        #expect(try database.setPhoto("second.jpg", forEntry: entry.id) == nil)
        #expect(try stored(entry).photoName == "second.jpg")

        #expect(try database.setPhoto(nil, forEntry: entry.id) == "second.jpg")
        #expect(try stored(entry).photoName == nil)
    }

    // MARK: - Erasing

    @Test func erasingEverythingEmptiesTheLog() throws {
        let item = DoneLogFixture.item()
        try database.save(item)
        try database.decide(.done, forItem: item.id, at: DoneLogFixture.date(days: 1))
        #expect(try database.doneLog().count == 1)

        try database.eraseAll()

        let entryCount = try database.reader.read { db in try DoneEntry.fetchCount(db) }
        #expect(entryCount == 0)
        #expect(try database.doneLog().isEmpty)
    }

    // MARK: - Sharing

    @Test func onlySafeEntriesOfActionableKindsAreShareable() {
        #expect(DoneLogFixture.entry().isShareable)
        #expect(DoneLogFixture.entry(category: .place).isShareable)
        #expect(!DoneLogFixture.entry(isSafeToDisplay: false).isShareable)
        #expect(!DoneLogFixture.entry(hasSensitiveText: true).isShareable)
        #expect(!DoneLogFixture.entry(category: .message).isShareable)
        #expect(!DoneLogFixture.entry(category: .reference).isShareable)
    }

    // MARK: - Helpers

    // MARK: - Keeping up

    /// The item that made the entry is deleted; its near-duplicate is still there. Un-doing the
    /// near-duplicate empties the group, so the entry goes.
    @Test func undoingTheLastDoneNearDuplicateRemovesTheEntry() throws {
        let group = try insertGroup()
        let decided = DoneLogFixture.item(title: "First shot", groupID: group.id)
        let other = DoneLogFixture.item(title: "Second shot", groupID: group.id)
        try database.save([decided, other])
        try database.decide(.done, forItem: decided.id, at: DoneLogFixture.date(days: 1))
        try database.deleteItems(assetLocalIDs: [decided.assetLocalID])

        try database.setState(.stillWant, forItem: other.id, at: DoneLogFixture.date(days: 2))

        #expect(try database.doneLog().isEmpty)
    }

    /// One near-duplicate un-done while another is still done: the group is still done.
    @Test func aGroupWithSomethingStillDoneKeepsItsEntry() throws {
        let group = try insertGroup()
        let decided = DoneLogFixture.item(title: "First shot", groupID: group.id)
        let other = DoneLogFixture.item(title: "Second shot", groupID: group.id)
        try database.save([decided, other])
        try database.decide(.done, forItem: decided.id, at: DoneLogFixture.date(days: 1))

        try database.setState(.stillWant, forItem: other.id, at: DoneLogFixture.date(days: 2))

        #expect(try database.doneLog().map(\.itemID) == [decided.id])
    }

    /// A state from another device can arrive for a screenshot this device hasn't read yet. It
    /// waits for the read, so the entry has a title and has been through the safety checks.
    @Test func anUnreadItemIsLoggedOnceItHasBeenRead() throws {
        var item = DoneLogFixture.item(title: nil, category: .other, cloudID: "cloud-gig")
        item.processedAt = nil
        try database.save(item)
        try database.applyRemoteState(cloudID: "cloud-gig", state: .done, changedAt: DoneLogFixture.date(days: 1))
        #expect(try database.doneLog().isEmpty)

        var read = try #require(try database.item(id: item.id))
        read.title = "Gig at the Enmore"
        read.category = .event
        read.isSafeToDisplay = true
        read.processedAt = DoneLogFixture.date(days: 2)
        try database.save([read])

        let entry = try #require(try database.doneLog().first)
        #expect(entry.title == "Gig at the Enmore")
        #expect(entry.category == .event)
        #expect(entry.isShareable)
    }

    /// Read again and found to hold something sensitive: the entry follows, so it's no longer
    /// shareable.
    @Test func anEntryFollowsItsItemWhenItsReadAgain() throws {
        var item = DoneLogFixture.item(title: "Gig at the Enmore")
        item.isSafeToDisplay = true
        try database.save(item)
        try database.decide(.done, forItem: item.id, at: DoneLogFixture.date(days: 1))
        #expect(try database.doneLog().first?.isShareable == true)

        var reread = try #require(try database.item(id: item.id))
        reread.hasSensitiveText = true
        try database.save([reread])

        let entry = try #require(try database.doneLog().first)
        #expect(entry.hasSensitiveText)
        #expect(!entry.isShareable)
    }

    @Test func photosStillInUseAreListed() throws {
        let item = DoneLogFixture.item()
        try database.save(item)
        try database.decide(.done, forItem: item.id, at: DoneLogFixture.date(days: 1))
        let entry = try #require(try database.doneLog().first)
        #expect(try database.memoryPhotoNames().isEmpty)

        try database.setPhoto("kept.jpg", forEntry: entry.id)

        #expect(try database.memoryPhotoNames() == ["kept.jpg"])
    }

    private func insertGroup() throws -> ItemGroup {
        let group = ItemGroup(createdAt: DoneLogFixture.date(days: 0), itemCount: 3, updatedAt: DoneLogFixture.date(days: 0))
        try database.writer.write { db in try group.insert(db) }
        return group
    }

    /// The entry for an item just done, as the log first has it.
    private func newEntry() throws -> DoneEntry {
        let item = DoneLogFixture.item()
        try database.save(item)
        try database.decide(.done, forItem: item.id, at: DoneLogFixture.date(days: 1))
        return try #require(try database.doneEntry(forItem: item.id))
    }

    /// The entry as the database has it now.
    private func stored(_ entry: DoneEntry) throws -> DoneEntry {
        let id = entry.id
        let fetched = try database.reader.read { db in try DoneEntry.fetchOne(db, key: id) }
        return try #require(fetched)
    }
}

private enum DoneLogFixture {
    /// Whole seconds, so dates survive the database's millisecond precision exactly.
    static func date(days: Int) -> Date {
        Date(timeIntervalSince1970: 1_760_000_000 + TimeInterval(days * 86_400))
    }

    static func item(
        title: String? = "Gig at the Enmore",
        category: ItemCategory = .event,
        cloudID: String? = nil,
        groupID: String? = nil,
        state: ItemState = .unreviewed,
        isNSFWFlagged: Bool = false,
        stateChangedAt: Date? = nil
    ) -> ScreenshotItem {
        ScreenshotItem(
            assetLocalID: UUID().uuidString,
            cloudID: cloudID,
            createdAt: date(days: 0),
            category: category,
            confidence: 0.97,
            groupID: groupID,
            state: state,
            isNSFWFlagged: isNSFWFlagged,
            stateChangedAt: stateChangedAt,
            updatedAt: date(days: 0),
            title: title,
            processedAt: date(days: 0)
        )
    }

    static func entry(
        category: ItemCategory = .event,
        isSafeToDisplay: Bool = true,
        hasSensitiveText: Bool = false
    ) -> DoneEntry {
        DoneEntry(
            itemID: nil,
            groupKey: "group",
            doneAt: date(days: 0),
            title: nil,
            category: category,
            isSafeToDisplay: isSafeToDisplay,
            hasSensitiveText: hasSensitiveText
        )
    }
}
