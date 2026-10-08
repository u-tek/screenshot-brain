import Foundation
import Testing
@testable import Notifications

/// A notification only counts as sent once it fires: replanning the same evening mustn't use
/// up the trial reminder, the monthly Reveal or an item's nudge.
@Suite struct NotificationHistoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "NotificationHistoryTests.\(UUID().uuidString)")!
    }

    private func waitingTrialReminder(in defaults: UserDefaults) {
        var sent = NotificationHistory()
        sent.trialReminderSent = true
        NotificationScheduler.saveHistory(sent, defaults)
        NotificationScheduler.savePending(.init(fireAt: now.addingTimeInterval(3_600), before: NotificationHistory()), defaults)
    }

    @Test func aWaitingNotificationCountsOnlyOnceItFires() {
        let defaults = defaults()
        waitingTrialReminder(in: defaults)
        #expect(NotificationScheduler.loadHistory(defaults, now: now).trialReminderSent == false)
        #expect(NotificationScheduler.loadHistory(defaults, now: now.addingTimeInterval(7_200)).trialReminderSent)
    }

    @Test func replacingAWaitingNotificationGivesBackWhatItUsed() {
        let defaults = defaults()
        waitingTrialReminder(in: defaults)
        NotificationScheduler.discardPending(defaults, now: now)
        #expect(NotificationScheduler.loadHistory(defaults, now: now.addingTimeInterval(7_200)).trialReminderSent == false)
    }

    @Test func aNotificationThatFiredStaysSent() {
        let defaults = defaults()
        waitingTrialReminder(in: defaults)
        NotificationScheduler.discardPending(defaults, now: now.addingTimeInterval(7_200))
        #expect(NotificationScheduler.loadHistory(defaults, now: now.addingTimeInterval(7_200)).trialReminderSent)
    }
}
