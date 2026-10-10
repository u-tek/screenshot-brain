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

/// A transparent rules engine. Each rule adds a named signal. A category is assigned with
/// confidence when several signals agree and it clearly beats the runner-up; with less evidence
/// that still points one way, it's assigned as a lean, at a confidence below the display bar.
/// Anything else is Other.
public struct CategoryClassifier: Sendable {
    /// Categories that have reached the accuracy bar with test users. Any other category is
    /// reported as Other. Tunable as the accuracy harness collects data.
    public var shippedCategories: Set<ItemCategory> = Set(ItemCategory.allCases)
    /// A category needs at least this much combined evidence ("several signals agree").
    public var minimumScore = 2.0
    /// ...and must lead the runner-up by at least this much.
    public var minimumMargin = 0.75
    /// Less evidence than that, but this much, leading by the same margin, is a lean.
    public var leanScore = 1.5

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

        guard shippedCategories.contains(best.key) else {
            return Classification(category: .other, confidence: min(0.5, best.value / 4), signals: signals)
        }
        let confident = best.value >= minimumScore && distinctSignals >= 2 && margin >= minimumMargin
        if confident {
            let confidence = min(0.99, 0.55 + 0.12 * best.value + 0.08 * margin)
            return Classification(category: best.key, confidence: confidence, signals: signals)
        }
        // Not sure, but leaning one way: better sorted (or filed) by its best guess than left as
        // Other. Kept under the display bar, so a guess never reaches the widget.
        if best.value >= leanScore, margin >= minimumMargin {
            let confidence = min(0.7, 0.35 + 0.1 * best.value)
            return Classification(category: best.key, confidence: confidence, signals: signals)
        }
        return Classification(category: .other, confidence: min(0.5, best.value / 4), signals: signals)
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

        // Watch, listen, read and travel: the services and words of each, and more weight when
        // several turn up together.
        func words(_ category: ItemCategory, _ list: [String], strong: [String], name: String) {
            let hits = list.filter { body.contains($0) }.count
            if hits > 0 { signals.append(Signal(category, "\(name) words", 1)) }
            if hits >= 3 { signals.append(Signal(category, "many \(name) words", 0.75)) }
            if has(strong) { signals.append(Signal(category, "\(name) service", 0.5)) }
        }
        words(.watch, Words.watch, strong: Words.watchStrong, name: "film or show")
        if body.range(of: Patterns.episode, options: .regularExpression) != nil {
            signals.append(Signal(.watch, "season and episode", 1))
        }
        words(.listen, Words.listen, strong: Words.listenStrong, name: "music or podcast")
        words(.read, Words.read, strong: Words.readStrong, name: "book or article")
        words(.travel, Words.travel, strong: Words.travelStrong, name: "trip")

        // Message: a chat's timestamps and bubbles, messaging words, or an email's headers.
        if chatTimestampCount(text) >= 3 { signals.append(Signal(.message, "chat timestamps", 1)) }
        if has(Words.chat) { signals.append(Signal(.message, "messaging words", 1)) }
        if hasChatBubbles(text) { signals.append(Signal(.message, "chat bubbles", 1)) }
        if Words.email.filter({ body.contains($0) }).count >= 2 { signals.append(Signal(.message, "email headers", 1.5)) }

        // Post: a social feed's words, handles and hashtags.
        if has(Words.social) { signals.append(Signal(.post, "social words", 1)) }
        if has(Words.socialStrong) { signals.append(Signal(.post, "likes and reposts", 0.5)) }
        if matches(Patterns.handle, in: text.fullText) >= 1 { signals.append(Signal(.post, "handle", 0.5)) }
        if matches(Patterns.hashtag, in: text.fullText) >= 2 { signals.append(Signal(.post, "hashtags", 0.5)) }

        // Reference: codes, boarding passes, wifi and passwords, receipts.
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

