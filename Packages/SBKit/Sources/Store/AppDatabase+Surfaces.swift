import Core
import Foundation
import GRDB

/// A screenshot the library scan found, before it has been read.
public struct DiscoveredScreenshot: Hashable, Sendable {
    public var assetLocalID: String
    public var cloudID: String?
    public var createdAt: Date

    public init(assetLocalID: String, cloudID: String?, createdAt: Date) {
        self.assetLocalID = assetLocalID
        self.cloudID = cloudID
        self.createdAt = createdAt
    }
}

/// A card in the triage deck: one item standing in for its group of near-duplicates.
public struct TriageCard: Hashable, Sendable, Identifiable {
    public var item: ScreenshotItem
    public var groupSize: Int

    public init(item: ScreenshotItem, groupSize: Int) {
        self.item = item
        self.groupSize = groupSize
    }

    public var id: String { item.id }
}

/// The few columns the Reveal's stats need, for every screenshot in a period.
public struct ItemSummary: Codable, Hashable, Sendable, FetchableRecord {
    public var id: String
    public var createdAt: Date
    public var category: ItemCategory
    public var confidence: Double
    public var state: ItemState
    public var isSafeToDisplay: Bool
    public var isNSFWFlagged: Bool
    public var hasDate: Bool
    public var processedAt: Date?
}

private typealias Col = ScreenshotItem.Columns

// MARK: - Discovery and processing

extension AppDatabase {
    /// Records screenshots found in the library. Known assets are left alone. Returns how many were new.
    @discardableResult
    /// Local identifiers already recorded for screenshots created after `date`.
    public func knownAssetIDs(createdAfter date: Date) throws -> Set<String> {
        try reader.read { db in
            try ScreenshotItem
                .select(Col.assetLocalID)
                .filter(Col.createdAt > date)
                .asRequest(of: String.self)
                .fetchSet(db)
        }
    }

    public func recordDiscovered(_ screenshots: [DiscoveredScreenshot], now: Date = Date()) throws -> Int {
        try writer.write { db in
            var inserted = 0
            for screenshot in screenshots {
                let exists = try ScreenshotItem.filter(Col.assetLocalID == screenshot.assetLocalID).fetchCount(db) > 0
                if exists { continue }
                try ScreenshotItem(
                    assetLocalID: screenshot.assetLocalID,
                    cloudID: screenshot.cloudID,
                    createdAt: screenshot.createdAt,
                    updatedAt: now
                ).insert(db)
                inserted += 1
            }
            return inserted
        }
    }

    /// Screenshots not yet read, newest first.
    public func unprocessedItems(limit: Int) throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.processedAt == nil)
                .filter(Col.needsBackfill == false)
                .order(Col.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Screenshots that were cloud-only during an earlier scan.
    public func backfillItems(limit: Int) throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.needsBackfill == true)
                .order(Col.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func save(_ items: [ScreenshotItem]) throws {
        try writer.write { db in
            for item in items {
                try item.save(db)
            }
        }
    }

    /// Records groups of near-duplicates: one `ItemGroup` per group, the newest item representing it.
    public func saveGroups(_ groups: [String: [ScreenshotItem]], now: Date = Date()) throws {
        try writer.write { db in
            for (groupID, members) in groups where members.count > 1 {
                let sorted = members.sorted { $0.createdAt > $1.createdAt }
                try ItemGroup(
                    id: groupID,
                    createdAt: sorted.last?.createdAt ?? now,
                    representativeItemID: sorted.first?.id,
                    itemCount: members.count,
                    updatedAt: now
                ).save(db)
                for member in members {
                    guard var item = try ScreenshotItem.fetchOne(db, key: member.id) else { continue }
                    item.groupID = groupID
                    try item.update(db)
                }
            }
        }
    }

    public func containsItem(assetLocalID: String) throws -> Bool {
        try reader.read { db in
            try ScreenshotItem.filter(Col.assetLocalID == assetLocalID).fetchCount(db) > 0
        }
    }

    public func items(ids: [String]) throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem.filter(ids.contains(Col.id)).fetchAll(db)
        }
    }

    public func screenshotCount(since: Date? = nil) throws -> Int {
        try reader.read { db in
            var request = ScreenshotItem.all()
            if let since {
                request = request.filter(Col.createdAt >= since)
            }
            return try request.fetchCount(db)
        }
    }

    /// Every screenshot that's been read, for reclassifying.
    public func readItems() throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem.filter(Col.processedAt != nil).fetchAll(db)
        }
    }

    public func processedCount() throws -> Int {
        try reader.read { db in
            try ScreenshotItem.filter(Col.processedAt != nil).fetchCount(db)
        }
    }

    public func summaries(since: Date? = nil) throws -> [ItemSummary] {
        try reader.read { db in
            var request = ScreenshotItem
                .select(Col.id, Col.createdAt, Col.category, Col.confidence, Col.state,
                        Col.isSafeToDisplay, Col.isNSFWFlagged, Col.hasDate, Col.processedAt)
            if let since {
                request = request.filter(Col.createdAt >= since)
            }
            return try request.asRequest(of: ItemSummary.self).fetchAll(db)
        }
    }

    public func scanState() throws -> ScanState {
        try reader.read { db in
            try ScanState.fetchOne(db, key: ScanState.singletonID) ?? ScanState()
        }
    }

    public func save(_ state: ScanState) throws {
        try writer.write { db in
            try state.save(db)
        }
    }
}

