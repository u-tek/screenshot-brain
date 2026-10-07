import Core
import CoreGraphics
import Foundation

// MARK: - Palette

/// A screenshot's dominant colours, for its light. Averages a 3×3 grid of the image and merges
/// cells that are nearly the same colour.
public enum PaletteExtractor {
    public static func palette(of image: CGImage) -> [PaletteColor] {
        // Draw small, then average each third: cheap and robust to noise.
        let width = 24, height = 48
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }

        var cells: [PaletteColor] = []
        let cellWidth = width / 3, cellHeight = height / 3
        for row in 0..<3 {
            for column in 0..<3 {
                var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
                for y in (row * cellHeight)..<((row + 1) * cellHeight) {
                    for x in (column * cellWidth)..<((column + 1) * cellWidth) {
                        let offset = y * bytesPerRow + x * 4
                        red += Double(pixels[offset])
                        green += Double(pixels[offset + 1])
                        blue += Double(pixels[offset + 2])
                        count += 1
                    }
                }
                cells.append(PaletteColor(red: red / count / 255, green: green / count / 255, blue: blue / count / 255, weight: 1.0 / 9))
            }
        }
        return merge(cells)
    }

    static func merge(_ colors: [PaletteColor], threshold: Double = 0.08) -> [PaletteColor] {
        var merged: [PaletteColor] = []
        for color in colors {
            if let index = merged.firstIndex(where: { distance($0, color) < threshold }) {
                let existing = merged[index]
                let total = existing.weight + color.weight
                merged[index] = PaletteColor(
                    red: (existing.red * existing.weight + color.red * color.weight) / total,
                    green: (existing.green * existing.weight + color.green * color.weight) / total,
                    blue: (existing.blue * existing.weight + color.blue * color.weight) / total,
                    weight: total
                )
            } else {
                merged.append(color)
            }
        }
        return merged.sorted { $0.weight > $1.weight }
    }

    private static func distance(_ a: PaletteColor, _ b: PaletteColor) -> Double {
        let dr = a.red - b.red, dg = a.green - b.green, db = a.blue - b.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}

// MARK: - Expiry

/// When things expire or get a "still want this?" prompt. All tunable.
public enum ExpiryPolicy {
    /// Events expire the day after the event...
    public static let eventGraceDays = 1
    /// ...with a nudge this many days before.
    public static let eventNudgeDaysBefore = 2
    /// Products expire after this long, or when a detected sale end passes.
    public static let productLifetimeDays = 30
    /// Places and recipes get a "still want this?" prompt after this long.
    public static let stillWantPromptDays = 60

    public struct Dates: Hashable, Sendable {
        public var dueDate: Date? = nil
        public var expiresAt: Date? = nil
        public var reviewAt: Date? = nil
    }

    public static func dates(
        category: ItemCategory,
        entities: [DetectedEntity],
        text: String,
        createdAt: Date,
        calendar: Calendar = .current
    ) -> Dates {
        let dayDates = entities.filter(\.namesADay).compactMap(\.date)
        // The date that matters is the first one on or after the day the screenshot was taken.
        let startOfCapture = calendar.startOfDay(for: createdAt)
        let relevant = dayDates.filter { $0 >= startOfCapture }.min()

        switch category {
        case .event:
            guard let eventDate = relevant else { return Dates() }
            let dayAfter = calendar.date(byAdding: .day, value: eventGraceDays + 1, to: calendar.startOfDay(for: eventDate))
            return Dates(dueDate: eventDate, expiresAt: dayAfter)
        case .product:
            let lifetime = calendar.date(byAdding: .day, value: productLifetimeDays, to: createdAt)
            let mentionsSale = ["sale", "ends", "until", "offer"].contains { text.lowercased().contains($0) }
            if mentionsSale, let saleEnd = relevant {
                let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: saleEnd))
                return Dates(dueDate: saleEnd, expiresAt: [lifetime, end].compactMap { $0 }.min())
            }
            return Dates(expiresAt: lifetime)
        case .place, .recipe:
            return Dates(reviewAt: calendar.date(byAdding: .day, value: stillWantPromptDays, to: createdAt))
        case .reference, .other:
            return Dates()
        }
    }

    /// When to nudge about a dated item.
    public static func nudgeDate(for dueDate: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: -eventNudgeDaysBefore, to: calendar.startOfDay(for: dueDate))
    }
}

// MARK: - Grouping

/// Near-duplicates: screenshots taken within about a minute of each other with overlapping text.
public enum Grouper {
    public static let window: TimeInterval = 60
    public static let minimumOverlap = 0.5

    public struct Member: Hashable, Sendable {
        public var id: String
        public var createdAt: Date
        public var words: Set<String>

        public init(id: String, createdAt: Date, words: Set<String>) {
            self.id = id
            self.createdAt = createdAt
            self.words = words
        }
    }

    /// Returns a group ID for each member that belongs to a group of two or more.
    public static func groups(for members: [Member]) -> [String: String] {
        let sorted = members.sorted { $0.createdAt < $1.createdAt }
        var groupOf: [String: String] = [:]
        for (index, member) in sorted.enumerated() {
            for previous in sorted[..<index].reversed() {
                guard member.createdAt.timeIntervalSince(previous.createdAt) <= window else { break }
                guard overlap(member.words, previous.words) >= minimumOverlap else { continue }
                let groupID = groupOf[previous.id] ?? "group-\(previous.id)"
                groupOf[previous.id] = groupID
                groupOf[member.id] = groupID
                break
            }
        }
        return groupOf
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }
}

// MARK: - Title

public enum TitleExtractor {
    /// The most prominent line of real words outside the status bar: the tallest text, preferring
    /// the upper part of the screen.
    public static func title(from text: RecognizedText) -> String? {
        let candidates = text.lines.filter { line in
            line.box.minY < 0.93
                && line.text.filter(\.isLetter).count >= 3
                && line.text.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) == nil
        }
        let best = candidates.max { lhs, rhs in
            score(lhs) < score(rhs)
        }
        guard let best else { return nil }
        let trimmed = best.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
    }

    private static func score(_ line: TextLine) -> Double {
        // Taller text matters more; a little bonus for being higher on the screen.
        Double(line.box.height) * 10 + Double(line.box.midY) * 0.2
    }
}
