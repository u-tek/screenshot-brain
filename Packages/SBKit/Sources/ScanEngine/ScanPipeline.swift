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

    /// Records screenshots from the last two months (or since the last scan). Fast: metadata only.
    /// Returns how many were new.
    @discardableResult
    public func discover(now: Date = Date()) throws -> Int {
        let state = try database.scanState()
        let since = state.lastScanAt.map { $0.addingTimeInterval(-3_600) } ?? now.addingTimeInterval(-Self.lookback)
        let found = library.discover(since: since)
        let inserted = try database.recordDiscovered(found, now: now)
        var updated = state
        updated.lastScanAt = now
        updated.updatedAt = now
        try database.save(updated)
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
        for batch in stride(from: 0, to: pending.count, by: concurrency).map({ Array(pending[$0..<min($0 + concurrency, pending.count)]) }) {
            try Task.checkCancellation()
            let results = await withTaskGroup(of: ScreenshotItem.self) { group in
                for item in batch {
                    group.addTask { await self.read(item, timer: timer) }
                }
                var results: [ScreenshotItem] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            try measure(.save, timer) { try database.save(results) }
            processed += results
            read += results.count
            progress(ScanProgress(read: read, total: total))
        }
        try groupNearDuplicates(processed)
    }

    /// Reads one screenshot.
    func read(_ original: ScreenshotItem, timer: StageTimer?, now: Date = Date()) async -> ScreenshotItem {
        var item = original
        item.updatedAt = now

        let loaded = await measure(.load, timer) { await self.library.loadImage(localIdentifier: item.assetLocalID) }
        let image: CGImage
        switch loaded {
        case .cloudOnly:
            item.needsBackfill = true
            return item
        case .missing:
            item.processedAt = now
            item.needsBackfill = false
            return item
        case .image(let loadedImage):
            image = loadedImage
        }
        return await analyse(item, image: image, timer: timer, now: now)
    }

    /// Everything after loading, given the image. Shared with the share extension, which receives
    /// images rather than library assets.
    public func analyse(_ original: ScreenshotItem, image: CGImage, timer: StageTimer? = nil, now: Date = Date()) async -> ScreenshotItem {
        var item = original
        item.updatedAt = now
        item.processedAt = now
        item.needsBackfill = false

        // Nudity first: a flagged screenshot is never read further, never kept as text and never
        // displayed anywhere.
        let flagged = await measure(.nudity, timer) { await self.screening.isFlagged(image) }
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

        let text = measure(.text, timer) { (try? recognizer.recognize(image)) ?? RecognizedText(lines: []) }
        // Ignore the status bar, so its clock never reads as a date.
        let content = text.lines.filter { $0.box.minY < 0.94 }.map(\.text).joined(separator: "\n")
        let entities = measure(.entities, timer) { detector.entities(in: content) }
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
        if verdict.hasSensitiveText, item.state == .unreviewed {
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

    // MARK: Grouping

    /// Collapses near-duplicates among freshly read items (and their recent neighbours).
    func groupNearDuplicates(_ items: [ScreenshotItem]) throws {
        let readable = items.filter { $0.processedAt != nil && !$0.isNSFWFlagged }
        guard readable.count > 1 else { return }
        let members = readable.map {
            Grouper.Member(id: $0.id, createdAt: $0.createdAt, words: RecognizedText.words(in: $0.extractedText ?? ""))
        }
        let groupIDs = Grouper.groups(for: members)
        guard !groupIDs.isEmpty else { return }

        var byGroup: [String: [ScreenshotItem]] = [:]
        for item in readable {
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
