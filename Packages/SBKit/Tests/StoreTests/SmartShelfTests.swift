import Core
import Foundation
import Testing
@testable import Store

@Suite struct SmartShelfTests {
    private func item(
        _ title: String? = nil,
        text: String? = nil,
        category: ItemCategory = .other,
        state: ItemState = .stillWant,
        dueDate: Date? = nil
    ) -> ScreenshotItem {
        ScreenshotItem(
            assetLocalID: UUID().uuidString,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            category: category,
            state: state,
            extractedText: text,
            title: title,
            dueDate: dueDate
        )
    }

    private func on(_ shelf: SmartShelf, _ item: ScreenshotItem) -> Bool {
        SmartShelf.shelves(for: item).contains(shelf)
    }

    // MARK: - Free

    @Test func freeEntryAdmissionAndTicketsAreFree() {
        #expect(on(.free, item(text: "Night market this Saturday. Free entry")))
        #expect(on(.free, item(text: "Admission: free for everyone")))
        #expect(on(.free, item(text: "Free tickets while they last")))
        #expect(on(.free, item(text: "Free community event in the park")))
        #expect(on(.free, item(text: "Entry $0")))
    }

    @Test func freeShippingIsNotFree() {
        #expect(!on(.free, item(text: "Free shipping on orders over $50")))
        #expect(!on(.free, item(text: "Tickets $45, admission at the door")))
        #expect(!on(.free, item(text: "Carefree weekend, entry $30")))
    }

    // MARK: - Date night

    @Test func aPlaceOrEventWithDateNightWordsIsDateNight() {
        #expect(on(.dateNight, item(text: "Rooftop cocktails and jazz", category: .place)))
        #expect(on(.dateNight, item(text: "Omakase tasting menu", category: .event)))
        #expect(on(.dateNight, item("Candlelit dinner at Bistro 21", category: .place)))
    }

    @Test func dateNightWordsOnTheWrongKindOfThingDoNotCount() {
        #expect(!on(.dateNight, item(text: "Wine glasses 6 pack", category: .product)))
        #expect(!on(.dateNight, item(text: "Barbecue at the park", category: .place)))
        #expect(!on(.dateNight, item(text: "Brunch and coffee", category: .place)))
    }

    // MARK: - Rainy day

    @Test func watchReadListenAndRecipesAreRainyDay() {
        #expect(on(.rainyDay, item("A film", category: .watch)))
        #expect(on(.rainyDay, item("A podcast", category: .listen)))
        #expect(on(.rainyDay, item("An article", category: .read)))
        #expect(on(.rainyDay, item("Banana bread", category: .recipe)))
    }

    @Test func indoorPlacesAreRainyDayWhateverTheirCategory() {
        #expect(on(.rainyDay, item(text: "New exhibition at the gallery", category: .event)))
        #expect(on(.rainyDay, item(text: "Museum open daily", category: .place)))
        #expect(on(.rainyDay, item(text: "Independent bookshop, Newtown", category: .place)))
        #expect(!on(.rainyDay, item(text: "Rooftop bar", category: .place)))
        #expect(!on(.rainyDay, item(text: "Trainers on sale", category: .product)))
    }

    // MARK: - Under 20

    @Test func pricesAtOrUnderTwentyAreCheap() {
        #expect(on(.cheap, item(text: "Burger $12")))
        #expect(on(.cheap, item(text: "Entry £8.50")))
        #expect(on(.cheap, item(text: "Lunch 12€")))
        #expect(on(.cheap, item(text: "Set menu $20")))
    }

    @Test func dearOrUnpricedThingsAreNotCheap() {
        #expect(!on(.cheap, item(text: "Tasting menu $85")))
        #expect(!on(.cheap, item(text: "Weekend away £1,200")))
        #expect(!on(.cheap, item(text: "Total 1,200€")))
        #expect(!on(.cheap, item(text: "Set menu $20.50")))
        #expect(!on(.cheap, item(text: "Opens at 12 daily, 5 stars")))
    }

    // MARK: - With friends

    @Test func groupThingsAreWithFriends() {
        #expect(on(.withFriends, item(text: "Trivia night every Tuesday")))
        #expect(on(.withFriends, item(text: "Karaoke room, bowling after")))
        #expect(on(.withFriends, item(text: "Sharing plates for the table")))
        #expect(on(.withFriends, item(text: "Book a table for 4")))
        #expect(on(.withFriends, item(text: "Booking for 6 people")))
        #expect(on(.withFriends, item(text: "Groups welcome")))
        #expect(on(.withFriends, item(text: "Splendour festival lineup")))
    }

    @Test func soloThingsAreNotWithFriends() {
        #expect(!on(.withFriends, item(text: "Table for 2 at 7pm")))
        #expect(!on(.withFriends, item(text: "Doors open for 4pm start")))
        #expect(!on(.withFriends, item(text: "Quiet coffee")))
    }

    // MARK: - Late night

    @Test func lateWordsAreLateNight() {
        #expect(on(.lateNight, item(text: "Open late on Fridays")))
        #expect(on(.lateNight, item(text: "Music until midnight")))
        #expect(on(.lateNight, item(text: "Kitchen open till 2am")))
        #expect(on(.lateNight, item(text: "Late-night ramen")))
        #expect(on(.lateNight, item(text: "Cocktails after dark")))
    }

    @Test func morningHoursAreNotLateNight() {
        #expect(!on(.lateNight, item(text: "Open until 10am")))
        #expect(!on(.lateNight, item(text: "Brunch from 8am")))
    }

    @Test func aTimeAtOrAfterNineInTheEveningIsLateNight() throws {
        let calendar = Calendar.current
        let late = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 21, minute: 0)))
        let early = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 20, minute: 59)))
        #expect(on(.lateNight, item("Gig", category: .event, dueDate: late)))
        #expect(!on(.lateNight, item("Gig", category: .event, dueDate: early)))
    }

    // MARK: - Grouping

    @Test func anItemCanSitOnSeveralShelvesInFixedOrder() {
        let both = item("Gig", text: "Free entry, open late", category: .event)
        #expect(SmartShelf.shelves(for: both) == [.free, .lateNight])
    }

    @Test func groupingDropsEmptyShelvesAndKeepsTheFixedOrder() {
        let late = item(text: "Open late")
        let free = item(text: "Free entry")
        let both = item(text: "Free admission, open late")
        let groups = SmartShelf.group([late, free, both])
        #expect(groups.map { $0.0 } == [.free, .lateNight])
        #expect(groups[0].1.map { $0.id } == [free.id, both.id])
        #expect(groups[1].1.map { $0.id } == [late.id, both.id])
    }

    @Test func groupingLeavesOutItemsThatAreNotStillWanted() {
        let done = item(text: "Free entry", state: .done)
        #expect(SmartShelf.group([done]).isEmpty)
        #expect(SmartShelf.group([]).isEmpty)
    }

    @Test func shelfTitlesAreFixed() {
        #expect(SmartShelf.allCases.map { $0.title } == ["Free", "Date night", "Rainy day", "Under 20", "With friends", "Late night"])
    }
}
