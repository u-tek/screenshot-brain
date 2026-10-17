import Core
import CoreGraphics
import Foundation
import Safety
import Store

public struct ScanProgress: Hashable, Sendable {
    /// Screenshots read so far in this run.
    public var read: Int
    /// Screenshots this run will read.
    public var total: Int

    public var isFinished: Bool { read >= total }
}

/// Stages of the pipeline, for the benchmark.
public enum ScanStage: String, CaseIterable, Sendable {
    case load
    case nudity
    case text
    case entities
    case classify
    case palette
    case thumbnail
    case save
}

/// Accumulates time spent per stage across concurrent work.
public final class StageTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var totals: [ScanStage: Double] = [:]
    private var counts: [ScanStage: Int] = [:]

    public init() {}

    func measure<T>(_ stage: ScanStage, _ work: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer { record(stage, since: start) }
        return try work()
    }

    func measure<T>(_ stage: ScanStage, _ work: () async throws -> T) async rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer { record(stage, since: start) }
        return try await work()
    }

    private func record(_ stage: ScanStage, since start: UInt64) {
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        lock.lock()
        totals[stage, default: 0] += seconds
        counts[stage, default: 0] += 1
        lock.unlock()
    }

    /// Total seconds spent in each stage (summed across concurrent workers).
    public var summary: [(stage: ScanStage, seconds: Double, count: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return ScanStage.allCases.map { ($0, totals[$0] ?? 0, counts[$0] ?? 0) }
    }
}

/// Reads screenshots on the phone: fetch, downscale, nudity screen, text, entities, sensitive
/// text, classification, expiry, palette, thumbnail. Nothing leaves the device.
public final class ScanPipeline: Sendable {
    /// The first scan looks back this far.
    public static let lookback: TimeInterval = 60 * 86_400

    public let database: AppDatabase
    private let library: ScreenshotLibrary
    private let screening: any NudityScreening
    private let recognizer: TextRecognizer
    private let detector: EntityDetector
    private let classifier: CategoryClassifier
    private let thumbnailDirectory: URL?
    /// Screenshots read at once. Two or three keeps an iPhone 8 busy without thrashing memory.
    public let concurrency: Int

    public init(
        database: AppDatabase,
        library: ScreenshotLibrary = ScreenshotLibrary(),
        screening: any NudityScreening = OnDeviceNudityScreen(),
        classifier: CategoryClassifier = CategoryClassifier(),
        thumbnailDirectory: URL? = try? AppGroup.directory(.thumbnails),
        concurrency: Int = 3
    ) {
        self.database = database
        self.library = library
        self.screening = screening
        self.recognizer = TextRecognizer()
        self.detector = EntityDetector()
        self.classifier = classifier
        self.thumbnailDirectory = thumbnailDirectory
        self.concurrency = concurrency
    }

    // MARK: Discovery

    /// Records screenshots from the last two months that aren't recorded yet. Fast: metadata
    /// only. Always looks at the whole window, not just since the last scan, because screenshots
    /// can arrive late with older dates (iCloud Photos filling in on a new phone).
    /// Returns how many were new.
    @discardableResult
    public func discover(now: Date = Date()) throws -> Int {
        let since = now.addingTimeInterval(-Self.lookback)
        let known = try database.knownAssetIDs(createdAfter: since)
        let found = library.discover(since: since, skipping: known)
        let inserted = try database.recordDiscovered(found, now: now)
        // Screenshots recorded before their cloud identifier could be resolved (iCloud Photos
        // still catching up) get it now.
        let unresolved = try database.assetIDsWithoutCloudID(createdAfter: since)
        if !unresolved.isEmpty {
            try database.setCloudIDs(library.cloudIdentifiers(for: unresolved), now: now)
        }
        try database.markScanned(at: now)
        return inserted
    }

    // MARK: Reading

