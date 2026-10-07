import Core
import Foundation
import Store

/// Builds the widget's timeline from the shared database: marks what's been on screen as
/// surfaced, reads what may show next, and plans the rotation.
public struct WidgetTimeline {
    private let database: AppDatabase
    private let defaults: UserDefaults?

    public init(database: AppDatabase, defaults: UserDefaults?) {
        self.database = database
        self.defaults = defaults
    }

    public func build(access: WidgetAccess, now: Date = Date(), calendar: Calendar = .current) -> (entries: [WidgetEntryPlan], reloadAt: Date) {
        let shown = WidgetPlanner.surfaced(schedule: WidgetSchedule.load(defaults), now: now)
        for entry in shown {
            try? database.markSurfaced(ids: [entry.id], at: entry.date)
        }
        let candidates = (try? database.widgetCandidates(now: now, calendar: calendar)) ?? []
        let kept = (try? database.widgetCandidates(now: now, calendar: calendar, includeSurfaced: true).count) ?? candidates.count
        let lastRecap = (try? database.scanState())?.lastRecapAt ?? .distantPast
        let waiting = (try? database.recapCount(newSince: lastRecap)) ?? 0
        let score = (try? database.score()) ?? Score(done: 0, total: 0)
        let plan = WidgetPlanner.plan(
            candidates: candidates,
            keptCount: kept,
            waitingCount: waiting,
            score: score,
            access: access,
            now: now,
            calendar: calendar
        )
        let schedule = plan.entries.compactMap { entry -> ScheduledItem? in
            guard case .item(let item) = entry.card else { return nil }
            return ScheduledItem(id: item.id, date: entry.date)
        }
        WidgetSchedule.save(schedule, to: defaults)
        return plan
    }
}
