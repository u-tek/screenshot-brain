import Foundation

/// What a screenshot is for. Assigned by the ScanEngine's rules from the signals in it.
///
/// Some kinds are things to do (go, buy, cook, watch); the rest are worth keeping but there's
/// nothing to do about them (a chat, a post, a receipt). Only the first lot are sorted: the rest
/// are filed away without asking, and stay searchable.
public enum ItemCategory: String, Codable, CaseIterable, Sendable {
    case place
    case event
    case product
    case recipe
    /// Films, shows and videos to watch.
    case watch
    /// Music and podcasts.
    case listen
    /// Books and articles.
    case read
    /// Flights, stays and trips to plan.
    case travel
    /// Chats, DMs and emails.
    case message
    /// Social posts and memes.
    case post
    /// Receipts, codes, boarding passes, wifi details: kept to look up.
    case reference
    /// Nothing recognisable. Filed away with the keep-only kinds.
    case other

    /// Something to do: go, buy, cook, watch, listen, read, plan. These are sorted, counted in
    /// the score and offered by the widget.
    public var isActionable: Bool {
        switch self {
        case .place, .event, .product, .recipe, .watch, .listen, .read, .travel: true
        case .message, .post, .reference, .other: false
        }
    }

    /// Shown in triage and counted towards follow-through.
    public var isIntention: Bool {
        isActionable
    }

    /// The only categories that may reach the widget, the Reveal's example thumbnails or anything
    /// shareable. The safety filters apply on top of this. Chats and posts never do: they're
    /// other people's words.
    public var isDisplayableIntention: Bool {
        isActionable
    }

    /// The things to do, for queries.
    public static let actionable = allCases.filter(\.isActionable)
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
///
/// The pitch comes before sign-in: asking for an account on the very first screen, before anyone
/// knows what the app does, costs more people than it keeps.
public enum OnboardingStep: String, Codable, CaseIterable, Sendable, Comparable {
    case pitch
    case signIn
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

extension DetectedEntity {
    /// True when a detected date says a time of day ("8pm", "19:30", "noon"). A day on its own
    /// ("Sat 14 Oct") comes back from the data detector at noon, a time nobody wrote.
    public var namesATime: Bool {
        guard kind == .date else { return false }
        let pattern = #"\d:\d{2}|\d\s?(?:[ap]m\b|[ap]\.m\.)|\bnoon\b|\bmidnight\b"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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
