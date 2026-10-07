import Core
import DesignSystem
import Paywall
import SwiftUI

/// Everything after the Reveal: triage, the score moment, the paywall, the notifications
/// pre-prompt, the widget guide and Home.
struct AfterRevealFlow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.step {
        case .triage:
            TriageHost()
        case .score:
            ScoreMoment(palette: model.palette, score: model.score, guessedOutOfTen: model.answers.guessedDoneCount) {
                model.advance(to: .paywall)
            }
        case .paywall:
            PaywallView(
                purchases: model.purchases,
                palette: model.palette,
                privacyPolicy: model.configuration.privacyPolicyURL,
                onClose: { model.advance(to: .notifications) },
                onPurchased: {
                    model.purchased()
                    model.advance(to: .notifications)
                }
            )
            .onAppear { model.analytics.track(.paywallShown) }
        case .notifications:
            NotificationsPrompt(palette: model.palette, recapMinutes: model.answers.recapMinutes ?? 21 * 60 + 30) {
                Task { await model.requestNotifications() }
            } onSkip: {
                model.advance(to: .widgetGuide)
            }
        case .widgetGuide:
            WidgetGuide(palette: model.palette) {
                model.advance(to: .home)
            }
        default:
            MainTabs(database: model.services?.database)
        }
    }
}
