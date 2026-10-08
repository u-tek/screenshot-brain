import Core
import Foundation
import UserNotifications

/// Puts the planned notification in iOS's queue. There's only ever one pending: each plan
/// replaces the last, which is how "at most one a day" holds even when plans are redone.
public enum NotificationScheduler {
    static let identifierPrefix = "nightly-"
    private static let historyKey = "notifications.history"
    private static let pendingKey = "notifications.pending"

    /// The history from before the waiting notification was recorded, so a replan that replaces
    /// it before it fires can give back whatever it used up (the trial reminder, the monthly
    /// Reveal, a nudge about an item).
    struct PendingRecord: Codable {
        var fireAt: Date
        var before: NotificationHistory
    }

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
        discardPending()
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
            let before = loadHistory()
            var history = before
            history.record(plan, calendar: calendar)
            saveHistory(history)
            savePending(PendingRecord(fireAt: plan.fireAt, before: before))
        } catch {
            Log.app.error("Couldn't schedule tonight's notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// What's been sent. A notification still waiting to fire doesn't count yet, so planning
    /// again the same evening can choose it again.
    public static func loadHistory(_ defaults: UserDefaults? = AppGroup.defaults(), now: Date = Date()) -> NotificationHistory {
        if let pending = pendingRecord(defaults), pending.fireAt > now {
            return pending.before
        }
        guard let data = defaults?.data(forKey: historyKey) else { return NotificationHistory() }
        return (try? JSONDecoder().decode(NotificationHistory.self, from: data)) ?? NotificationHistory()
    }

    /// Clears everything scheduled and sent (Delete everything).
    public static func reset(_ defaults: UserDefaults? = AppGroup.defaults()) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        defaults?.removeObject(forKey: historyKey)
        defaults?.removeObject(forKey: pendingKey)
    }

    static func saveHistory(_ history: NotificationHistory, _ defaults: UserDefaults? = AppGroup.defaults()) {
        defaults?.set(try? JSONEncoder().encode(history), forKey: historyKey)
    }

    static func pendingRecord(_ defaults: UserDefaults?) -> PendingRecord? {
        guard let data = defaults?.data(forKey: pendingKey) else { return nil }
        return try? JSONDecoder().decode(PendingRecord.self, from: data)
    }

    static func savePending(_ record: PendingRecord, _ defaults: UserDefaults? = AppGroup.defaults()) {
        defaults?.set(try? JSONEncoder().encode(record), forKey: pendingKey)
    }

    /// The waiting notification was just removed. If it hadn't fired, it never happened.
    static func discardPending(_ defaults: UserDefaults? = AppGroup.defaults(), now: Date = Date()) {
        guard let record = pendingRecord(defaults) else { return }
        if record.fireAt > now {
            saveHistory(record.before, defaults)
        }
        defaults?.removeObject(forKey: pendingKey)
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
