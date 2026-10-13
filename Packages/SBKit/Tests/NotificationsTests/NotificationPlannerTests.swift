import Core
import Foundation
import Testing
@testable import Notifications

@Suite struct NotificationPlannerTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }()

    /// Wednesday 7 October 2026, 6pm in Sydney.
    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 18))!
    }

    private func context(
        now: Date,
        new: [NotableItem] = [],
        dated: [NotableItem] = [],
        weekSaved: Int = 0,
        weekDone: Int = 0,
        lastOpened: Date? = nil,
        trialEndsAt: Date? = nil,
        history: NotificationHistory = NotificationHistory(),
        kept: [NotableItem] = []
    ) -> NotificationContext {
        NotificationContext(
            now: now,
            recapMinutes: 21 * 60 + 30,
            newItems: new,
            datedItems: dated,
            weekSaved: weekSaved,
            weekDone: weekDone,
            lastOpenedAt: lastOpened ?? now,
            trialEndsAt: trialEndsAt,
            doneCount: 6,
            history: history,
            keptItems: kept
        )
    }

    private func kept(_ title: String?, _ category: ItemCategory = .place, daysAgo: Double, from date: Date, id: String? = nil) -> NotableItem {
        NotableItem(id: id ?? title ?? "kept", title: title, category: category, dueDate: nil, keptAt: date.addingTimeInterval(-daysAgo * 86_400))
    }

    private func gig(dueInDays days: Double, from date: Date, id: String = "gig") -> NotableItem {
        NotableItem(id: id, title: nil, category: .event, dueDate: date.addingTimeInterval(days * 86_400))
    }

    @Test func recapCopyIsSpecific() throws {
        let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 20))!
        let plan = try #require(NotificationPlanner.plan(context(now: start, new: [NotableItem(id: "a", title: nil, category: .event, dueDate: friday)]), calendar: calendar))
        #expect(plan.kind == .recap)
        #expect(plan.body == "That gig you saved is Friday. Still going?")
        #expect(calendar.component(.hour, from: plan.fireAt) == 21)
        #expect(calendar.component(.minute, from: plan.fireAt) == 30)
    }

    @Test func aGigThatHasBeenIsNotGivenADay() throws {
        let lastMonth = start.addingTimeInterval(-30 * 86_400)
        let plan = try #require(NotificationPlanner.plan(context(now: start, new: [NotableItem(id: "a", title: nil, category: .event, dueDate: lastMonth)]), calendar: calendar))
        #expect(plan.body == "That gig you saved. Going?")
    }

    @Test func recapNamesSomethingItHasNotNamedBefore() throws {
        var history = NotificationHistory()
        history.nudgedItemIDs = ["a"]
        let new = [
            NotableItem(id: "a", title: nil, category: .event, dueDate: nil),
            NotableItem(id: "b", title: nil, category: .place, dueDate: nil),
        ]
        let plan = try #require(NotificationPlanner.plan(context(now: start, new: new, history: history), calendar: calendar))
        #expect(plan.itemID == "b")
    }

    @Test func emptyNightsStayQuiet() {
        #expect(NotificationPlanner.plan(context(now: start), calendar: calendar) == nil)
    }

    @Test func nothingNewSendsOneExpiringThingInstead() throws {
        let plan = try #require(NotificationPlanner.plan(context(now: start, dated: [gig(dueInDays: 1.8, from: start)]), calendar: calendar))
        #expect(plan.kind == .expiry)
        var history = NotificationHistory()
        history.record(plan, calendar: calendar)
        // Never the same nudge twice.
        #expect(NotificationPlanner.plan(context(now: start, dated: [gig(dueInDays: 1.8, from: start)], history: history), calendar: calendar) == nil)
    }

    @Test func trialReminderOnDayFive() throws {
        let plan = try #require(NotificationPlanner.plan(context(now: start, trialEndsAt: start.addingTimeInterval(2 * 86_400 + 3_600)), calendar: calendar))
        #expect(plan.kind == .trialReminder)
        #expect(plan.body == "Your widget trial ends in 2 days. You've ticked off 6 things.")
    }

    @Test func winBackOnceThenSilence() throws {
        let awayWeek = start.addingTimeInterval(-8 * 86_400)
        // Nothing expiring: nothing at all, even with new screenshots.
        #expect(NotificationPlanner.plan(context(now: start, new: [gig(dueInDays: 9, from: start, id: "n")], lastOpened: awayWeek), calendar: calendar) == nil)
        let plan = try #require(NotificationPlanner.plan(context(now: start, dated: [gig(dueInDays: 1.5, from: start)], lastOpened: awayWeek), calendar: calendar))
        #expect(plan.kind == .winBack)
        var history = NotificationHistory()
        history.record(plan, calendar: calendar)
        let later = start.addingTimeInterval(86_400)
        #expect(NotificationPlanner.plan(context(now: later, dated: [gig(dueInDays: 1.5, from: later, id: "other")], lastOpened: awayWeek, history: history), calendar: calendar) == nil)
        // A month away: nothing, whatever's expiring.
        #expect(NotificationPlanner.plan(context(now: start, dated: [gig(dueInDays: 1, from: start)], lastOpened: start.addingTimeInterval(-31 * 86_400)), calendar: calendar) == nil)
    }

    @Test func winBackBringsBackSomethingKeptThenOnceMoreThenSilence() throws {
        let lastOpened = start.addingTimeInterval(-8 * 86_400)
        let list = [kept("Ramen Ikkyu", daysAgo: 30, from: start), kept("Salomon XT-6", .product, daysAgo: 20, from: start)]
        let first = try #require(NotificationPlanner.plan(context(now: start, lastOpened: lastOpened, kept: list), calendar: calendar))
        #expect(first.kind == .winBack)
        #expect(first.body == "Ramen Ikkyu is still on your list. This weekend?")
        var history = NotificationHistory()
        history.record(first, calendar: calendar)

        // Nothing more until three weeks away.
        let nextDay = start.addingTimeInterval(86_400)
        #expect(NotificationPlanner.plan(context(now: nextDay, lastOpened: lastOpened, history: history, kept: list), calendar: calendar) == nil)

        let threeWeeks = lastOpened.addingTimeInterval(21 * 86_400)
        let second = try #require(NotificationPlanner.plan(context(now: threeWeeks, lastOpened: lastOpened, history: history, kept: list), calendar: calendar))
        #expect(second.kind == .lateWinBack)
        #expect(second.body == "You've still got 2 things saved to do. Salomon XT-6 is one of them.")
        history.record(second, calendar: calendar)

        // Then silence, until they're back.
        let later = threeWeeks.addingTimeInterval(2 * 86_400)
        let more = list + [kept("Crispy chilli noodles", .recipe, daysAgo: 40, from: later)]
        #expect(NotificationPlanner.plan(context(now: later, lastOpened: lastOpened, history: history, kept: more), calendar: calendar) == nil)
    }

    @Test func quietNightBringsBackTheThingKeptLongest() throws {
        let list = [kept("Ramen Ikkyu", daysAgo: 21, from: start), kept("Salomon XT-6", .product, daysAgo: 10, from: start)]
        let plan = try #require(NotificationPlanner.plan(context(now: start, kept: list), calendar: calendar))
        #expect(plan.kind == .resurface)
        #expect(plan.body == "You kept Ramen Ikkyu 3 weeks ago. Actually going?")
        #expect(plan.link == "screenshotbrain://item/Ramen Ikkyu")
    }

    @Test func quietNightsResurfaceAtMostEveryThirdNight() throws {
        let list = [kept("Ramen Ikkyu", daysAgo: 21, from: start), kept("Salomon XT-6", .product, daysAgo: 10, from: start)]
        var history = NotificationHistory()
        let first = try #require(NotificationPlanner.plan(context(now: start, kept: list), calendar: calendar))
        history.record(first, calendar: calendar)
        for day in 1...2 {
            let now = start.addingTimeInterval(Double(day) * 86_400)
            #expect(NotificationPlanner.plan(context(now: now, history: history, kept: list), calendar: calendar) == nil)
        }
        let third = start.addingTimeInterval(3 * 86_400)
        let next = try #require(NotificationPlanner.plan(context(now: third, history: history, kept: list), calendar: calendar))
        // Never the same thing twice.
        #expect(next.body == "You kept Salomon XT-6 last week. Still want it?")
    }

    @Test func resurfacingWaitsAWeekAndGivesWayToAnythingNew() throws {
        #expect(NotificationPlanner.plan(context(now: start, kept: [kept("Ramen Ikkyu", daysAgo: 3, from: start)]), calendar: calendar) == nil)
        let list = [kept("Ramen Ikkyu", daysAgo: 21, from: start)]
        let plan = try #require(NotificationPlanner.plan(context(now: start, new: [NotableItem(id: "n", title: nil, category: .recipe, dueDate: nil)], kept: list), calendar: calendar))
        #expect(plan.kind == .recap)
    }

    @Test func resurfacingNeverNamesWhatIsNotSafeToShow() throws {
        let plan = try #require(NotificationPlanner.plan(context(now: start, kept: [kept(nil, .recipe, daysAgo: 70, from: start, id: "r")]), calendar: calendar))
        #expect(plan.body == "That recipe you saved 2 months ago. Cooking it this week?")
    }

    @Test func sundayDigest() throws {
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 18))!
        let plan = try #require(NotificationPlanner.plan(context(now: sunday, weekSaved: 4, weekDone: 2), calendar: calendar))
        #expect(plan.kind == .digest)
        #expect(plan.body == "4 saved, 2 done this week.")
    }

    @Test func monthlyRevealOnTheFirst() throws {
        let first = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18))!
        let plan = try #require(NotificationPlanner.plan(context(now: first), calendar: calendar))
        #expect(plan.kind == .monthlyReveal)
        #expect(plan.body == "Your October Reveal is ready. Guess how many you did?")
    }

    /// Thirty days of a plausible life: new screenshots some days, dated things coming and
    /// going, a week away in the middle. At most one notification a day, and none on nights with
    /// nothing new, nothing expiring and nothing special.
    @Test func thirtyDaySimulation() {
        var generator = SeededGenerator(seed: 42)
        var history = NotificationHistory()
        var lastOpened = start
        var dated: [NotableItem] = []
        var firesByDay: [DateComponents: Int] = [:]

        for day in 0..<30 {
            let now = start.addingTimeInterval(Double(day) * 86_400)
            let away = (12...19).contains(day)
            if !away { lastOpened = now }
            let newCount = Int.random(in: 0...3, using: &generator) == 0 ? 0 : Int.random(in: 0...2, using: &generator)
            let new = (0..<newCount).map { NotableItem(id: "d\(day)-\($0)", title: nil, category: .place, dueDate: nil) }
            if Int.random(in: 0...4, using: &generator) == 0 {
                dated.append(gig(dueInDays: Double.random(in: 1...6, using: &generator), from: now, id: "g\(day)"))
            }
            dated.removeAll { ($0.dueDate ?? now) < now }

            let context = context(now: now, new: new, dated: dated, weekSaved: 0, weekDone: 0, lastOpened: lastOpened, history: history)
            let plan = NotificationPlanner.plan(context, calendar: calendar)
            if let plan {
                history.record(plan, calendar: calendar)
                let key = calendar.dateComponents([.year, .month, .day], from: plan.fireAt)
                firesByDay[key, default: 0] += 1
            }

            let fireAt = NotificationPlanner.nextRecap(after: now, minutes: context.recapMinutes, calendar: calendar)
            let expiringUnnudged = dated.contains { item in
                guard let due = item.dueDate, !history.nudgedItemIDs.contains(item.id) || plan?.itemID == item.id else { return false }
                return due > fireAt && due.timeIntervalSince(fireAt) <= NotificationPlanner.expiryLead
            }
            let isFirst = calendar.component(.day, from: fireAt) == 1
            let emptyNight = new.isEmpty && !expiringUnnudged && !isFirst
            if emptyNight {
                #expect(plan == nil, "Day \(day) had nothing to say but sent \(String(describing: plan?.kind))")
            }
            if plan != nil {
                #expect(!plan!.body.localizedCaseInsensitiveContains("check the app"))
            }
        }
        #expect(firesByDay.values.allSatisfy { $0 <= 1 })
    }
}

/// A tiny deterministic generator, so the simulation is the same every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
