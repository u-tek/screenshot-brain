import BackgroundTasks
import Core
import Foundation
import Notifications
import ScanEngine
import Store

/// Tonight's notification: worked out from what's new, what's expiring and the user's recap time,
/// whenever the app goes to the background and again in a background refresh before the recap.
enum NightlyRecap {
    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "ScreenshotBrain") + ".recap"
    }

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task)
        }
    }

    /// Plans tonight's notification from what's known now, and asks for a refresh before the
    /// recap time to catch anything screenshotted in between.
    static func replan(services: AppServices, answers: OnboardingAnswers?, now: Date = Date()) async {
        let context = makeContext(services: services, answers: answers, now: now)
        await NotificationScheduler.schedule(NotificationPlanner.plan(context))
        scheduleRefresh(recapAt: NotificationPlanner.nextRecap(after: now, minutes: context.recapMinutes))
    }

    static func makeContext(services: AppServices, answers: OnboardingAnswers?, now: Date) -> NotificationContext {
        let database = services.database
        let lastRecap = (try? database.scanState())?.lastRecapAt ?? .distantPast
        let new = ((try? database.recapDeck(newSince: lastRecap, olderLimit: 0)) ?? []).map { notable($0.item) }
        let dated = ((try? database.comingUp(now: now, days: 3)) ?? []).map(notable)
        let week = (try? database.weekStats(now: now)) ?? (0, 0)
        return NotificationContext(
            now: now,
            recapMinutes: answers?.recapMinutes ?? answers?.windDownMinutes ?? 21 * 60 + 30,
            newItems: new,
            datedItems: dated,
            weekSaved: week.saved,
            weekDone: week.done,
            lastOpenedAt: AppOpens.last() ?? now,
            trialEndsAt: Entitlement.trialEndsAt(),
            doneCount: (try? database.score().done) ?? 0,
            history: NotificationScheduler.loadHistory()
        )
    }

    /// Only safe items are named on the Lock Screen; anything else is described by its category.
    private static func notable(_ item: ScreenshotItem) -> NotableItem {
        NotableItem(id: item.id, title: item.isSafeToDisplay ? item.title : nil, category: item.category, dueDate: item.dueDate)
    }

    private static func scheduleRefresh(recapAt: Date) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = recapAt.addingTimeInterval(-90 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.app.error("Couldn't schedule the recap refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGTask) {
        let box = RecapTaskBox(task)
        guard let services = AppServices.shared else {
            box.task.setTaskCompleted(success: true)
            return
        }
        let work = Task {
            // A refresh gets about 30 seconds: find what's new and read the newest of it.
            let access = ScreenshotLibrary.currentAccess()
            if access == .full || access == .limited {
                try? services.pipeline.discover()
                try? await services.pipeline.readPending(limit: 24)
            }
            let answers = try? services.database.onboardingAnswers()
            await replan(services: services, answers: answers)
            await WidgetRefresher.refresh(services: services)
            box.task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}

private final class RecapTaskBox: @unchecked Sendable {
    let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }
}
