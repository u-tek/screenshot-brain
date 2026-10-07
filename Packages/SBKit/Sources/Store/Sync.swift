import Core
import Foundation
import GRDB

/// CloudKit bookkeeping. A single row.
public struct SyncState: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "syncState"
    public static let singletonID = 1

    public var id: Int = SyncState.singletonID
    public var zoneCreated: Bool = false
    public var changeToken: Data?
    public var lastPushAt: Date?

    public init() {}
}

/// An item state that arrived from another device for an asset this device hasn't scanned yet.
public struct PendingRemoteState: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pendingRemoteState"

    public var cloudID: String
    public var state: ItemState
    public var stateChangedAt: Date

    public init(cloudID: String, state: ItemState, stateChangedAt: Date) {
        self.cloudID = cloudID
        self.state = state
        self.stateChangedAt = stateChangedAt
    }
}

private typealias Col = ScreenshotItem.Columns

extension AppDatabase {
    public func syncState() throws -> SyncState {
        try reader.read { db in
            try SyncState.fetchOne(db, key: SyncState.singletonID) ?? SyncState()
        }
    }

    public func save(_ state: SyncState) throws {
        try writer.write { db in
            try state.save(db)
        }
    }

    /// Items whose state may need pushing: those with a cloud identifier, changed since `date`.
    public func itemsForSync(changedSince date: Date) throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(Col.cloudID != nil)
                .filter(Col.updatedAt > date)
                .filter(Col.stateChangedAt != nil)
                .fetchAll(db)
        }
    }

    /// Applies a state decided on another device. The newest decision wins. If this device hasn't
    /// found the asset yet, the state waits until it does.
    public func applyRemoteState(cloudID: String, state: ItemState, changedAt: Date) throws {
        try writer.write { db in
            if var item = try ScreenshotItem.filter(Col.cloudID == cloudID).fetchOne(db) {
                guard (item.stateChangedAt ?? .distantPast) < changedAt else { return }
                item.state = state
                item.stateChangedAt = changedAt
                // Keep updatedAt as is, so the change isn't pushed straight back.
                try item.update(db)
            } else {
                try PendingRemoteState(cloudID: cloudID, state: state, stateChangedAt: changedAt).save(db)
            }
        }
    }

    /// Applies remote states that were waiting for this device to find their assets.
    public func applyPendingRemoteStates() throws {
        try writer.write { db in
            for pending in try PendingRemoteState.fetchAll(db) {
                guard var item = try ScreenshotItem.filter(Col.cloudID == pending.cloudID).fetchOne(db) else { continue }
                if (item.stateChangedAt ?? .distantPast) < pending.stateChangedAt {
                    item.state = pending.state
                    item.stateChangedAt = pending.stateChangedAt
                    try item.update(db)
                }
                try pending.delete(db)
            }
        }
    }

    /// Adopts onboarding progress from another device when it's further along, so a new phone
    /// resumes where the old one left off and onboarding is never repeated.
    public func applyRemoteOnboarding(_ remote: OnboardingAnswers) throws {
        try writer.write { db in
            let local = try OnboardingAnswers.fetchOne(db, key: OnboardingAnswers.singletonID)
            guard let local else {
                try remote.save(db)
                return
            }
            guard remote.step > local.step else { return }
            var merged = remote
            merged.guessedScreenshotCount = remote.guessedScreenshotCount ?? local.guessedScreenshotCount
            merged.guessedTopCategory = remote.guessedTopCategory ?? local.guessedTopCategory
            merged.guessedDoneCount = remote.guessedDoneCount ?? local.guessedDoneCount
            merged.guessedPeakPeriod = remote.guessedPeakPeriod ?? local.guessedPeakPeriod
            merged.windDownMinutes = remote.windDownMinutes ?? local.windDownMinutes
            merged.recapMinutes = remote.recapMinutes ?? local.recapMinutes
            try merged.save(db)
        }
    }

    /// Removes everything on this device: items, groups, answers, snapshots and sync state.
    /// Used by account deletion.
    public func eraseAll() throws {
        try writer.write { db in
            for table in [ScreenshotItem.databaseTableName, ItemGroup.databaseTableName, OnboardingAnswers.databaseTableName,
                          ScoreSnapshot.databaseTableName, RevealSnapshot.databaseTableName, AccuracyRecord.databaseTableName,
                          ScanState.databaseTableName, SyncState.databaseTableName, PendingRemoteState.databaseTableName] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}
