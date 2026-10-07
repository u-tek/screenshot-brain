import Core
import Foundation
import Testing
@testable import Store
@testable import WidgetCore

@Suite struct WidgetPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let score = Score(done: 2, total: 9)

    private func item(_ title: String, state: ItemState = .stillWant, daysAgo: Double = 3, expiresIn: Double? = nil) -> ScreenshotItem {
        ScreenshotItem(
            assetLocalID: title,
            createdAt: now.addingTimeInterval(-daysAgo * 86_400),
            category: .place,
            confidence: 0.95,
            state: state,
            expiresAt: expiresIn.map { now.addingTimeInterval($0 * 86_400) },
            isSafeToDisplay: true,
            thumbnailPath: "\(title).jpg",
            stateChangedAt: now.addingTimeInterval(-daysAgo * 86_400),
            title: title,
            processedAt: now
        )
    }

    @Test func rotatesOneItemAnHour() {
        let plan = WidgetPlanner.plan(candidates: [item("a"), item("b"), item("c")], keptCount: 5, waitingCount: 0, score: score, access: .unlocked, now: now)
        #expect(plan.entries.map(\.date) == [now, now.addingTimeInterval(3_600), now.addingTimeInterval(7_200)])
        #expect(plan.reloadAt == now.addingTimeInterval(3 * 3_600))
    }

    @Test func nudgesForMoreWhenLittleIsKept() {
        let plan = WidgetPlanner.plan(candidates: [item("a")], keptCount: 1, waitingCount: 0, score: score, access: .unlocked, now: now)
        #expect(plan.entries.last?.card == .screenshotSomething)
        let empty = WidgetPlanner.plan(candidates: [], keptCount: 0, waitingCount: 0, score: score, access: .unlocked, now: now)
        #expect(empty.entries.map(\.card) == [.screenshotSomething])
    }

    @Test func allCaughtUpPointsAtTheRecap() {
        let plan = WidgetPlanner.plan(candidates: [], keptCount: 8, waitingCount: 4, score: score, access: .unlocked, now: now)
        #expect(plan.entries.map(\.card) == [.caughtUp(waiting: 4)])
    }

    @Test func lockedAfterTheTrial() {
        let plan = WidgetPlanner.plan(candidates: [item("a")], keptCount: 8, waitingCount: 0, score: score, access: .locked, now: now)
        #expect(plan.entries.map(\.card) == [.locked])
        let defaults = UserDefaults(suiteName: "widget-tests-\(UUID().uuidString)")
        #expect(WidgetAccess.current(defaults: defaults) == .unlocked)
        Entitlement.setPremium(false, defaults: defaults)
        #expect(WidgetAccess.current(defaults: defaults) == .locked)
        Entitlement.setPremium(true, defaults: defaults)
        #expect(WidgetAccess.current(defaults: defaults) == .unlocked)
    }

    @Test func nothingShowsTwiceInADay() throws {
        let database = try AppDatabase.inMemory()
        // Oldest untouched first: a, then b, then c.
        try database.save([item("a", daysAgo: 5), item("b", daysAgo: 4), item("c", daysAgo: 3)])
        let defaults = UserDefaults(suiteName: "widget-tests-\(UUID().uuidString)")
        let timeline = WidgetTimeline(database: database, defaults: defaults)

        let first = timeline.build(access: .unlocked, now: now)
        #expect(first.entries.count == 3)
        // An hour later the first two have been on screen; a reload shows only the third.
        let later = timeline.build(access: .unlocked, now: now.addingTimeInterval(3_600 + 60))
        let shown = later.entries.compactMap { entry -> String? in
            if case .item(let item) = entry.card { return item.title }
            return nil
        }
        #expect(shown == ["c"])
    }

    @Test func unreviewedFirstThenSoonestExpiring() throws {
        let database = try AppDatabase.inMemory()
        try database.save([
            item("kept-later", expiresIn: 20),
            item("kept-soon", expiresIn: 2),
            item("new", state: .unreviewed),
        ])
        let candidates = try database.widgetCandidates(now: now)
        #expect(candidates.map(\.title) == ["new", "kept-soon", "kept-later"])
    }

    @Test func describesDatesPlainly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var dated = item("gig")
        dated.dueDate = now.addingTimeInterval(86_400)
        #expect(WidgetItem.detail(for: dated, now: now, calendar: calendar) == "Tomorrow")
        #expect(WidgetItem.detail(for: item("old", daysAgo: 21), now: now, calendar: calendar) == "Saved 3 weeks ago")
    }
}
