import Core
import Foundation
import GRDB

extension AppDatabase {
    /// Processed, safe-to-search items, newest first: what meaning search ranks. Capped so a huge
    /// library can't make one search slow.
    public func meaningCandidates(limit: Int = 3000) throws -> [ScreenshotItem] {
        try reader.read { db in
            try ScreenshotItem
                .filter(ScreenshotItem.Columns.processedAt != nil)
                .filter(ScreenshotItem.Columns.isNSFWFlagged == false)
                .order(ScreenshotItem.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
