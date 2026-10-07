import Core
import Foundation
import UserNotifications

/// Puts the planned notification in iOS's queue. There's only ever one pending: each plan
/// replaces the last, which is how "at most one a day" holds even when plans are redone.
public enum NotificationScheduler {
    static let identifierPrefix = "nightly-"
    private static let historyKey = "notifications.history"

    public static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public static func isAuthorised() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Replaces whatever was pending with `plan` (or with nothing).
    public static func schedule(_ plan: PlannedNotification?, calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard let plan, await isAuthorised() else { return }

        let content = UNMutableNotificationContent()
        content.body = plan.body
        content.sound = .default
        content.userInfo = ["link": plan.link]
        content.threadIdentifier = plan.kind.rawValue
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireAt)
        let request = UNNotificationRequest(
            identifier: identifierPrefix + NotificationPlanner.monthKey(plan.fireAt, calendar: calendar) + "-\(parts.day ?? 0)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        do {
            try await center.add(request)
            var history = loadHistory()
            history.record(plan, calendar: calendar)
            saveHistory(history)
        } catch {
            Log.app.error("Couldn't schedule tonight's notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func loadHistory(_ defaults: UserDefaults? = AppGroup.defaults()) -> NotificationHistory {
        guard let data = defaults?.data(forKey: historyKey) else { return NotificationHistory() }
        return (try? JSONDecoder().decode(NotificationHistory.self, from: data)) ?? NotificationHistory()
    }

    static func saveHistory(_ history: NotificationHistory, _ defaults: UserDefaults? = AppGroup.defaults()) {
        defaults?.set(try? JSONEncoder().encode(history), forKey: historyKey)
    }
}

/// When the app was last opened, for win-back and the 30-day stop.
public enum AppOpens {
    private static let key = "app.lastOpenedAt"

    public static func record(_ date: Date = Date(), defaults: UserDefaults? = AppGroup.defaults()) {
        defaults?.set(date, forKey: key)
    }

    public static func last(_ defaults: UserDefaults? = AppGroup.defaults()) -> Date? {
        defaults?.object(forKey: key) as? Date
    }
}
