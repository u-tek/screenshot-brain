import Core
import Foundation
import GRDB

/// One thing done, in the did-it log, with whatever the user added to remember it by.
///
/// Written when an item is marked done and removed if that's undone. It keeps its own copy of the
/// title, kind and light, so it outlives the screenshot: people delete a screenshot once they've
/// done the thing, and the log is a record of what they did, not of what's left in Photos.
/// Like the item it came from, it stays on this device.
public struct DoneEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// The item it was made from. Nil once that screenshot is gone.
    public var itemID: String?
    /// The item's group of near-duplicates, or the item itself: a group is done once.
    public var groupKey: String
    public var doneAt: Date
    public var title: String?
    public var category: ItemCategory
    /// Relative to the App Group's thumbnails directory.
    public var thumbnailPath: String?
    public var palette: [PaletteColor]
    public var isSafeToDisplay: Bool
    public var hasSensitiveText: Bool
    /// What the user wrote about it.
    public var note: String?
    /// A photo the user added, by file name in the App Group's memories directory.
    public var photoName: String?
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        itemID: String?,
        groupKey: String,
        doneAt: Date,
        title: String?,
        category: ItemCategory,
        thumbnailPath: String? = nil,
        palette: [PaletteColor] = [],
        isSafeToDisplay: Bool = false,
        hasSensitiveText: Bool = false,
        note: String? = nil,
        photoName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.groupKey = groupKey
        self.doneAt = doneAt
        self.title = title
        self.category = category
        self.thumbnailPath = thumbnailPath
        self.palette = palette
        self.isSafeToDisplay = isSafeToDisplay
        self.hasSensitiveText = hasSensitiveText
        self.note = note
        self.photoName = photoName
        self.updatedAt = updatedAt
    }

    init(item: ScreenshotItem) {
        let doneAt = item.stateChangedAt ?? item.updatedAt
        self.init(
            itemID: item.id,
            groupKey: item.groupID ?? item.id,
            doneAt: doneAt,
            title: item.title,
            category: item.category,
            thumbnailPath: item.thumbnailPath,
            palette: item.palette,
            isSafeToDisplay: item.isSafeToDisplay,
            hasSensitiveText: item.hasSensitiveText,
            updatedAt: doneAt
        )
    }

    /// Whether it may appear on something shared out of the app: only things that passed every
    /// safety filter, with nothing sensitive in their text, and only the kinds worth showing.
    public var isShareable: Bool {
        isSafeToDisplay && !hasSensitiveText && category.isDisplayableIntention
    }

    /// A memory added: a photo or a note.
    public var hasMemory: Bool {
        photoName != nil || !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

extension DoneEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "doneEntry"

    public enum Columns: String, ColumnExpression {
        case id, itemID, groupKey, doneAt, title, category, thumbnailPath, palette
        case isSafeToDisplay, hasSensitiveText, note, photoName, updatedAt
    }
}

// MARK: - Schema

extension AppDatabase {
    static func createDoneLog(_ db: Database) throws {
        try db.create(table: DoneEntry.databaseTableName) { t in
            t.primaryKey("id", .text)
            // Kept when the screenshot goes: the log outlives Photos.
            t.column("itemID", .text).indexed().references(ScreenshotItem.databaseTableName, onDelete: .setNull)
            t.column("groupKey", .text).notNull().unique()
            t.column("doneAt", .datetime).notNull().indexed()
            t.column("title", .text)
            t.column("category", .text).notNull()
            t.column("thumbnailPath", .text)
            t.column("palette", .text).notNull()
            t.column("isSafeToDisplay", .boolean).notNull().defaults(to: false)
            t.column("hasSensitiveText", .boolean).notNull().defaults(to: false)
            t.column("note", .text)
            t.column("photoName", .text)
            t.column("updatedAt", .datetime).notNull()
        }
        // Everything already done starts the log, oldest first so a group keeps its first.
        // Plain SQL, so later changes to the item record can't break this migration.
        try db.execute(sql: """
            INSERT OR IGNORE INTO doneEntry
                (id, itemID, groupKey, doneAt, title, category, thumbnailPath, palette,
                 isSafeToDisplay, hasSensitiveText, updatedAt)
            SELECT id, id, COALESCE(groupID, id), COALESCE(stateChangedAt, updatedAt), title, category,
                   thumbnailPath, palette, isSafeToDisplay, hasSensitiveText, COALESCE(stateChangedAt, updatedAt)
            FROM screenshotItem
            WHERE state = ? AND isNSFWFlagged = 0 AND processedAt IS NOT NULL
            ORDER BY COALESCE(stateChangedAt, updatedAt)
            """, arguments: [ItemState.done.rawValue])
    }

