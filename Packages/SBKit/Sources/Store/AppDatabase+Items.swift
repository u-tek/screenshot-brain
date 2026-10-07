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
