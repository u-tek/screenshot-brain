import Core
import Foundation
import GRDB

/// One saved screenshot (or the representative of a group of near-duplicates).
///
/// `extractedText` and `entities` stay on this device. Only identifiers, the category, the state
/// and dates are eligible for CloudKit sync.
public struct ScreenshotItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// `PHAsset.localIdentifier`. Changes on a new phone; `cloudID` maps across devices.
    public var assetLocalID: String
    /// `PHCloudIdentifier.stringValue`, when the asset is in iCloud Photos.
    public var cloudID: String?
    public var createdAt: Date
    public var category: ItemCategory
    /// 0...1. Categories below the confidence bar are shown as `.other`.
    public var confidence: Double
    public var entities: [DetectedEntity]
    public var groupID: String?
    public var state: ItemState
    public var expiresAt: Date?
    /// Set only by the Safety module. False until an item has passed every filter.
    public var isSafeToDisplay: Bool
    public var isNSFWFlagged: Bool
    public var hasSensitiveText: Bool
    /// Relative to the App Group's thumbnails directory.
    public var thumbnailPath: String?
    public var palette: [PaletteColor]
    public var extractedText: String?
    public var stateChangedAt: Date?
    /// Last time the widget showed this item, so nothing shows twice in a day.
    public var lastSurfacedAt: Date?
    public var updatedAt: Date
    /// A short title read from the screenshot (its most prominent line). On-device only.
    public var title: String?
    /// The date that matters: the event's date, or a sale's end.
    public var dueDate: Date?
    /// When to ask "still want this?" (places and recipes).
    public var reviewAt: Date?
    /// When the scan engine finished reading this screenshot. Nil until then.
    public var processedAt: Date?
    /// The asset was cloud-only during the scan; read it later.
    public var needsBackfill: Bool
    /// Any date or time was found in the screenshot.
    public var hasDate: Bool

    public init(
        id: String = UUID().uuidString,
        assetLocalID: String,
        cloudID: String? = nil,
        createdAt: Date,
        category: ItemCategory = .other,
        confidence: Double = 0,
        entities: [DetectedEntity] = [],
        groupID: String? = nil,
        state: ItemState = .unreviewed,
        expiresAt: Date? = nil,
        isSafeToDisplay: Bool = false,
        isNSFWFlagged: Bool = false,
        hasSensitiveText: Bool = false,
        thumbnailPath: String? = nil,
        palette: [PaletteColor] = [],
        extractedText: String? = nil,
        stateChangedAt: Date? = nil,
        lastSurfacedAt: Date? = nil,
        updatedAt: Date = Date(),
        title: String? = nil,
        dueDate: Date? = nil,
        reviewAt: Date? = nil,
        processedAt: Date? = nil,
        needsBackfill: Bool = false,
        hasDate: Bool = false
    ) {
        self.id = id
        self.assetLocalID = assetLocalID
        self.cloudID = cloudID
        self.createdAt = createdAt
        self.category = category
        self.confidence = confidence
        self.entities = entities
        self.groupID = groupID
        self.state = state
        self.expiresAt = expiresAt
        self.isSafeToDisplay = isSafeToDisplay
        self.isNSFWFlagged = isNSFWFlagged
        self.hasSensitiveText = hasSensitiveText
        self.thumbnailPath = thumbnailPath
        self.palette = palette
        self.extractedText = extractedText
        self.stateChangedAt = stateChangedAt
        self.lastSurfacedAt = lastSurfacedAt
        self.updatedAt = updatedAt
        self.title = title
        self.dueDate = dueDate
        self.reviewAt = reviewAt
        self.processedAt = processedAt
        self.needsBackfill = needsBackfill
        self.hasDate = hasDate
    }

    /// Whether the item may appear anywhere in the app at all. Nudity-flagged items never do.
    public var isVisibleInApp: Bool {
        !isNSFWFlagged
    }
}

extension ScreenshotItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "screenshotItem"

    public enum Columns: String, ColumnExpression {
        case id, assetLocalID, cloudID, createdAt, category, confidence, entities, groupID, state
        case expiresAt, isSafeToDisplay, isNSFWFlagged, hasSensitiveText, thumbnailPath, palette
        case extractedText, stateChangedAt, lastSurfacedAt, updatedAt
        case title, dueDate, reviewAt, processedAt, needsBackfill, hasDate
    }
}

/// Near-duplicate screenshots (taken within about a minute, with overlapping text) collapsed into one.
public struct ItemGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var representativeItemID: String?
    public var itemCount: Int
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        createdAt: Date,
        representativeItemID: String? = nil,
        itemCount: Int = 1,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.representativeItemID = representativeItemID
        self.itemCount = itemCount
        self.updatedAt = updatedAt
    }
}

extension ItemGroup: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "itemGroup"
}