    /// Keeps the log in step with items just written: an entry for each thing done (one per
    /// group of near-duplicates), brought up to date as the item is read and checked, and gone
    /// again once nothing in its group is done.
    ///
    /// An item isn't logged until it has been read: a state from another device can arrive for
    /// a screenshot this device has only just found, with no title, kind or safety checks yet.
    static func recordDone(_ items: [ScreenshotItem], in db: Database) throws {
        let undone = items.filter { $0.state != .done }
        if !undone.isEmpty {
            // The group each was in, and whatever entry was made from it before it was grouped.
            var keys = Set(undone.map { $0.groupID ?? $0.id })
            keys.formUnion(try DoneEntry
                .filter(undone.map(\.id).contains(DoneEntry.Columns.itemID))
                .fetchAll(db)
                .map(\.groupKey))
            for key in keys {
                let stillDone = try ScreenshotItem
                    .filter(ScreenshotItem.Columns.state == ItemState.done.rawValue)
                    .filter(ScreenshotItem.Columns.groupID == key || ScreenshotItem.Columns.id == key)
                    .fetchCount(db) > 0
                if !stillDone {
                    try DoneEntry.filter(DoneEntry.Columns.groupKey == key).deleteAll(db)
                }
            }
        }
        for item in items where item.state == .done && !item.isNSFWFlagged && item.processedAt != nil {
            let key = item.groupID ?? item.id
            if var entry = try DoneEntry.filter(DoneEntry.Columns.groupKey == key).fetchOne(db) {
                // Read again or rechecked since (reclassified, or found to hold something
                // sensitive): the entry follows, so the share card never shows what it shouldn't.
                guard entry.itemID == item.id else { continue }
                let before = entry
                entry.title = item.title
                entry.category = item.category
                entry.thumbnailPath = item.thumbnailPath
                entry.palette = item.palette
                entry.isSafeToDisplay = item.isSafeToDisplay
                entry.hasSensitiveText = item.hasSensitiveText
                if entry != before {
                    try entry.update(db)
                }
            } else {
                try DoneEntry(item: item).insert(db)
            }
        }
    }

    /// The photo files the log still uses, so the rest can be cleared away.
    public func memoryPhotoNames() throws -> Set<String> {
        try reader.read { db in
            try String.fetchSet(db, sql: "SELECT photoName FROM doneEntry WHERE photoName IS NOT NULL")
        }
    }
}

// MARK: - Reading and remembering

extension AppDatabase {
    /// Everything done, newest first. Nothing whose screenshot was flagged for nudity.
    public func doneLog() throws -> [DoneEntry] {
        try reader.read { db in
            try DoneEntry.fetchAll(db, sql: """
                SELECT doneEntry.*
                FROM doneEntry
                LEFT JOIN screenshotItem ON screenshotItem.id = doneEntry.itemID
                WHERE COALESCE(screenshotItem.isNSFWFlagged, 0) = 0
                ORDER BY doneEntry.doneAt DESC
                """)
        }
    }

    /// The log entry for an item done, if it is.
    public func doneEntry(forItem itemID: String) throws -> DoneEntry? {
        try reader.read { db in
            if let entry = try DoneEntry.filter(DoneEntry.Columns.itemID == itemID).fetchOne(db) {
                return entry
            }
            // A near-duplicate of the one that made the entry.
            guard let groupID = try ScreenshotItem.fetchOne(db, key: itemID)?.groupID else { return nil }
            return try DoneEntry.filter(DoneEntry.Columns.groupKey == groupID).fetchOne(db)
        }
    }

    /// Sets what the user wrote about something done. Blank clears it.
    public func setNote(_ note: String?, forEntry id: String, at date: Date = Date()) throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try writer.write { db in
            guard var entry = try DoneEntry.fetchOne(db, key: id) else { return }
            entry.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            entry.updatedAt = date
            try entry.update(db)
        }
    }

    /// Sets the photo added to something done, or clears it with nil. Returns the file name it
    /// replaced, for the caller to delete.
    @discardableResult
    public func setPhoto(_ name: String?, forEntry id: String, at date: Date = Date()) throws -> String? {
        try writer.write { db in
            guard var entry = try DoneEntry.fetchOne(db, key: id) else { return nil }
            let previous = entry.photoName
            entry.photoName = name
            entry.updatedAt = date
            try entry.update(db)
            return previous == name ? nil : previous
        }
    }
}
