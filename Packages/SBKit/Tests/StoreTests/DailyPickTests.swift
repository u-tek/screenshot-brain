import Core
import Foundation
import Testing
@testable import Store

@Suite struct DailyPickTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// 2026-10-15 is a Thursday.
    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func item(
        _ title: String?,
        category: ItemCategory,
        state: ItemState = .stillWant,
        keptDaysAgo: Int = 1,
        due: Date? = nil,
        text: String? = nil,
        now: Date
    ) -> ScreenshotItem {
        var item = ScreenshotItem(
            assetLocalID: UUID().uuidString,
            createdAt: now.addingTimeInterval(-Double(keptDaysAgo) * 86_400),
            category: category,
            state: state,
            extractedText: text,
            title: title,
            dueDate: due
        )
        item.stateChangedAt = item.createdAt
        return item
    }

    @Test func nothingKeptMeansNoPick() {
        let now = date(13)
        #expect(DailyPick.pick(from: [], now: now, calendar: calendar) == nil)
        let untitled = item(nil, category: .place, now: now)
        let done = item("Ramen Ikkyu", category: .place, state: .done, now: now)
        #expect(DailyPick.pick(from: [untitled, done], now: now, calendar: calendar) == nil)
    }

    @Test func sameAllDay() {
        let morning = date(13, 9)
        let items = (0..<8).map { item("Place \($0)", category: .place, keptDaysAgo: $0 + 1, now: morning) }
        let first = DailyPick.pick(from: items, now: morning, calendar: calendar)
        let later = DailyPick.pick(from: items, now: morning.addingTimeInterval(3_600), calendar: calendar)
        #expect(first?.item.id == later?.item.id)
    }

    @Test func rerollGivesAnother() {
        let now = date(13)
        let items = (0..<4).map { item("Place \($0)", category: .place, keptDaysAgo: $0 + 1, now: now) }
        let first = DailyPick.pick(from: items, now: now, calendar: calendar)
        let second = DailyPick.pick(from: items, now: now, calendar: calendar, reroll: 1)
        #expect(first?.item.id != second?.item.id)
    }

    @Test func aRecipeOnAWeekdayEvening() {
        let now = date(13, 19)
        let recipe = item("Miso aubergine", category: .recipe, now: now)
        let pick = DailyPick.pick(from: [recipe], now: now, calendar: calendar)
        #expect(pick?.reason == "Something to cook tonight.")
    }

    @Test func aDateBeatsEverything() {
        let now = date(13, 19)
        let gig = item("Fontaines D.C.", category: .event, due: date(16, 20), now: now)
        let recipe = item("Miso aubergine", category: .recipe, now: now)
        let pick = DailyPick.pick(from: [recipe, gig], now: now, calendar: calendar)
        #expect(pick?.item.id == gig.id)
        #expect(pick?.reason == "It's on Friday.")
    }

    @Test func pastDatesAreSkipped() {
        let now = date(13)
        let gone = item("Last week's gig", category: .event, due: date(10), now: now)
        #expect(DailyPick.pick(from: [gone], now: now, calendar: calendar) == nil)
    }

    @Test func theSeasonWhenTheThingNamesIt() {
        let now = date(13, 10)
        let walk = item("Cosy pub walk", category: .place, now: now)
        #expect(DailyPick.pick(from: [walk], now: now, calendar: calendar)?.reason == "Made for autumn.")
    }

    @Test func keptAWhile() {
        let now = date(13, 10)
        let old = item("Salomon XT-6", category: .product, keptDaysAgo: 40, now: now)
        #expect(DailyPick.pick(from: [old], now: now, calendar: calendar)?.reason == "Kept since September. Still want it?")
    }

    // MARK: - Weekend plan

    @Test func weekendWindow() {
        #expect(!WeekendPlan.isOn(date(15, 12), calendar: calendar))
        #expect(WeekendPlan.isOn(date(15, 18), calendar: calendar))
        #expect(WeekendPlan.isOn(date(17), calendar: calendar))
        #expect(WeekendPlan.isOn(date(18, 22), calendar: calendar))
        #expect(!WeekendPlan.isOn(date(19), calendar: calendar))
    }

    @Test func datedThingsFirstThenOutings() {
        let now = date(15, 18)
        let gig = item("Fontaines D.C.", category: .event, due: date(17, 20), now: now)
        let nextWeek = item("Next week's gig", category: .event, due: date(22, 20), now: now)
        let ramen = item("Ramen Ikkyu", category: .place, keptDaysAgo: 30, now: now)
        let gallery = item("Tate Modern late", category: .place, keptDaysAgo: 5, now: now)
        let recipe = item("Miso aubergine", category: .recipe, now: now)
        let plan = WeekendPlan.pick(from: [recipe, gallery, ramen, nextWeek, gig], now: now, calendar: calendar)
        #expect(plan.map(\.title) == ["Fontaines D.C.", "Ramen Ikkyu", "Tate Modern late"])
    }

    @Test func oneThingIsNoPlan() {
        let now = date(15, 18)
        let ramen = item("Ramen Ikkyu", category: .place, now: now)
        #expect(WeekendPlan.pick(from: [ramen], now: now, calendar: calendar).isEmpty)
    }

    @Test func aSwapKeepsTheDatedThing() {
        let now = date(15, 18)
        let gig = item("Fontaines D.C.", category: .event, due: date(17, 20), now: now)
        let places = (0..<5).map { item("Place \($0)", category: .place, keptDaysAgo: 30 - $0, now: now) }
        let first = WeekendPlan.pick(from: [gig] + places, now: now, calendar: calendar)
        let swapped = WeekendPlan.pick(from: [gig] + places, now: now, calendar: calendar, reroll: 1)
        #expect(first.first?.id == gig.id)
        #expect(swapped.first?.id == gig.id)
        #expect(first != swapped)
    }
}
