import Core
import Foundation
import GRDB

/// "Done X of Y". Dropped items carry no penalty, so Y counts only what was kept or done.
/// A group of near-duplicates counts once.
public struct Score: Hashable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

extension AppDatabase {
    public func save(_ item: ScreenshotItem) throws {
        try writer.write { db in
            try item.save(db)
        }
    }

    public func item(id: String) throws -> ScreenshotItem? {
        try reader.read { db in
            try ScreenshotItem.fetchOne(db, key: id)
        }
    }

    public func setState(_ state: ItemState, forItem id: String, at date: Date = Date()) throws {
        try writer.write { db in
            guard var item = try ScreenshotItem.fetchOne(db, key: id) else { return }
            item.state = state
            item.stateChangedAt = date
            item.updatedAt = date
            try item.update(db)
        }
    }

    /// Decides an item and every near-duplicate grouped with it. Returns them as they were, so
    /// the decision can be undone. A near-duplicate with sensitive text (parked as reference) or
    /// flagged for nudity stays where it is.
    @discardableResult
    public func decide(_ state: ItemState, forItem id: String, at date: Date = Date()) throws -> [ScreenshotItem] {
        try writer.write { db in
            guard let item = try ScreenshotItem.fetchOne(db, key: id) else { return [] }
            let members = try item.groupID.map { groupID in
                try ScreenshotItem
                    .filter(ScreenshotItem.Columns.groupID == groupID)
                    .fetchAll(db)
                    .filter { $0.id == item.id || (!$0.hasSensitiveText && !$0.isNSFWFlagged) }
            } ?? [item]
            for var member in members {
                member.state = state
                member.stateChangedAt = date
                member.updatedAt = date
                try member.update(db)
            }
            return members
        }
    }

    /// Undoes a decision: puts each item back in the state it was in. Only the state: anything
    /// else that changed since (the widget showing it, say) stays.
    public func undoDecision(restoring previous: [ScreenshotItem], at date: Date = Date()) throws {
        try writer.write { db in
            for var item in previous {
                // Stamped now, so the undo also wins on other devices.
                item.stateChangedAt = date
                item.updatedAt = date
                try item.update(db, columns: [ScreenshotItem.Columns.state, .stateChangedAt, .updatedAt])
            }
        }
    }

    public func score() throws -> Score {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT state, COUNT(DISTINCT COALESCE(groupID, id)) AS count
                FROM screenshotItem
                WHERE state IN (?, ?)
                GROUP BY state
                """, arguments: [ItemState.done.rawValue, ItemState.stillWant.rawValue])
            var done = 0
            var stillWant = 0
            for row in rows {
                let state: String = row["state"]
                let count: Int = row["count"]
                if state == ItemState.done.rawValue {
                    done = count
                } else {
                    stillWant = count
                }
            }
            return Score(done: done, total: done + stillWant)
        }
    }
}

extension AppDatabase {
    public func onboardingAnswers() throws -> OnboardingAnswers? {
        try reader.read { db in
            try OnboardingAnswers.fetchOne(db, key: OnboardingAnswers.singletonID)
        }
    }

    public func save(_ answers: OnboardingAnswers) throws {
        try writer.write { db in
            try answers.save(db)
        }
    }
}

extension AppDatabase {
    /// Keeps a Reveal's numbers for history (the monthly Reveals, month after month).
    public func save(_ snapshot: RevealSnapshot) throws {
        try writer.write { db in
            try snapshot.save(db)
        }
    }

    public func revealSnapshots() throws -> [RevealSnapshot] {
        try reader.read { db in
            try RevealSnapshot.order(Column("periodStart").desc).fetchAll(db)
        }
    }
}
