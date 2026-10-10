import Core
import Foundation
import Testing
@testable import ScanEngine
import Safety

/// Builds recognised text from lines, top to bottom, the way Vision reports them.
func screenshot(_ lines: [String], codes: Int = 0, labels: [String] = []) -> RecognizedText {
    let height = 0.8 / Double(max(lines.count, 1))
    let textLines = lines.enumerated().map { index, text in
        TextLine(text: text, box: CGRect(x: 0.05, y: 0.9 - Double(index + 1) * height, width: 0.8, height: height * 0.6))
    }
    return RecognizedText(lines: textLines, codeCount: codes, imageLabels: labels)
}

func classify(_ text: RecognizedText) -> Classification {
    let entities = EntityDetector().entities(in: text.fullText)
    let sensitive = SensitiveTextDetector.findings(in: text.fullText)
    return CategoryClassifier().classify(text, entities: entities, hasSensitiveText: !sensitive.isEmpty)
}

/// One fixture per category: the text Vision reads from a typical screenshot of each.
enum Fixtures {
    static let gig = screenshot([
        "Fri 14 Nov",
        "Middle Kids",
        "Enmore Theatre, Newtown",
        "Doors open 7pm",
        "Get tickets",
        "Ticketek",
    ])
    static let bar = screenshot([
        "Bar Sazerac",
        "4.6 ★★★★★ (1,284 reviews)",
        "Cocktail bar · $$",
        "Open · Closes 1 am",
        "Directions",
        "Call",
    ])
    static let sneakers = screenshot([
        "Air Max 90",
        "$189.99",
        "Select size",
        "Add to Bag",
        "Free delivery on orders over $150",
        "Afterpay available",
    ])
    static let pasta = screenshot([
        "Lemon pasta",
        "Serves 4 · Prep time 10 min",
        "Ingredients",
        "400 g spaghetti",
        "2 tbsp olive oil",
        "3 cloves garlic",
        "1 cup parmesan",
        "Method",
        "Boil the pasta, then stir through the lemon.",
    ])
    static let chat = screenshot([
        "Mum",
        "iMessage",
        "can you grab milk",
        "9:14",
        "sure",
        "9:20",
        "thanks love",
        "9:21",
        "Delivered",
    ])
    static let boardingPass = screenshot([
        "Boarding pass",
        "SYD → MEL",
        "Flight QF 401",
        "Gate 12",
        "Seat 23A",
    ], codes: 1)
    static let wifi = screenshot([
        "Cafe Guest Wi-Fi",
        "Network name: CafeGuest",
        "Password: flatwhite2024",
    ])
    static let tweet = screenshot([
        "Dan",
        "@danwrites",
        "the best part of any drive is the 2am servo pie",
        "1,204 Reposts 89 Quotes 12.3K Likes",
        "#roadtrip #pies",
    ])
    static let show = screenshot([
        "Netflix",
        "Severance",
        "Season 2",
        "10 Episodes",
        "Watch Now",
        "Starring Adam Scott",
    ])
    static let artist = screenshot([
        "Spotify",
        "Mallrat",
        "2.1M monthly listeners",
        "Butterfly Blue · Album",
        "Follow",
    ])
    static let book = screenshot([
        "Goodreads",
        "The Secret History",
        "by Donna Tartt",
        "Want to Read",
        "Hardcover, 559 pages",
    ])
    static let stay = screenshot([
        "Airbnb",
        "Cabin near Byron Bay",
        "Superhost",
        "$240 per night",
        "Check availability",
    ])
    static let email = screenshot([
        "Inbox",
        "From: Jess",
        "To: me",
        "Subject: Lunch plans",
        "see you at the beach",
    ])
    static let meme = screenshot([
        "me pretending to be fine",
        "lol",
    ])
}

@Suite struct ClassifierTests {
    @Test func gigIsAnEvent() {
        let result = classify(Fixtures.gig)
        #expect(result.category == .event, "signals: \(result.signals.map(\.name))")
        #expect(result.confidence >= 0.8)
    }

