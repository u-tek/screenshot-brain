import Foundation

/// What a screenshot is for. Assigned by the ScanEngine's rules only when several signals agree;
/// anything uncertain is `.other` and goes to triage, never silently into `.reference`.
public enum ItemCategory: String, Codable, CaseIterable, Sendable {
    case place
    case event
    case product
    case recipe
    case reference
    case other

    /// Shown in triage and counted towards follow-through. Reference is kept for search only.
    public var isIntention: Bool {
        self != .reference
    }

    /// The only categories that may reach the widget, the Reveal's example thumbnails or anything
    /// shareable. The safety filters apply on top of this.
    public var isDisplayableIntention: Bool {
        switch self {
        case .place, .event, .product, .recipe: true
        case .reference, .other: false
        }
    }
}

public enum ItemState: String, Codable, CaseIterable, Sendable {
    case unreviewed
    case stillWant
    case done
    case dropped
    case reference
}

/// A coarse time of day, used by the "when do you screenshot the most?" question.
public enum DayPeriod: String, Codable, CaseIterable, Sendable {
    case morning
    case afternoon
    case evening
    case lateNight

    public init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .lateNight
        }
    }
}

/// The first-open flow, in order. Persisted so onboarding resumes and is never repeated.
public enum OnboardingStep: String, Codable, CaseIterable, Sendable, Comparable {
    case signIn
    case pitch
    case photoAccess
    case questions
    case finishingUp
    case reveal
    case triage
    case score
    case paywall
    case notifications
    case widgetGuide
    case home

    public static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// Something the entity detectors found in a screenshot's text.
///
/// Holds extracted text, so it is stored on-device only and never synced.
public struct DetectedEntity: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case date
        case address
        case link
        case phoneNumber
        case transit
        case price
        case rating
        case reviewCount
    }

    public var kind: Kind
    /// The matched text, exactly as recognised.
    public var text: String
    public var date: Date?
    public var duration: TimeInterval?
    public var url: URL?
    public var amount: Decimal?
    public var currencyCode: String?

    public init(
        kind: Kind,
        text: String,
        date: Date? = nil,
        duration: TimeInterval? = nil,
        url: URL? = nil,
        amount: Decimal? = nil,
        currencyCode: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.date = date
        self.duration = duration
        self.url = url
        self.amount = amount
        self.currencyCode = currencyCode
    }
}

/// One dominant colour of a screenshot, in sRGB with components in 0...1.
/// An item's palette becomes its light: the soft colour that glows behind its glass.
public struct PaletteColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    /// Share of the image this colour covers, 0...1.
    public var weight: Double

    public init(red: Double, green: Double, blue: Double, weight: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.weight = weight
    }
}
