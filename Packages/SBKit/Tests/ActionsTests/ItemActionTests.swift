import Core
import Foundation
import Testing
@testable import Actions
@testable import Store

@Suite struct ItemActionTests {
    private func item(
        _ category: ItemCategory,
        entities: [DetectedEntity] = [],
        text: String? = nil,
        dueDate: Date? = nil,
        sensitive: Bool = false
    ) -> ScreenshotItem {
        ScreenshotItem(
            assetLocalID: UUID().uuidString,
            createdAt: Date(timeIntervalSince1970: 0),
            category: category,
            confidence: 0.9,
            entities: entities,
            hasSensitiveText: sensitive,
            extractedText: text,
            title: "Saved thing",
            dueDate: dueDate
        )
    }

    @Test func eventsLeadWithTheCalendar() {
        let gig = item(.event, dueDate: Date(timeIntervalSince1970: 1_000_000))
        #expect(ItemAction.available(for: gig) == [.calendar, .send])
        #expect(ItemAction.suggested(for: gig) == .calendar)
    }

    @Test func placesLeadWithMaps() {
        let place = item(.place, entities: [DetectedEntity(kind: .address, text: "12 King St, Newtown")])
        #expect(ItemAction.available(for: place).first == .maps)
        #expect(MapsQuery.query(for: place) == "12 King St, Newtown")
    }

    @Test func productsOpenTheirLinkOrASearch() throws {
        let link = try #require(URL(string: "https://shop.example/sneakers"))
        let withLink = item(.product, entities: [DetectedEntity(kind: .link, text: "shop.example/sneakers", url: link)])
        #expect(ShopLink.url(for: withLink) == link)
        let withoutLink = item(.product)
        #expect(ShopLink.url(for: withoutLink)?.host == "www.google.com")
        #expect(ItemAction.suggested(for: withoutLink) == .shop)
    }

    @Test func recipesCopyOnlyIngredientLines() {
        let text = """
        Crispy chilli noodles
        200g wide rice noodles
        2 tbsp chilli crisp
        ½ cup peanuts
        a pinch of salt
        Method
        Boil the noodles for 4 minutes.
        """
        #expect(Ingredients.lines(in: text) == ["200g wide rice noodles", "2 tbsp chilli crisp", "½ cup peanuts", "a pinch of salt"])
        #expect(ItemAction.available(for: item(.recipe, text: text)).first == .ingredients)
    }

    @Test func sensitiveItemsCantBeSent() {
        #expect(!ItemAction.available(for: item(.other, sensitive: true)).contains(.send))
    }

    @Test func eventDraftsNeedADate() {
        #expect(EventDraft(item: item(.event)) == nil)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let draft = EventDraft(item: item(.event, dueDate: start))
        #expect(draft?.end == start.addingTimeInterval(EventDraft.defaultDuration))
    }
}