    @Test func barIsAPlace() {
        let result = classify(Fixtures.bar)
        #expect(result.category == .place, "signals: \(result.signals.map(\.name))")
    }

    @Test func sneakersAreAProduct() {
        let result = classify(Fixtures.sneakers)
        #expect(result.category == .product, "signals: \(result.signals.map(\.name))")
    }

    @Test func pastaIsARecipe() {
        let result = classify(Fixtures.pasta)
        #expect(result.category == .recipe, "signals: \(result.signals.map(\.name))")
    }

    @Test func chatIsAMessage() {
        let result = classify(Fixtures.chat)
        #expect(result.category == .message, "signals: \(result.signals.map(\.name))")
        #expect(!result.category.isActionable)
    }

    @Test func emailIsAMessage() {
        let result = classify(Fixtures.email)
        #expect(result.category == .message, "signals: \(result.signals.map(\.name))")
    }

    @Test func tweetIsAPost() {
        let result = classify(Fixtures.tweet)
        #expect(result.category == .post, "signals: \(result.signals.map(\.name))")
    }

    @Test func showIsToWatch() {
        let result = classify(Fixtures.show)
        #expect(result.category == .watch, "signals: \(result.signals.map(\.name))")
        #expect(result.confidence >= 0.8)
    }

    @Test func artistIsToListen() {
        let result = classify(Fixtures.artist)
        #expect(result.category == .listen, "signals: \(result.signals.map(\.name))")
    }

    @Test func bookIsToRead() {
        let result = classify(Fixtures.book)
        #expect(result.category == .read, "signals: \(result.signals.map(\.name))")
    }

    @Test func stayIsATrip() {
        let result = classify(Fixtures.stay)
        #expect(result.category == .travel, "signals: \(result.signals.map(\.name))")
    }

    @Test func aLeanIsAssignedBelowTheDisplayBar() {
        let result = classify(screenshot(["Spotify", "Butterfly Blue"]))
        #expect(result.category == .listen, "signals: \(result.signals.map(\.name))")
        #expect(result.confidence < 0.8)
    }

    @Test func boardingPassIsReference() {
        #expect(classify(Fixtures.boardingPass).category == .reference)
    }

    @Test func wifiDetailsAreReferenceBecauseTheyreSensitive() {
        #expect(classify(Fixtures.wifi).category == .reference)
    }

    @Test func uncertainScreenshotsAreOther() {
        let result = classify(Fixtures.meme)
        #expect(result.category == .other)
        #expect(result.confidence < 0.8)
    }

    @Test func oneSignalAloneIsNotEnough() {
        let result = classify(screenshot(["$20"]))
        #expect(result.category == .other)
    }

    @Test func categoriesNotYetShippedFallBackToOther() {
        var classifier = CategoryClassifier()
        classifier.shippedCategories = [.event, .place]
        let text = Fixtures.sneakers
        let entities = EntityDetector().entities(in: text.fullText)
        #expect(classifier.classify(text, entities: entities, hasSensitiveText: false).category == .other)
    }

    @Test func littleTextFallsBackToImageLabels() {
        let result = classify(screenshot(["Sat"], labels: ["concert", "stage", "crowd"]))
        #expect(result.signals.contains { $0.name == "looks like a gig" })
    }
}

@Suite struct EntityTests {
    @Test func readsPrices() {
        let entities = EntityDetector().entities(in: "Now $1,299.00, was A$1,499")
        let amounts = entities.filter { $0.kind == .price }.compactMap(\.amount)
        #expect(amounts.contains(Decimal(string: "1299.00")!))
        #expect(amounts.contains(1499))
    }

    @Test func readsEuropeanPrices() {
        #expect(EntityDetector.amount(in: "12,50 €") == Decimal(string: "12.50"))
        #expect(EntityDetector.amount(in: "1.299,00 €") == 1299)
        let entities = EntityDetector().entities(in: "Jetzt €12,50 statt €1.299,00")
        let amounts = entities.filter { $0.kind == .price }.compactMap(\.amount)
        #expect(amounts == [Decimal(string: "12.50")!, 1299])
    }

