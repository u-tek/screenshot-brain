@preconcurrency import CloudKit
import Core
import CryptoKit
import Foundation

/// Syncs progress through the user's private CloudKit database: item states (keyed by the
/// asset's Photos cloud identifier, which survives a new phone), onboarding answers and the
/// recap time. Screenshots, extracted text and entities are never synced.
public actor CloudSync {
    static let zoneName = "ScreenshotBrain"

    enum RecordType {
        static let itemState = "ItemState"
        static let onboarding = "Onboarding"
    }

    private let database: AppDatabase
    private let containerIdentifier: String
    private let zoneID = CKRecordZone.ID(zoneName: CloudSync.zoneName, ownerName: CKCurrentUserDefaultName)

    public init(database: AppDatabase, containerIdentifier: String) {
        self.database = database
        self.containerIdentifier = containerIdentifier
    }

    /// Made on first use, never at launch: creating a container traps when the build has no
    /// iCloud entitlement (an unsigned simulator build), and only signed-in users ever sync.
    private lazy var container = CKContainer(identifier: containerIdentifier)

    private var cloud: CKDatabase {
        container.privateCloudDatabase
    }

    /// Pushes local changes, then pulls remote ones. Failures are logged and retried next time;
    /// the app never depends on sync to work.
    public func sync() async {
        do {
            guard try await container.accountStatus() == .available else { return }
            try await ensureZone()
            try await push()
            try await pull()
            try database.applyPendingRemoteStates()
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            try? resetState()
        } catch let error as CKError where error.code == .changeTokenExpired {
            var state = (try? database.syncState()) ?? SyncState()
            state.changeToken = nil
            try? database.save(state)
        } catch {
            Log.sync.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes everything this app stored in iCloud. Used by account deletion.
    public func deleteEverything() async throws {
        if try await container.accountStatus() == .available {
            do {
                _ = try await cloud.modifyRecordZones(saving: [], deleting: [zoneID])
            } catch let error as CKError where error.code == .zoneNotFound {
                // Nothing to delete.
            }
        }
        try resetState()
    }

    // MARK: Push

    private func ensureZone() async throws {
        var state = try database.syncState()
        guard !state.zoneCreated else { return }
        _ = try await cloud.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        state.zoneCreated = true
        try database.save(state)
    }

    private func push() async throws {
        var state = try database.syncState()
        let since = state.lastPushAt ?? .distantPast
        let started = Date()

        var records: [CKRecord] = try database.itemsForSync(changedSince: since).compactMap(record(for:))
        if let answers = try database.onboardingAnswers(), answers.updatedAt > since {
            records.append(record(for: answers))
        }
        for start in stride(from: 0, to: records.count, by: 300) {
            let batch = Array(records[start..<min(start + 300, records.count)])
            _ = try await cloud.modifyRecords(saving: batch, deleting: [], savePolicy: .changedKeys, atomically: false)
        }
        state.lastPushAt = started
        try database.save(state)
    }

    private func record(for item: ScreenshotItem) -> CKRecord? {
        guard let cloudID = item.cloudID, let changedAt = item.stateChangedAt else { return nil }
        let id = CKRecord.ID(recordName: "item-" + Self.digest(cloudID), zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.itemState, recordID: id)
        record["cloudID"] = cloudID as CKRecordValue
        record["state"] = item.state.rawValue as CKRecordValue
        record["stateChangedAt"] = changedAt as CKRecordValue
        record["category"] = item.category.rawValue as CKRecordValue
        return record
    }

    private func record(for answers: OnboardingAnswers) -> CKRecord {
        let record = CKRecord(recordType: RecordType.onboarding, recordID: CKRecord.ID(recordName: "onboarding", zoneID: zoneID))
        record["step"] = answers.step.rawValue as CKRecordValue
        record["updatedAt"] = answers.updatedAt as CKRecordValue
        if let value = answers.guessedScreenshotCount { record["guessedScreenshotCount"] = NSNumber(value: value) }
        if let value = answers.guessedTopCategory { record["guessedTopCategory"] = value.rawValue as CKRecordValue }
        if let value = answers.guessedDoneCount { record["guessedDoneCount"] = NSNumber(value: value) }
        if let value = answers.guessedPeakPeriod { record["guessedPeakPeriod"] = value.rawValue as CKRecordValue }
        if let value = answers.windDownMinutes { record["windDownMinutes"] = NSNumber(value: value) }
        if let value = answers.recapMinutes { record["recapMinutes"] = NSNumber(value: value) }
        if let value = answers.completedAt { record["completedAt"] = value as CKRecordValue }
        return record
    }

    // MARK: Pull

    private func pull() async throws {
        var state = try database.syncState()
        var token: CKServerChangeToken? = state.changeToken.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        var moreComing = true
        while moreComing {
            let changes = try await cloud.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (_, result) in changes.modificationResultsByID {
                if case .success(let modification) = result {
                    try apply(modification.record)
                }
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }
        if let token {
            state.changeToken = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        }
        try database.save(state)
    }

    private func apply(_ record: CKRecord) throws {
        switch record.recordType {
        case RecordType.itemState:
            guard let cloudID = record["cloudID"] as? String,
                  let rawState = record["state"] as? String,
                  let state = ItemState(rawValue: rawState),
                  let changedAt = record["stateChangedAt"] as? Date
            else { return }
            try database.applyRemoteState(cloudID: cloudID, state: state, changedAt: changedAt)
        case RecordType.onboarding:
            guard let rawStep = record["step"] as? String, let step = OnboardingStep(rawValue: rawStep) else { return }
            let answers = OnboardingAnswers(
                step: step,
                guessedScreenshotCount: record["guessedScreenshotCount"] as? Int,
                guessedTopCategory: (record["guessedTopCategory"] as? String).flatMap(ItemCategory.init(rawValue:)),
                guessedDoneCount: record["guessedDoneCount"] as? Int,
                guessedPeakPeriod: (record["guessedPeakPeriod"] as? String).flatMap(DayPeriod.init(rawValue:)),
                windDownMinutes: record["windDownMinutes"] as? Int,
                recapMinutes: record["recapMinutes"] as? Int,
                completedAt: record["completedAt"] as? Date,
                updatedAt: record["updatedAt"] as? Date ?? Date()
            )
            try database.applyRemoteOnboarding(answers)
        default:
            break
        }
    }

    private func resetState() throws {
        try database.save(SyncState())
    }

    /// Record names must be short ASCII; cloud identifiers aren't, so they're hashed.
    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
