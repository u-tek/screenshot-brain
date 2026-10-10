import Core
import Foundation
import Store

/// One-tap follow-through for a saved thing.
public enum ItemAction: String, CaseIterable, Sendable, Identifiable {
    case calendar
    case maps
    case shop
    /// The show, album, book or trip: its link, or a search for it.
    case lookUp
    case ingredients
    case send

    public var id: String { rawValue }

    /// The suggestion on a triage card: "Add to calendar".
    public var title: String {
        switch self {
        case .calendar: "Add to calendar"
        case .maps: "Open in Maps"
        case .shop: "Open shop"
        case .lookUp: "Look it up"
        case .ingredients: "Copy ingredients"
        case .send: "Send to someone"
        }
    }

    /// The chip in item detail: "Calendar".
    public var shortTitle: String {
        switch self {
        case .calendar: "Calendar"
        case .maps: "Maps"
        case .shop: "Shop"
        case .lookUp: "Look up"
        case .ingredients: "Ingredients"
        case .send: "Send"
        }
    }

    public var systemImage: String {
        switch self {
        case .calendar: "calendar"
        case .maps: "map"
        case .shop: "bag"
        case .lookUp: "magnifyingglass"
        case .ingredients: "list.bullet"
        case .send: "paperplane"
        }
    }

    /// Every action that makes sense for this item, the most useful first.
    public static func available(for item: ScreenshotItem) -> [ItemAction] {
        var actions: [ItemAction] = []
        if EventDraft(item: item) != nil {
            actions.append(.calendar)
        }
        if item.category == .place || item.entities.contains(where: { $0.kind == .address }) {
            actions.append(.maps)
        }
        // Somewhere to go: the link read from it, or a search for its name.
        let lookedUp: Set<ItemCategory> = [.watch, .listen, .read, .travel]
        if ShopLink.url(for: item) != nil, lookedUp.contains(item.category) {
            actions.append(.lookUp)
        } else if ShopLink.url(for: item) != nil, item.category == .product || (ShopLink.detectedURL(for: item) != nil && item.category != .event) {
            actions.append(.shop)
        }
        if item.category == .recipe, !Ingredients.lines(in: item.extractedText ?? "").isEmpty {
            actions.append(.ingredients)
        }
        // Never offer to send something with card numbers, passwords or codes in it.
        if !item.hasSensitiveText {
            actions.append(.send)
        }
        // The category's own action leads.
        if let primary = primary(for: item.category), let index = actions.firstIndex(of: primary) {
            actions.insert(actions.remove(at: index), at: 0)
        }
        return actions
    }

    /// The one action to suggest for an item, if any.
    public static func suggested(for item: ScreenshotItem) -> ItemAction? {
        available(for: item).first { $0 != .send }
    }

    private static func primary(for category: ItemCategory) -> ItemAction? {
        switch category {
        case .event: .calendar
        case .place: .maps
        case .product: .shop
        case .recipe: .ingredients
        case .watch, .listen, .read, .travel: .lookUp
        case .message, .post, .reference, .other: nil
        }
    }
}

/// A calendar event drafted from what was read in a screenshot.
public struct EventDraft: Hashable, Sendable {
    /// When no duration was read: long enough for a gig or a booking.
    public static let defaultDuration: TimeInterval = 2 * 3_600

    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var url: URL?
    /// The screenshot named a day but no time.
    public var isAllDay: Bool

    /// Nil when there's no date to put in a calendar.
    public init?(item: ScreenshotItem, calendar: Calendar = .current) {
        let dated = item.entities.first { $0.kind == .date && $0.date != nil }
        guard let start = item.dueDate ?? dated?.date else { return nil }
        self.title = item.title ?? "Something you saved"
        let isAllDay = item.dueDate != nil ? !item.dueDateHasTime : dated?.namesATime == false
        self.isAllDay = isAllDay
        if isAllDay {
            let day = calendar.startOfDay(for: start)
            self.start = day
            self.end = day
        } else {
            self.start = start
            self.end = start.addingTimeInterval(dated?.duration ?? Self.defaultDuration)
        }
        self.location = item.entities.first { $0.kind == .address }?.text
        self.url = ShopLink.detectedURL(for: item)
    }
}

public enum ShopLink {
    /// A web link read from the screenshot.
    public static func detectedURL(for item: ScreenshotItem) -> URL? {
        item.entities.lazy
            .filter { $0.kind == .link }
            .compactMap(\.url)
            .first { $0.scheme == "https" || $0.scheme == "http" }
    }

    /// The detected link, or else a web search for what's in the screenshot.
    public static func url(for item: ScreenshotItem) -> URL? {
        if let detected = detectedURL(for: item) {
            return detected
        }
        guard let query = item.title, !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

public enum Ingredients {
    private static let quantity = try! NSRegularExpression(
        pattern: #"^\s*[-•*]?\s*(\d+(\s*[./]\s*\d+)?|\d*\s*[½¼¾⅓⅔⅛]|a\s+(pinch|handful|few)|pinch|handful)\s*(g|kg|ml|l|cups?|tbsps?|tsps?|tablespoons?|teaspoons?|oz|lbs?|cloves?|cans?|tins?|bunch(es)?|sprigs?|x)?\b"#,
        options: [.caseInsensitive]
    )

    /// Lines that read like ingredients: a quantity, maybe a unit, then the thing.
    public static func lines(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard line.filter(\.isLetter).count >= 2, line.count <= 80 else { return false }
                let range = NSRange(line.startIndex..., in: line)
                return quantity.firstMatch(in: line, range: range) != nil
            }
    }
}

public enum MapsQuery {
    /// What to look up: a detected address, or the place's name.
    public static func query(for item: ScreenshotItem) -> String? {
        item.entities.first { $0.kind == .address }?.text ?? item.title
    }
}

/// The text that goes with a screenshot sent to a friend.
public enum SendMessage {
    public static let text = "keen?\n\nsent with Screenshot Brain"
}
