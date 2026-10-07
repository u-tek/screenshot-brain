import Core
import Foundation
import Testing
@testable import Reveal
@testable import Store

@Suite struct RevealBuilderTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }()

    private func date(day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func summary(_ date: Date, _ category: ItemCategory = .other, confidence: Double = 0, nsfw: Bool = false, hasDate: Bool = false, state: ItemState = .unreviewed) -> ItemSummary {
        ItemSummary(
            id: UUID().uuidString,
            createdAt: date,
            category: category,
            confidence: confidence,
            state: state,
            isSafeToDisplay: false,
            isNSFWFlagged: nsfw,
            hasDate: hasDate,
            processedAt: date
        )
    }

    @Test func findsThePeakTenMinutesInsideThePeakHour() {
        let summaries = [
            summary(date(day: 1, hour: 0, minute: 41)),
            summary(date(day: 2, hour: 0, minute: 44)),
            summary(date(day: 3, hour: 0, minute: 12)),
            summary(date(day: 4, hour: 14, minute: 5)),
        ]
        let story = RevealBuilder.build(summaries: summaries, answers: nil, isLimited: false, start: .distantPast, end: .now, calendar: calendar)
        #expect(story.peakMinute == 40)
        #expect(story.peakTimeText == "12:40am")
        #expect(story.hourCounts[0] == 3)
    }

    @Test func findsTheBusiestDay() {
        let summaries = [
            summary(date(day: 1, hour: 9, minute: 0)),
            summary(date(day: 3, hour: 9, minute: 0)),
            summary(date(day: 3, hour: 13, minute: 0)),
            summary(date(day: 3, hour: 22, minute: 0)),
        ]
        let story = RevealBuilder.build(summaries: summaries, answers: nil, isLimited: false, start: .distantPast, end: .now, calendar: calendar)
        #expect(story.busiestDayCount == 3)
        #expect(story.busiestDay == calendar.startOfDay(for: date(day: 3, hour: 0, minute: 0)))
    }

    @Test func onlyConfidentCategoriesAreClaimed() {
        let when = date(day: 1, hour: 9, minute: 0)
        let summaries = [
            summary(when, .place, confidence: 0.9),
            summary(when, .place, confidence: 0.95),
            summary(when, .product, confidence: 0.85),
            summary(when, .product, confidence: 0.5),
            summary(when, .other, confidence: 0.3),
            summary(when, .event, confidence: 0.99, nsfw: true),
        ]
        let story = RevealBuilder.build(summaries: summaries, answers: nil, isLimited: false, start: .distantPast, end: .now, calendar: calendar)
        #expect(story.categories.map(\.category) == [.place, .product])
        #expect(story.categories.map(\.count) == [2, 1])
        #expect(story.unsureCount == 2)
        #expect(story.topCategory == .place)
        // Facts count everything, including what's never shown.
        #expect(story.total == 6)
    }

    @Test func countsDatesAndDone() {
        let when = date(day: 1, hour: 9, minute: 0)
        let summaries = [
            summary(when, hasDate: true),
            summary(when, hasDate: true, state: .done),
            summary(when),
        ]
        let story = RevealBuilder.build(summaries: summaries, answers: nil, isLimited: false, start: .distantPast, end: .now, calendar: calendar)
        #expect(story.datedCount == 2)
        #expect(story.doneCount == 1)
    }

    @Test func skipsCardsWithoutData() {
        let story = RevealBuilder.build(summaries: [], answers: nil, isLimited: true, start: .distantPast, end: .now, calendar: calendar)
        #expect(RevealCard.cards(for: story) == [.total, .share])
        #expect(RevealCard.cards(for: .sample).count == RevealCard.allCases.count)
    }

    @Test func theFreeMonthlyRevealIsShort() {
        var story = RevealStory.sample
        story.isShort = true
        #expect(RevealCard.cards(for: story) == [.total, .categories, .share])
    }

    @Test func lastMonthCoversTheWholeMonth() {
        let now = date(day: 14, hour: 9, minute: 0)
        let period = RevealPeriod.lastMonth(now: now, calendar: calendar)
        let range = period.range(now: now, calendar: calendar)
        #expect(calendar.component(.month, from: range.start) == 8)
        #expect(calendar.component(.day, from: range.start) == 1)
        #expect(range.end == calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!)
        #expect(period.label(calendar: calendar, now: now) == "In August")
    }
}
