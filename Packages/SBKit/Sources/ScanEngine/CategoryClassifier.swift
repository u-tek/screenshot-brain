import Core
import Foundation

/// One piece of evidence the rules found.
public struct Signal: Hashable, Sendable {
    public var category: ItemCategory
    public var name: String
    public var weight: Double

    public init(_ category: ItemCategory, _ name: String, _ weight: Double = 1) {
        self.category = category
        self.name = name
        self.weight = weight
    }
}

public struct Classification: Hashable, Sendable {
    public var category: ItemCategory
    /// 0...1.
    public var confidence: Double
    /// Every signal found, for the debug "why" view and for tests.
    public var signals: [Signal]
}

/// A transparent rules engine. Each rule adds a named signal; a category is assigned only when
/// several signals agree and it clearly beats the runner-up. Anything uncertain is Other and goes
/// to triage, never silently into Reference.
public struct CategoryClassifier: Sendable {
    /// Categories that have reached the accuracy bar with test users. Any other category is
    /// reported as Other. Tunable as the accuracy harness collects data.
    public var shippedCategories: Set<ItemCategory> = Set(ItemCategory.allCases)
    /// A category needs at least this much combined evidence ("several signals agree").
    public var minimumScore = 2.0
    /// ...and must lead the runner-up by at least this much.
    public var minimumMargin = 0.75

    public init() {}

    public func classify(_ text: RecognizedText, entities: [DetectedEntity], hasSensitiveText: Bool) -> Classification {
        let signals = Self.signals(text: text, entities: entities)

        // Card numbers, bank details, passwords and codes always go to Reference.
        if hasSensitiveText {
            return Classification(category: .reference, confidence: 0.99, signals: signals + [Signal(.reference, "sensitive text", 3)])
        }

        var scores: [ItemCategory: Double] = [:]
        for signal in signals {
            scores[signal.category, default: 0] += signal.weight
        }
        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first else {
            return Classification(category: .other, confidence: 0, signals: signals)
        }
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        let distinctSignals = signals.filter { $0.category == best.key }.count
        let margin = best.value - runnerUp

        let confident = best.value >= minimumScore && distinctSignals >= 2 && margin >= minimumMargin
        guard confident, shippedCategories.contains(best.key) else {
            return Classification(category: .other, confidence: min(0.5, best.value / 4), signals: signals)
        }
        let confidence = min(0.99, 0.55 + 0.12 * best.value + 0.08 * margin)
        return Classification(category: best.key, confidence: confidence, signals: signals)
    }

    // MARK: Rules

    static func signals(text: RecognizedText, entities: [DetectedEntity]) -> [Signal] {
        let body = text.fullText.lowercased()
        func has(_ words: [String]) -> Bool {
            words.contains { body.contains($0) }
        }
        func count(_ kind: DetectedEntity.Kind) -> Int {
            entities.filter { $0.kind == kind }.count
        }
        var signals: [Signal] = []

        // Event: a date plus venue or ticket words.
        let dayDates = entities.filter(\.namesADay).count
        if dayDates > 0 { signals.append(Signal(.event, "names a day", 1)) }
        if has(Words.event) { signals.append(Signal(.event, "ticket or venue words", 1)) }
        if has(Words.eventStrong) { signals.append(Signal(.event, "doors, tickets or lineup", 0.5)) }

        // Place: an address, ratings, or a map layout.
        if count(.address) > 0 { signals.append(Signal(.place, "address", 1)) }
        if count(.rating) > 0 || count(.reviewCount) > 0 { signals.append(Signal(.place, "rating or reviews", 1)) }
        if has(Words.place) { signals.append(Signal(.place, "map or venue words", 1)) }
        if count(.phoneNumber) > 0 && count(.address) > 0 { signals.append(Signal(.place, "phone and address", 0.25)) }

        // Product: a price plus shopping words.
        if count(.price) > 0 { signals.append(Signal(.product, "price", 1)) }
        if has(Words.shopping) { signals.append(Signal(.product, "shopping words", 1)) }
        if count(.price) > 0 && has(Words.shoppingStrong) { signals.append(Signal(.product, "add to bag", 0.5)) }

        // Recipe: ingredient quantities plus method words.
        let quantities = ingredientLineCount(text)
        if quantities >= 3 { signals.append(Signal(.recipe, "ingredient quantities", 1)) }
        if quantities >= 6 { signals.append(Signal(.recipe, "many ingredients", 0.5)) }
        if has(Words.method) { signals.append(Signal(.recipe, "method words", 1)) }

        // Reference: chats, codes, boarding passes, wifi and passwords, receipts.
        if chatTimestampCount(text) >= 3 { signals.append(Signal(.reference, "chat timestamps", 1)) }
        if has(Words.chat) { signals.append(Signal(.reference, "messaging words", 1)) }
        if text.codeCount > 0 { signals.append(Signal(.reference, "QR or barcode", 1)) }
        if has(Words.boarding) { signals.append(Signal(.reference, "boarding pass", 1.5)) }
        if has(Words.wifi) { signals.append(Signal(.reference, "wifi details", 1.5)) }
        if has(Words.receipt) { signals.append(Signal(.reference, "receipt", 1)) }
        if count(.transit) > 0 { signals.append(Signal(.reference, "transit details", 0.5)) }

        // Little text: Vision's image labels, as a weak fallback.
        for label in text.imageLabels {
            if Words.foodLabels.contains(where: { label.contains($0) }) { signals.append(Signal(.recipe, "looks like food", 0.75)) }
            if Words.productLabels.contains(where: { label.contains($0) }) { signals.append(Signal(.product, "looks like a product", 0.75)) }
            if Words.placeLabels.contains(where: { label.contains($0) }) { signals.append(Signal(.place, "looks like a place", 0.75)) }
            if Words.eventLabels.contains(where: { label.contains($0) }) { signals.append(Signal(.event, "looks like a gig", 0.75)) }
        }
        return signals
    }