    /// Short lines hugging the left edge and others hugging the right: two sides of a chat.
    static func hasChatBubbles(_ text: RecognizedText) -> Bool {
        let content = text.lines.filter { $0.box.minY < 0.9 && $0.box.width < 0.7 }
        let left = content.filter { $0.box.minX < 0.12 && $0.box.maxX < 0.75 }.count
        let right = content.filter { $0.box.minX > 0.3 && $0.box.maxX > 0.88 }.count
        return left >= 2 && right >= 2
    }

    static func matches(_ pattern: String, in text: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
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
        /// "S2 E5", "season 3", "episode 4".
        static let episode = #"\bs\d{1,2}\s?e\d{1,2}\b|\bseason \d|\bepisode \d"#
        /// "@someone", not the middle of an email address.
        static let handle = #"(?<![\w.])@[A-Za-z0-9_.]{3,}"#
        static let hashtag = #"(?<![\w&])#[A-Za-z][A-Za-z0-9_]{2,}"#
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
        static let chat = ["imessage", "text message", "delivered", "typing…", "typing...", "last seen", "active now",
                           "whatsapp", "messenger", "sent you", "replied to you", "reacted", "voice message", "seen by",
                           "group chat", "message…", "message..."]
        static let email = ["inbox", "reply all", "from:", "to:", "subject:", "cc:", "forward", "sent from my iphone"]
        static let social = ["retweet", "reposts", "repost", "likes", "liked by", "followers", "following",
                             "view all", "comments", "replies", "for you", "reels", "tiktok", "instagram", "threads",
                             "twitter", "reddit", "upvote", "subreddit", "posted by", "trending"]
        static let socialStrong = ["liked by", "retweets", "reposts", "quote tweet", "upvote", "view all comments", "followers"]
        static let watch = ["netflix", "prime video", "disney+", "binge", "hbo", "apple tv", "paramount+",
                            "trailer", "imdb", "rotten tomatoes", "letterboxd", "watchlist", "in cinemas", "now showing",
                            "directed by", "starring", "watch now", "streaming", "youtube", "runtime", "seasons", "episodes"]
        static let watchStrong = ["watch now", "watchlist", "in cinemas", "now showing", "imdb", "letterboxd", "rotten tomatoes"]
        static let listen = ["spotify", "apple music", "soundcloud", "album", "playlist", "podcast", "tracks", "shazam",
                             "song", "monthly listeners", "lyrics", "listen", "bandcamp", "tidal", "new release"]
        static let listenStrong = ["monthly listeners", "add to playlist", "listen on", "shazam", "spotify", "apple music", "podcast"]
        static let read = ["goodreads", "kindle", "paperback", "hardcover", "author", "chapter", "isbn", "min read",
                           "novel", "bestseller", "booktopia", "substack", "newsletter", "article", "audiobook",
                           "want to read", "books", "fiction", "memoir"]
        static let readStrong = ["min read", "isbn", "goodreads", "want to read", "paperback", "hardcover"]
        static let travel = ["flights", "flight", "one way", "round trip", "per night", "airbnb", "booking.com",
                             "hotel", "resort", "check-out", "skyscanner", "expedia", "itinerary", "jetstar", "qantas",
                             "virgin australia", "hostel", "superhost", "getaway", "holiday"]
        static let travelStrong = ["per night", "round trip", "one way", "skyscanner", "airbnb", "booking.com", "superhost"]
        static let boarding = ["boarding pass", "boarding group", "gate ", "seat ", "departure gate"]
        static let wifi = ["wi-fi", "wifi", "ssid", "network name", "wpa"]
        static let receipt = ["subtotal", "total", "gst", "tax invoice", "receipt", "order #", "order number",
                              "paid", "invoice", "amount due", "card ending"]
        static let foodLabels = ["food", "dish", "meal", "dessert", "baked", "cake", "pizza", "salad", "soup", "pasta"]
        static let productLabels = ["clothing", "shoe", "sneaker", "bag", "handbag", "watch", "jewelry", "furniture", "dress"]
        static let placeLabels = ["restaurant", "cafe", "interior_room", "building", "beach", "mountain", "landscape", "hotel"]
        static let eventLabels = ["concert", "stage", "performance", "crowd", "festival"]
    }
}