// MARK: - Display surfaces
//
// Every surface goes through these queries. Nudity-flagged items appear on none of them. The
// widget and the Reveal's example thumbnails additionally require `isSafeToDisplay`.

extension AppDatabase {
    /// Unreviewed things to do for the swipe deck, newest first, near-duplicates folded into one
    /// card. Chats, posts, receipts and anything unrecognised are never sorted.
    public func triageDeck(limit: Int = 30) throws -> [TriageCard] {
        Self.foldGroups(try triageCandidates(), limit: limit)
    }

    /// For the Sunday digest: intentions saved, and things done, in the last seven days.
    public func weekStats(now: Date) throws -> (saved: Int, done: Int) {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        return try reader.read { db in
            let saved = try ScreenshotItem
                .filter(Col.isNSFWFlagged == false)
                .filter(ItemCategory.actionable.map(\.rawValue).contains(Col.category))
                .filter(Col.createdAt >= weekAgo)
                .fetchCount(db)
            let done = try ScreenshotItem
                .filter(Col.state == ItemState.done.rawValue)
                .filter(Col.stateChangedAt >= weekAgo)
                .fetchCount(db)
            return (saved, done)
        }
    }

    /// A later recap: screenshots saved since the last one, then a few older ones still waiting.
    public func recapDeck(newSince: Date, olderLimit: Int = 5, limit: Int = 30) throws -> [TriageCard] {
        let waiting = try triageCandidates()
        let fresh = Self.foldGroups(waiting.filter { $0.createdAt >= newSince }, limit: limit)
        let older = Self.foldGroups(waiting.filter { $0.createdAt < newSince }, limit: olderLimit)
        return fresh + older
    }

    /// How many cards the next recap would show.
    public func recapCount(newSince: Date, olderLimit: Int = 5) throws -> Int {
        try recapDeck(newSince: newSince, olderLimit: olderLimit).count
    }

    public func markRecapped(at date: Date = Date()) throws {
        var state = try scanState()
        state.lastRecapAt = date
        state.updatedAt = date
        try save(state)
    }