/// The guesses made during onboarding, the recap time, and how far through onboarding the user is.
/// A single row.
public struct OnboardingAnswers: Codable, Hashable, Sendable {
    public static let singletonID = 1

    public var id: Int
    public var step: OnboardingStep
    public var guessedScreenshotCount: Int?
    public var guessedTopCategory: ItemCategory?
    public var guessedDoneCount: Int?
    public var guessedPeakPeriod: DayPeriod?
    /// Minutes after midnight.
    public var windDownMinutes: Int?
    /// Minutes after midnight. Defaults to the wind-down time.
    public var recapMinutes: Int?
    public var completedAt: Date?
    public var updatedAt: Date

    public init(
        step: OnboardingStep = .signIn,
        guessedScreenshotCount: Int? = nil,
        guessedTopCategory: ItemCategory? = nil,
        guessedDoneCount: Int? = nil,
        guessedPeakPeriod: DayPeriod? = nil,
        windDownMinutes: Int? = nil,
        recapMinutes: Int? = nil,
        completedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = Self.singletonID
        self.step = step
        self.guessedScreenshotCount = guessedScreenshotCount
        self.guessedTopCategory = guessedTopCategory
        self.guessedDoneCount = guessedDoneCount
        self.guessedPeakPeriod = guessedPeakPeriod
        self.windDownMinutes = windDownMinutes
        self.recapMinutes = recapMinutes
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }
}

extension OnboardingAnswers: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "onboardingAnswers"
}

/// "Done X of Y" at a moment in time.
public struct ScoreSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var takenAt: Date
    public var done: Int
    public var total: Int

    public init(id: String = UUID().uuidString, takenAt: Date, done: Int, total: Int) {
        self.id = id
        self.takenAt = takenAt
        self.done = done
        self.total = total
    }
}

extension ScoreSnapshot: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "scoreSnapshot"

    public enum Columns: String, ColumnExpression {
        case id, takenAt, done, total
    }
}

/// A Reveal's stats, kept so past months can be shown again.
public struct RevealSnapshot: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case firstOpen
        case monthly
        case allTime
    }

    public var id: String
    public var kind: Kind
    public var periodStart: Date
    public var periodEnd: Date
    public var createdAt: Date
    public var stats: RevealStats

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        periodStart: Date,
        periodEnd: Date,
        createdAt: Date = Date(),
        stats: RevealStats
    ) {
        self.id = id
        self.kind = kind
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.createdAt = createdAt
        self.stats = stats
    }
}

extension RevealSnapshot: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "revealSnapshot"
}

/// Counts and timestamps only: the facts a Reveal can't get wrong, plus category counts that
/// cleared the confidence bar.
public struct RevealStats: Codable, Hashable, Sendable {
    public var totalScreenshots: Int
    /// 0...23, local time.
    public var peakHour: Int?
    public var busiestDay: Date?
    public var busiestDayCount: Int
    /// Keyed by `ItemCategory.rawValue`.
    public var categoryCounts: [String: Int]
    public var datedCount: Int
    public var oldestUndoneItemID: String?

    public init(
        totalScreenshots: Int,
        peakHour: Int? = nil,
        busiestDay: Date? = nil,
        busiestDayCount: Int = 0,
        categoryCounts: [String: Int] = [:],
        datedCount: Int = 0,
        oldestUndoneItemID: String? = nil
    ) {
        self.totalScreenshots = totalScreenshots
        self.peakHour = peakHour
        self.busiestDay = busiestDay
        self.busiestDayCount = busiestDayCount
        self.categoryCounts = categoryCounts
        self.datedCount = datedCount
        self.oldestUndoneItemID = oldestUndoneItemID
    }

    public func count(for category: ItemCategory) -> Int {
        categoryCounts[category.rawValue] ?? 0
    }
}

/// How well the classifier did, per category, from the debug "was this right?" mode.
public struct AccuracyRecord: Codable, Hashable, Sendable {
    public var category: ItemCategory
    public var correct: Int
    public var wrong: Int

    public init(category: ItemCategory, correct: Int = 0, wrong: Int = 0) {
        self.category = category
        self.correct = correct
        self.wrong = wrong
    }

    public var accuracy: Double? {
        let total = correct + wrong
        return total == 0 ? nil : Double(correct) / Double(total)
    }
}

extension AccuracyRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "accuracyRecord"
}

/// Where the last scan got to, so scans are incremental and resumable. A single row.
public struct ScanState: Codable, Hashable, Sendable {
    public static let singletonID = 1

    public var id: Int
    public var lastScanAt: Date?
    public var updatedAt: Date

    public init(lastScanAt: Date? = nil, updatedAt: Date = Date()) {
        self.id = Self.singletonID
        self.lastScanAt = lastScanAt
        self.updatedAt = updatedAt
    }
}

extension ScanState: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "scanState"
}