    /// Reads every screenshot not yet read (newest first), saving as it goes so a crash or a
    /// background expiry loses nothing. Calls `progress` after each batch.
    public func readPending(
        limit: Int? = nil,
        includeBackfill: Bool = false,
        timer: StageTimer? = nil,
        progress: @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws {
        var pending = try database.unprocessedItems(limit: limit ?? Int.max)
        if includeBackfill {
            pending += try database.backfillItems(limit: limit ?? Int.max)
        }
        if let limit {
            pending = Array(pending.prefix(limit))
        }
        let total = pending.count
        progress(ScanProgress(read: 0, total: total))

        var processed: [ScreenshotItem] = []
        var read = 0
        do {
            for batch in stride(from: 0, to: pending.count, by: concurrency).map({ Array(pending[$0..<min($0 + concurrency, pending.count)]) }) {
                try Task.checkCancellation()
                let results = await withTaskGroup(of: ScreenshotItem?.self) { group in
                    for item in batch {
                        group.addTask { await self.read(item, timer: timer) }
                    }
                    var results: [ScreenshotItem] = []
                    for await result in group {
                        if let result {
                            results.append(result)
                        }
                    }
                    return results
                }
                try measure(.save, timer) { try database.saveReadResults(results) }
                processed += results
                read += batch.count
                progress(ScanProgress(read: read, total: total))
            }
        } catch {
            // Cancelled (or failed) part-way: what was read is still grouped.
            try? groupNearDuplicates(processed)
            throw error
        }
        try groupNearDuplicates(processed)
    }

    /// Reads one screenshot. Nil when it couldn't be read this time (it failed to load, or a
    /// screen or Vision failed): it stays unread, to be tried on the next run.
    func read(_ original: ScreenshotItem, timer: StageTimer?, now: Date = Date()) async -> ScreenshotItem? {
        var item = original
        item.updatedAt = now

        // Cloud-only screenshots are skipped on the first pass and downloaded on the backfill pass.
        let loaded = await measure(.load, timer) {
            await self.library.loadImage(localIdentifier: item.assetLocalID, allowsNetwork: original.needsBackfill)
        }
        let image: CGImage
        switch loaded {
        case .cloudOnly:
            item.needsBackfill = true
            return item
        case .missing:
            item.processedAt = now
            item.needsBackfill = false
            return item
        case .unavailable:
            return nil
        case .image(let loadedImage):
            image = loadedImage
        }
        return await attemptAnalysis(item, image: image, timer: timer, now: now)
    }

    /// Everything after loading, given the image. Shared with the share extension, which receives
    /// images rather than library assets. If the nudity screen or Vision fails, the result is
    /// filed unread and never displayed (see `attemptAnalysis` to try again instead).
    public func analyse(_ original: ScreenshotItem, image: CGImage, timer: StageTimer? = nil, now: Date = Date()) async -> ScreenshotItem {
        if let item = await attemptAnalysis(original, image: image, timer: timer, now: now) {
            return item
        }
        var item = original
        item.updatedAt = now
        item.processedAt = now
        item.needsBackfill = false
        item.isSafeToDisplay = false
        return item
    }

    /// Like `analyse`, but nil when the nudity screen or text recognition failed, so the caller
    /// can leave the screenshot to be read again rather than keep a guess.
    func attemptAnalysis(_ original: ScreenshotItem, image: CGImage, timer: StageTimer? = nil, now: Date = Date()) async -> ScreenshotItem? {
        var item = original
        item.updatedAt = now
        item.processedAt = now
        item.needsBackfill = false

        // Nudity first: a flagged screenshot is never read further, never kept as text and never
        // displayed anywhere. If the screen can't tell, nothing is kept: fail closed.
        let screened = await measure(.nudity, timer) { await self.screening.isFlaggedIfKnown(image) }
        guard let flagged = screened else { return nil }
        if flagged {
            item.isNSFWFlagged = true
            item.isSafeToDisplay = false
            item.category = .other
            item.confidence = 0
            item.entities = []
            item.extractedText = nil
            item.title = nil
            item.palette = []
            item.thumbnailPath = nil
            return item
        }

        guard let text = measure(.text, timer, { try? recognizer.recognize(image) }) else { return nil }
        // Ignore the status bar, so its clock never reads as a date.
        let content = text.lines.filter { $0.box.minY < 0.94 }.map(\.text).joined(separator: "\n")
        let entities = measure(.entities, timer) { detector.entities(in: content, capturedAt: item.createdAt, now: now) }
        let sensitive = SensitiveTextDetector.findings(in: text.fullText)
        let verdict = SafetyVerdict(isNSFWFlagged: false, sensitiveText: sensitive)
        let classification = measure(.classify, timer) {
            classifier.classify(text, entities: entities, hasSensitiveText: verdict.hasSensitiveText)
        }
        let dates = ExpiryPolicy.dates(category: classification.category, entities: entities, text: content, createdAt: item.createdAt)

        item.category = classification.category
        item.confidence = classification.confidence
        item.entities = entities
        item.extractedText = text.fullText
        item.title = TitleExtractor.title(from: text)
        item.hasDate = entities.contains(where: \.namesADay)
        item.dueDate = dates.dueDate
        item.expiresAt = dates.expiresAt
        item.reviewAt = dates.reviewAt
        item.isNSFWFlagged = false
        item.hasSensitiveText = verdict.hasSensitiveText
        // Nothing to do about a chat, a post or a receipt: filed away without asking, never sorted.
        if verdict.hasSensitiveText || !classification.category.isActionable, item.state == .unreviewed {
            item.state = .reference
        }
        item.isSafeToDisplay = Safety.isSafeToDisplay(category: classification.category, confidence: classification.confidence, verdict: verdict)
        item.palette = measure(.palette, timer) { PaletteExtractor.palette(of: image) }

        // Only safe items get a thumbnail in the shared container, because only they may reach
        // the widget.
        if item.isSafeToDisplay, let directory = thumbnailDirectory {
            item.thumbnailPath = measure(.thumbnail, timer) { try? Thumbnailer.write(image, id: item.id, directory: directory) }
        } else {
            item.thumbnailPath = nil
        }
        return item
    }

    // MARK: Reclassifying

    /// Bumped when the categories or their rules change, so screenshots read before are sorted
    /// into the new ones.
    public static let classifierVersion = 2
    private static let classifierVersionKey = "scan.classifierVersion"

    /// Runs the classifier again over screenshots read by an older version, from the text kept
    /// from the first read (no image needed). Returns how many changed category.
    @discardableResult
    public func reclassifyIfNeeded(defaults: UserDefaults? = AppGroup.defaults()) throws -> Int {
        guard let defaults, defaults.integer(forKey: Self.classifierVersionKey) < Self.classifierVersion else { return 0 }
        let changed = try reclassify(try database.readItems())
        defaults.set(Self.classifierVersion, forKey: Self.classifierVersionKey)
        return changed
    }

    /// Reclassifies `items` and saves the ones whose category changed, onto the rows as they are
    /// now (see `AppDatabase.saveReclassified`: the state follows the new category).
    func reclassify(_ items: [ScreenshotItem], now: Date = Date()) throws -> Int {
        var changed: [ScreenshotItem] = []
        for var item in items where !item.isNSFWFlagged {
            guard let extracted = item.extractedText, !extracted.isEmpty else { continue }
            // The layout isn't kept, only the lines: enough for every rule but the chat bubbles.
            let lines = extracted.components(separatedBy: .newlines).map {
                TextLine(text: $0, box: CGRect(x: 0.05, y: 0.5, width: 0.8, height: 0.01))
            }
            let text = RecognizedText(lines: lines)
            let classification = classifier.classify(text, entities: item.entities, hasSensitiveText: item.hasSensitiveText)
            guard classification.category != item.category else { continue }
            // Image labels aren't kept: a screenshot placed by them alone keeps its place. But with
            // enough text to have been placed by the text (labels are only asked for when there's
            // little), Other is a real change of mind, and a thing to do that no longer reads like
            // one stops being offered.
            if classification.category == .other {
                guard item.category.isActionable, text.wordCount >= recognizer.littleTextWordCount else { continue }
            }
            item.category = classification.category
            item.confidence = classification.confidence
            let dates = ExpiryPolicy.dates(category: item.category, entities: item.entities, text: extracted, createdAt: item.createdAt)
            item.dueDate = dates.dueDate
            item.expiresAt = dates.expiresAt
            item.reviewAt = dates.reviewAt
            item.isSafeToDisplay = item.thumbnailPath != nil
                && item.category.isDisplayableIntention
                && item.confidence >= Safety.confidenceBar
                && !item.hasSensitiveText
            changed.append(item)
        }
        guard !changed.isEmpty else { return 0 }
        return try database.saveReclassified(changed, now: now)
    }

    // MARK: Grouping

    /// Collapses near-duplicates among freshly read items and their neighbours in time that are
    /// still waiting to be sorted.
    func groupNearDuplicates(_ items: [ScreenshotItem]) throws {
        let readable = items.filter { $0.processedAt != nil && !$0.isNSFWFlagged }
        guard let first = readable.map(\.createdAt).min(), let last = readable.map(\.createdAt).max() else { return }
        let ids = Set(readable.map(\.id))
        let neighbours = try database
            .unreviewedItems(createdBetween: first.addingTimeInterval(-Grouper.window)...last.addingTimeInterval(Grouper.window))
            .filter { !ids.contains($0.id) }
        let candidates = readable + neighbours
        guard candidates.count > 1 else { return }
        let members = candidates.map {
            Grouper.Member(id: $0.id, createdAt: $0.createdAt, words: RecognizedText.words(in: $0.extractedText ?? ""), groupID: $0.groupID)
        }
        let groupIDs = Grouper.groups(for: members)
        guard !groupIDs.isEmpty else { return }

        var byGroup: [String: [ScreenshotItem]] = [:]
        for item in candidates {
            if let groupID = groupIDs[item.id] {
                byGroup[groupID, default: []].append(item)
            }
        }
        try database.saveGroups(byGroup)
    }

    private func measure<T>(_ stage: ScanStage, _ timer: StageTimer?, _ work: () throws -> T) rethrows -> T {
        if let timer {
            return try timer.measure(stage, work)
        }
        return try work()
    }

    private func measure<T>(_ stage: ScanStage, _ timer: StageTimer?, _ work: () async throws -> T) async rethrows -> T {
        if let timer {
            return try await timer.measure(stage, work)
        }
        return try await work()
    }
}

extension RecognizedText {
    static func words(in text: String) -> Set<String> {
        RecognizedText(lines: [TextLine(text: text, box: .zero)]).words
    }
}