    static func ingredientLineCount(_ text: RecognizedText) -> Int {
        text.lines.filter { line in
            line.text.lowercased().range(of: Patterns.ingredient, options: .regularExpression) != nil
        }.count
    }

    static func chatTimestampCount(_ text: RecognizedText) -> Int {
        text.lines.filter { line in
            line.box.minY < 0.94 && line.text.range(of: Patterns.timestamp, options: .regularExpression) != nil
        }.count
    }

    enum Patterns {
        static let ingredient =
            #"(?:^|\s)(?:\d+(?:[./]\d+)?|½|¼|¾|⅓|⅔)\s?(?:cups?|tbsp|tsp|tablespoons?|teaspoons?|g|grams?|kg|ml|l|oz|lb|cloves?|pinch|handful|cans?|slices?)\b"#
        static let timestamp = #"^\s*\d{1,2}:\d{2}\s*(?:am|pm|AM|PM)?\s*$"#
    }

    enum Words {
        static let event = ["tickets", "ticket", "doors", "live at", "tour", "presale", "festival", "venue", "gig",
                            "concert", "rsvp", "admission", "lineup", "line-up", "support act", "dj set",
                            "eventbrite", "ticketek", "ticketmaster", "moshtix", "dice", "humanitix", "interested"]
        static let eventStrong = ["doors open", "buy tickets", "get tickets", "tickets on sale", "lineup", "sold out show"]
        static let place = ["directions", "open now", "closes", "opens at", "menu", "reserve", "book a table",
                            "hours", "get directions", "min walk", "km away", "restaurant", "cafe", "café", "bar ·",
                            "bakery", "dine-in", "takeaway", "reservations", "google maps", "open ·", "closed ·"]
        static let shopping = ["add to bag", "add to cart", "buy now", "checkout", "in stock", "free shipping",
                               "free delivery", "size guide", "select size", "afterpay", "klarna", "zip pay", "wishlist",
                               "sold out", "colour", "color:", "add to basket", "shop now", "pre-order", "% off"]
        static let shoppingStrong = ["add to bag", "add to cart", "buy now", "add to basket"]
        static let method = ["preheat", "stir", "bake", "whisk", "simmer", "serves", "prep time", "cook time",
                             "ingredients", "method", "season with", "oven", "minutes until", "chop", "fry"]
        static let chat = ["imessage", "delivered", "read ", "typing…", "typing...", "online", "last seen", "reply"]
        static let boarding = ["boarding pass", "boarding", "gate", "seat", "flight", "departure", "check-in"]
        static let wifi = ["wi-fi", "wifi", "ssid", "network name", "wpa"]
        static let receipt = ["subtotal", "total", "gst", "tax invoice", "receipt", "order #", "order number",
                              "paid", "invoice", "amount due", "card ending"]
        static let foodLabels = ["food", "dish", "meal", "dessert", "baked", "cake", "pizza", "salad", "soup", "pasta"]
        static let productLabels = ["clothing", "shoe", "sneaker", "bag", "handbag", "watch", "jewelry", "furniture", "dress"]
        static let placeLabels = ["restaurant", "cafe", "interior_room", "building", "beach", "mountain", "landscape", "hotel"]
        static let eventLabels = ["concert", "stage", "performance", "crowd", "festival"]
    }
}
