import Core
import DesignSystem
import Paywall
import SwiftUI

/// Everything after the Reveal: triage, the score moment, the notifications pre-prompt, the
/// paywall, the widget guide and Home.
struct AfterRevealFlow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.step {
        case .triage:
            TriageHost()
        case .score:
            ScoreMoment(palette: model.palette, score: model.score, guessedOutOfTen: model.answers.guessedDoneCount) {
                model.advance(to: .notifications)
            }
        case .paywall:
            OnboardingPaywall()
        case .notifications:
            NotificationsPrompt(palette: model.palette, recapMinutes: NightlyRecap.recapMinutes(model.answers)) {
                Task { await model.requestNotifications() }
            } onSkip: {
                model.analytics.track(.notificationsPrepromptSkipped)
                model.advance(to: .paywall)
            }
        case .widgetGuide:
            WidgetGuide(palette: model.palette) {
                model.advance(to: .home)
            }
        default:
            MainScreen(database: model.services?.database)
        }
    }
}

/// The paywall after the Reveal. Its items (what the user's widget would show) are read once when
/// it appears, not on every redraw.
private struct OnboardingPaywall: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [PaywallItem]?

    var body: some View {
        ZStack {
            if let items {
                PaywallView(
                    purchases: model.purchases,
                    palette: model.palette,
                    items: items,
                    privacyPolicy: model.configuration.privacyPolicyURL,
                    onClose: {
                        model.analytics.track(.paywallDismissed, counts: ["source": 0])
                        model.advance(to: .widgetGuide)
                    },
                    onPurchased: {
                        model.purchased()
                        model.advance(to: .widgetGuide)
                    }
                )
                .onAppear { model.analytics.track(.paywallShown) }
            }
        }
        .task {
            if items == nil { items = model.paywallItems() }
        }
    }
}
