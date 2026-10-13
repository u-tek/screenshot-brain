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

    /// Records screenshots found in the library. Known assets are left alone. Returns how many were new.
    @discardableResult
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

    /// Saves what a read produced, onto the row as it is now. The row may have changed while the
    /// screenshot was being read (a decision, the widget showing it, a state arriving from
    /// another device, grouping), so those fields stay as they are in the database and only the
    /// analysis is written. An unreviewed item that turns out to be nothing to do is filed away.
    public func saveReadResults(_ results: [ScreenshotItem]) throws {
        try writer.write { db in
            for result in results {
                guard let live = try ScreenshotItem.fetchOne(db, key: result.id) else { continue }
                var merged = result
                merged.state = live.state
                merged.stateChangedAt = live.stateChangedAt
                merged.lastSurfacedAt = live.lastSurfacedAt
                merged.groupID = live.groupID
                merged.cloudID = live.cloudID ?? result.cloudID
                merged.updatedAt = max(live.updatedAt, result.updatedAt)
                if live.state == .unreviewed, !merged.isNSFWFlagged,
                   merged.hasSensitiveText || !merged.category.isActionable {
                    merged.state = .reference
                }
                try merged.update(db)
            }
        }
    }

    /// Saves new categories (and what follows from them) onto the rows as they are now, leaving
    /// everything else alone. Returns how many changed. Items still waiting to be sorted that turn
    /// out to be nothing to do are filed away; items that were filed away automatically (never
    /// decided by hand or on another device) and now are something to do go back to waiting.
    @discardableResult
    public func saveReclassified(_ items: [ScreenshotItem], now: Date = Date()) throws -> Int {
        try writer.write { db in
            var changed = 0
            for item in items {
                guard var live = try ScreenshotItem.fetchOne(db, key: item.id),
                      !live.isNSFWFlagged,
                      live.category != item.category
                else { continue }
                let wasFiledAutomatically = live.state == .reference && live.stateChangedAt == nil && !live.category.isActionable
                live.category = item.category
                live.confidence = item.confidence
                live.dueDate = item.dueDate
                live.expiresAt = item.expiresAt
                live.reviewAt = item.reviewAt
                live.isSafeToDisplay = item.isSafeToDisplay
                if live.state == .unreviewed, !live.category.isActionable {
                    live.state = .reference
                } else if wasFiledAutomatically, live.category.isActionable, !live.hasSensitiveText {
                    live.state = .unreviewed
                }
                live.updatedAt = now
                try live.update(db)
                changed += 1
            }
            return changed
        }
    }

    /// Records groups of near-duplicates: one `ItemGroup` per group, the newest item representing
    /// it. Members that were already in the group (found again as neighbours) are counted too.
    public func saveGroups(_ groups: [String: [ScreenshotItem]], now: Date = Date()) throws {
        try writer.write { db in
            for (groupID, members) in groups where members.count > 1 {
                // The group first: items refer to it.
                var group = try ItemGroup.fetchOne(db, key: groupID)
                    ?? ItemGroup(id: groupID, createdAt: now, representativeItemID: members.first?.id, itemCount: members.count, updatedAt: now)
                try group.save(db)
                for member in members {
                    _ = try ScreenshotItem
                        .filter(Col.id == member.id)
                        .updateAll(db, Col.groupID.set(to: groupID))
                }
                let all = try ScreenshotItem
                    .filter(Col.groupID == groupID)
                    .order(Col.createdAt.desc)
                    .fetchAll(db)
                guard let newest = all.first, let oldest = all.last else { continue }
                group.createdAt = oldest.createdAt
                group.representativeItemID = newest.id
                group.itemCount = all.count
                group.updatedAt = now
                try group.save(db)
            }
        }
    }

    /// Read screenshots still waiting to be sorted that were taken in `range`: the neighbours a
    /// freshly read screenshot may turn out to be a near-duplicate of.
    public func unreviewedItems(createdBetween range: ClosedRange<Date>, limit: Int = 200) throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.processedAt != nil)
                .filter(Col.isNSFWFlagged == false)
                .filter(Col.state == ItemState.unreviewed.rawValue)
                .filter(Col.createdAt >= range.lowerBound && Col.createdAt <= range.upperBound)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Local identifiers of screenshots created after `date` whose cloud identifier isn't known yet.
    public func assetIDsWithoutCloudID(createdAfter date: Date) throws -> [String] {
        try reader.read { db in
            try ScreenshotItem
                .select(Col.assetLocalID)
                .filter(Col.cloudID == nil)
                .filter(Col.createdAt > date)
                .asRequest(of: String.self)
                .fetchAll(db)
        }
    }

    /// Fills in cloud identifiers (by local identifier) that weren't available when the
    /// screenshots were found. Touches `updatedAt` so a decision made meanwhile is pushed.
    public func setCloudIDs(_ cloudIDs: [String: String], now: Date = Date()) throws {
        guard !cloudIDs.isEmpty else { return }
        try writer.write { db in
            for (assetLocalID, cloudID) in cloudIDs {
                _ = try ScreenshotItem
                    .filter(Col.assetLocalID == assetLocalID)
                    .filter(Col.cloudID == nil)
                    .updateAll(db, Col.cloudID.set(to: cloudID), Col.updatedAt.set(to: now))
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

    /// Notes that a scan finished, without touching the rest of the scan state.
    public func markScanned(at date: Date) throws {
        try writer.write { db in
            var state = try ScanState.fetchOne(db, key: ScanState.singletonID) ?? ScanState()
            state.lastScanAt = date
            state.updatedAt = date
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
        // Near-duplicates fold first, so a group spanning the cut-off is one card, not two. The
        // newest item of a group stands for it.
        let cards = Self.foldGroups(try triageCandidates(), limit: Int.max)
        let fresh = cards.filter { $0.item.createdAt >= newSince }.prefix(limit)
        let older = cards.filter { $0.item.createdAt < newSince }.prefix(olderLimit)
        return Array(fresh) + Array(older)
    }

    /// How many cards the next recap would show.
    public func recapCount(newSince: Date, olderLimit: Int = 5) throws -> Int {
        try recapDeck(newSince: newSince, olderLimit: olderLimit).count
    }

    public func markRecapped(at date: Date = Date()) throws {
        try writer.write { db in
            var state = try ScanState.fetchOne(db, key: ScanState.singletonID) ?? ScanState()
            state.lastRecapAt = date
            state.updatedAt = date
            try state.save(db)
        }
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
        // Ordered and limited in SQL (the same order as `widgetOrder`), so the widget reads only
        // the rows it can show.
        var sql = "SELECT * FROM screenshotItem"
            + " WHERE isSafeToDisplay = 1 AND isNSFWFlagged = 0 AND hasSensitiveText = 0"
            + " AND thumbnailPath IS NOT NULL AND state IN (?, ?)"
            + " AND (expiresAt IS NULL OR expiresAt > ?)"
        var arguments: [(any DatabaseValueConvertible)?] = [ItemState.unreviewed.rawValue, ItemState.stillWant.rawValue, now]
        if !includeSurfaced {
            sql += " AND (lastSurfacedAt IS NULL OR lastSurfacedAt < ?)"
            arguments.append(startOfDay)
        }
        sql += " ORDER BY (state = ?) DESC, (expiresAt IS NULL) ASC, expiresAt ASC, COALESCE(stateChangedAt, createdAt) ASC"
        sql += " LIMIT ?"
        arguments.append(ItemState.unreviewed.rawValue)
        arguments.append(max(limit, 0))
        let query = sql
        let values = arguments
        return try reader.read { db in
            try ScreenshotItem.fetchAll(db, sql: query, arguments: StatementArguments(values))
        }
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
                .filter(Col.isNSFWFlagged == false)
                .filter(Col.hasSensitiveText == false)
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

    /// Forgets items whose assets were deleted from the library, and their thumbnails.
    /// `thumbnailDirectory` defaults to the App Group's thumbnails.
    public func deleteItems(assetLocalIDs: [String], thumbnailDirectory: URL? = nil) throws {
        let thumbnails: [String] = try writer.write { db in
            let matching = ScreenshotItem.filter(assetLocalIDs.contains(Col.assetLocalID))
            let paths = try matching
                .select(Col.thumbnailPath)
                .filter(Col.thumbnailPath != nil)
                .asRequest(of: String.self)
                .fetchAll(db)
            _ = try matching.deleteAll(db)
            return paths
        }
        guard !thumbnails.isEmpty, let directory = thumbnailDirectory ?? (try? AppGroup.directory(.thumbnails)) else { return }
        for path in thumbnails {
            let name = URL(fileURLWithPath: path).lastPathComponent
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
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