    private func triageCandidates() throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.processedAt != nil)
                .filter(Col.isNSFWFlagged == false)
                .filter(Col.hasSensitiveText == false)
                .filter(Col.state == ItemState.unreviewed.rawValue)
                .filter(ItemCategory.actionable.map(\.rawValue).contains(Col.category))
                .order(Col.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// What the widget may show: safe items only, unreviewed before kept, soonest-expiring first,
    /// then oldest untouched; anything already shown today is skipped.
    /// `includeSurfaced` counts what's already been shown today too (how much there is in all).
    public func widgetCandidates(now: Date, calendar: Calendar = .current, limit: Int = 12, includeSurfaced: Bool = false) throws -> [ScreenshotItem] {
        let startOfDay = calendar.startOfDay(for: now)
        let items = try reader.read { db in
            var request = ScreenshotItem
                .filter(Col.isSafeToDisplay == true)
                .filter(Col.isNSFWFlagged == false)
                .filter(Col.hasSensitiveText == false)
                .filter(Col.thumbnailPath != nil)
                .filter([ItemState.unreviewed.rawValue, ItemState.stillWant.rawValue].contains(Col.state))
                .filter(Col.expiresAt == nil || Col.expiresAt > now)
            if !includeSurfaced {
                request = request.filter(Col.lastSurfacedAt == nil || Col.lastSurfacedAt < startOfDay)
            }
            return try request.fetchAll(db)
        }
        return Array(items.sorted(by: Self.widgetOrder).prefix(limit))
    }

    public func markSurfaced(ids: [String], at date: Date) throws {
        try writer.write { db in
            for id in ids {
                guard var item = try ScreenshotItem.fetchOne(db, key: id) else { continue }
                item.lastSurfacedAt = date
                try item.update(db)
            }
        }
    }

    /// Dated intentions in the next `days`, soonest first. Near-duplicates show once.
    public func comingUp(now: Date, days: Int = 7) throws -> [ScreenshotItem] {
        let start = now.addingTimeInterval(-12 * 3_600)
        let end = now.addingTimeInterval(Double(days) * 86_400)
        let items = try reader.read { db in
            try ScreenshotItem
                .filter(Col.processedAt != nil)
                .filter(Col.isNSFWFlagged == false)
                .filter([ItemState.unreviewed.rawValue, ItemState.stillWant.rawValue].contains(Col.state))
                .filter(ItemCategory.actionable.map(\.rawValue).contains(Col.category))
                .filter(Col.dueDate >= start && Col.dueDate <= end)
                .order(Col.dueDate.asc)
                .fetchAll(db)
        }
        return Self.oneOfEachGroup(items)
    }

    /// Kept intentions, grouped by category, oldest untouched first. Near-duplicates count once,
    /// as they do in the score.
    public func stillWant() throws -> [ItemCategory: [ScreenshotItem]] {
        let items = try reader.read { db in
            try ScreenshotItem
                .filter(Col.isNSFWFlagged == false)
                .filter(Col.state == ItemState.stillWant.rawValue)
                .fetchAll(db)
        }
        let sorted = items.sorted { ($0.stateChangedAt ?? $0.createdAt) < ($1.stateChangedAt ?? $1.createdAt) }
        return Dictionary(grouping: Self.oneOfEachGroup(sorted), by: \.category)
    }

    /// Everything filed away (chats, posts, receipts, anything unrecognised, and whatever was
    /// filed by hand), grouped by category, newest first. Near-duplicates show once.
    public func filed() throws -> [ItemCategory: [ScreenshotItem]] {
        let items = try reader.read { db in
            try ScreenshotItem
                .filter(Col.processedAt != nil)
                .filter(Col.isNSFWFlagged == false)
                .filter(Col.state == ItemState.reference.rawValue)
                .order(Col.createdAt.desc)
                .fetchAll(db)
        }
        return Dictionary(grouping: Self.oneOfEachGroup(items), by: \.category)
    }

    /// Reference search across the text read from screenshots.
    public func search(_ query: String, limit: Int = 50) throws -> [ScreenshotItem] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        return try reader.read { db in
            try ScreenshotItem.fetchAll(db, sql: """
                SELECT screenshotItem.*
                FROM screenshotItem
                JOIN \(Self.searchTableName) ON \(Self.searchTableName).rowid = screenshotItem.rowid
                WHERE \(Self.searchTableName) MATCH ? AND screenshotItem.isNSFWFlagged = 0
                ORDER BY \(Self.searchTableName).rank
                LIMIT ?
                """, arguments: [pattern, limit])
        }
    }

    /// Example thumbnails for the Reveal's top-category card. Safe items only.
    public func revealExamples(category: ItemCategory, limit: Int = 3) throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.isSafeToDisplay == true)
                .filter(Col.isNSFWFlagged == false)
                .filter(Col.hasSensitiveText == false)
                .filter(Col.category == category.rawValue)
                .filter(Col.thumbnailPath != nil)
                .order(Col.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Recent safe items, for building the light of shared surfaces (the Reveal, the share card)
    /// from the user's own colours.
    public func recentSafeItems(limit: Int = 12) throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.isSafeToDisplay == true)
                .filter(Col.isNSFWFlagged == false)
                .order(Col.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// The oldest intention never done (and never dropped).
    public func oldestUndone() throws -> ScreenshotItem? {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.isSafeToDisplay == true)
                .filter([ItemState.unreviewed.rawValue, ItemState.stillWant.rawValue].contains(Col.state))
                .order(Col.createdAt.asc)
                .fetchOne(db)
        }
    }

    /// Items dropped in triage, which can be deleted from the library in one batch.
    public func dropped() throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.state == ItemState.dropped.rawValue)
                .order(Col.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Forgets items whose assets were deleted from the library.
    public func deleteItems(assetLocalIDs: [String]) throws {
        _ = try writer.write { db in
            try ScreenshotItem.filter(assetLocalIDs.contains(Col.assetLocalID)).deleteAll(db)
        }
    }

    static func foldGroups(_ items: [ScreenshotItem], limit: Int) -> [TriageCard] {
        var cards: [TriageCard] = []
        var indexByGroup: [String: Int] = [:]
        for item in items {
            if let groupID = item.groupID, let index = indexByGroup[groupID] {
                cards[index].groupSize += 1
                continue
            }
            guard cards.count < limit else { continue }
            if let groupID = item.groupID {
                indexByGroup[groupID] = cards.count
            }
            cards.append(TriageCard(item: item, groupSize: 1))
        }
        return cards
    }

    /// The first item of each group of near-duplicates, in order.
    static func oneOfEachGroup(_ items: [ScreenshotItem]) -> [ScreenshotItem] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.groupID ?? $0.id).inserted }
    }

    static func widgetOrder(_ a: ScreenshotItem, _ b: ScreenshotItem) -> Bool {
        let aUnreviewed = a.state == .unreviewed, bUnreviewed = b.state == .unreviewed
        if aUnreviewed != bUnreviewed { return aUnreviewed }
        switch (a.expiresAt, b.expiresAt) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        return (a.stateChangedAt ?? a.createdAt) < (b.stateChangedAt ?? b.createdAt)
    }
}

// MARK: - Accuracy harness

extension AppDatabase {
    public func recordAccuracy(category: ItemCategory, correct: Bool) throws {
        try writer.write { db in
            var record = try AccuracyRecord.fetchOne(db, key: category.rawValue) ?? AccuracyRecord(category: category)
            if correct {
                record.correct += 1
            } else {
                record.wrong += 1
            }
            try record.save(db)
        }
    }

    public func accuracyRecords() throws -> [AccuracyRecord] {
        try reader.read { db in
            try AccuracyRecord.fetchAll(db)
        }
    }
}