    @Test func readsCanadianDollars() {
        let price = EntityDetector().entities(in: "CA$1,299").first { $0.kind == .price }
        #expect(price?.text == "CA$1,299")
        #expect(price?.currencyCode == "CAD")
    }

    @Test func readsRatingsAndReviews() {
        let entities = EntityDetector().entities(in: "4.6 ★★★★★ (1,284 reviews)")
        #expect(entities.contains { $0.kind == .rating })
        #expect(entities.contains { $0.kind == .reviewCount })
        let shouted = EntityDetector().entities(in: "4.5 Stars · 1,284 Google Reviews")
        #expect(shouted.contains { $0.kind == .rating })
        #expect(shouted.contains { $0.kind == .reviewCount })
    }

    @Test func distinguishesDaysFromTimes() {
        #expect(DetectedEntity(kind: .date, text: "Fri 14 Nov").namesADay)
        #expect(DetectedEntity(kind: .date, text: "14/11/2026").namesADay)
        #expect(!DetectedEntity(kind: .date, text: "9:41").namesADay)
    }
}

@Suite struct ExpiryTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let captured = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func eventsExpireTheDayAfter() {
        let eventDate = captured.addingTimeInterval(5 * 86_400)
        let dates = ExpiryPolicy.dates(
            category: .event,
            entities: [DetectedEntity(kind: .date, text: "Fri 14 Nov", date: eventDate)],
            text: "",
            createdAt: captured,
            calendar: calendar
        )
        #expect(dates.dueDate == eventDate)
        let expected = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: eventDate))
        #expect(dates.expiresAt == expected)
    }

    @Test func productsExpireAfterThirtyDays() {
        let dates = ExpiryPolicy.dates(category: .product, entities: [], text: "", createdAt: captured, calendar: calendar)
        #expect(dates.expiresAt == calendar.date(byAdding: .day, value: 30, to: captured))
    }

    @Test func placesGetAStillWantPromptAfterSixtyDays() {
        let dates = ExpiryPolicy.dates(category: .place, entities: [], text: "", createdAt: captured, calendar: calendar)
        #expect(dates.reviewAt == calendar.date(byAdding: .day, value: 60, to: captured))
        #expect(dates.expiresAt == nil)
    }
}

@Suite struct GroupingTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func nearDuplicatesWithinAMinuteGroup() {
        let words: Set<String> = ["middle", "kids", "enmore", "theatre", "tickets"]
        let groups = Grouper.groups(for: [
            .init(id: "a", createdAt: start, words: words),
            .init(id: "b", createdAt: start.addingTimeInterval(30), words: words.union(["doors"])),
            .init(id: "c", createdAt: start.addingTimeInterval(400), words: words),
        ])
        #expect(groups["a"] != nil)
        #expect(groups["a"] == groups["b"])
        #expect(groups["c"] == nil)
    }

    @Test func differentScreenshotsTakenTogetherDontGroup() {
        let groups = Grouper.groups(for: [
            .init(id: "a", createdAt: start, words: ["pasta", "lemon", "garlic"]),
            .init(id: "b", createdAt: start.addingTimeInterval(10), words: ["sneakers", "size", "bag"]),
        ])
        #expect(groups.isEmpty)
    }
}

@Suite struct AnalysisTests {
    @Test func paletteMergesNearColours() {
        let merged = PaletteExtractor.merge([
            PaletteColor(red: 0.90, green: 0.30, blue: 0.20, weight: 0.5),
            PaletteColor(red: 0.92, green: 0.31, blue: 0.21, weight: 0.25),
            PaletteColor(red: 0.10, green: 0.10, blue: 0.60, weight: 0.25),
        ])
        #expect(merged.count == 2)
        #expect(abs(merged[0].weight - 0.75) < 0.0001)
    }

    @Test func titleIsTheMostProminentLine() {
        var text = screenshot(["9:41", "small caption", "Middle Kids", "details"])
        text.lines[2].box.size.height = 0.2
        #expect(TitleExtractor.title(from: text) == "Middle Kids")
    }
}
