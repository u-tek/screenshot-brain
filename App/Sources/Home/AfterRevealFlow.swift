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
            PaywallView(
                purchases: model.purchases,
                palette: model.palette,
                items: model.paywallItems(),
                privacyPolicy: model.configuration.privacyPolicyURL,
                onClose: { model.advance(to: .widgetGuide) },
                onPurchased: {
                    model.purchased()
                    model.advance(to: .widgetGuide)
                }
            )
            .onAppear { model.analytics.track(.paywallShown) }
        case .notifications:
            NotificationsPrompt(palette: model.palette, recapMinutes: model.answers.recapMinutes ?? 21 * 60 + 30) {
                Task { await model.requestNotifications() }
            } onSkip: {
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
