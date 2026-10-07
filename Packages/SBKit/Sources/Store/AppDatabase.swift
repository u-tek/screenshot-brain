import Core
import Foundation
import GRDB

/// The on-device store, shared by the app and its extensions through the App Group container.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public var reader: any DatabaseReader {
        writer
    }

    /// Wraps a database connection and brings its schema up to date.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }
}

// MARK: - Opening

extension AppDatabase {
    public static let fileName = "ScreenshotBrain.sqlite"

    /// Opens the database in the App Group container.
    ///
    /// The app and the widget both open it read-write (widget buttons write item states), so it
    /// uses WAL through a `DatabasePool`, waits on locks held by the other process, and is opened
    /// under file coordination so two processes never set it up at the same time.
    public static func openShared(configuration appConfiguration: AppConfiguration = .main) throws -> AppDatabase {
        let directory = try AppGroup.directory(.database, configuration: appConfiguration)
        return try open(at: directory.appendingPathComponent(fileName))
    }

    static func open(at url: URL) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        // The app posts suspend and resume notifications as it leaves and enters the foreground,
        // so it never holds a lock on a shared file while suspended (which iOS punishes with 0xdead10cc).
        configuration.observesSuspensionNotifications = true

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var result: Result<AppDatabase, any Error> = .failure(CocoaError(.fileReadUnknown))
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { coordinatedURL in
            result = Result {
                try AppDatabase(DatabasePool(path: coordinatedURL.path, configuration: configuration))
            }
        }
        if let coordinatorError {
            throw coordinatorError
        }
        return try result.get()
    }

    /// An empty database in memory, for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// Call as the app moves to the background.
    public static func suspendSharedAccess() {
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
    }

    /// Call as the app returns to the foreground.
    public static func resumeSharedAccess() {
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
    }
}

// MARK: - Schema

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: ItemGroup.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("representativeItemID", .text)
                t.column("itemCount", .integer).notNull().defaults(to: 1)
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: ScreenshotItem.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("assetLocalID", .text).notNull().unique()
                t.column("cloudID", .text).indexed()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("category", .text).notNull().indexed()
                t.column("confidence", .double).notNull()
                t.column("entities", .text).notNull()
                t.column("groupID", .text).indexed().references(ItemGroup.databaseTableName, onDelete: .setNull)
                t.column("state", .text).notNull().indexed()
                t.column("expiresAt", .datetime).indexed()
                t.column("isSafeToDisplay", .boolean).notNull().defaults(to: false)
                t.column("isNSFWFlagged", .boolean).notNull().defaults(to: false)
                t.column("hasSensitiveText", .boolean).notNull().defaults(to: false)
                t.column("thumbnailPath", .text)
                t.column("palette", .text).notNull()
                t.column("extractedText", .text)
                t.column("stateChangedAt", .datetime)
                t.column("lastSurfacedAt", .datetime)
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: OnboardingAnswers.databaseTableName) { t in
                t.primaryKey("id", .integer)
                t.column("step", .text).notNull()
                t.column("guessedScreenshotCount", .integer)
                t.column("guessedTopCategory", .text)
                t.column("guessedDoneCount", .integer)
                t.column("guessedPeakPeriod", .text)
                t.column("windDownMinutes", .integer)
                t.column("recapMinutes", .integer)
                t.column("completedAt", .datetime)
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: ScoreSnapshot.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("takenAt", .datetime).notNull().indexed()
                t.column("done", .integer).notNull()
                t.column("total", .integer).notNull()
            }

            try db.create(table: RevealSnapshot.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("periodStart", .datetime).notNull()
                t.column("periodEnd", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("stats", .text).notNull()
            }
        }

        return migrator
    }
}
