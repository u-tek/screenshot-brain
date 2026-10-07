import Core

/// The outcome of the safety filters for one screenshot.
public struct SafetyVerdict: Hashable, Sendable {
    public var isNSFWFlagged: Bool
    public var sensitiveText: Set<SensitiveTextKind>

    public init(isNSFWFlagged: Bool, sensitiveText: Set<SensitiveTextKind>) {
        self.isNSFWFlagged = isNSFWFlagged
        self.sensitiveText = sensitiveText
    }

    public var hasSensitiveText: Bool {
        !sensitiveText.isEmpty
    }
}

/// The safe-to-display rule, in one place.
///
/// Only items confidently classified as a Place, Event, Product or Recipe that pass both filters
/// may appear on the widget, as the Reveal's example thumbnails, or on anything shareable.
public enum Safety {
    /// Categories are only claimed above this confidence. Below it, an item shows as Other.
    public static let confidenceBar = 0.8

    public static func isSafeToDisplay(category: ItemCategory, confidence: Double, verdict: SafetyVerdict) -> Bool {
        category.isDisplayableIntention
            && confidence >= confidenceBar
            && !verdict.isNSFWFlagged
            && !verdict.hasSensitiveText
    }
}
