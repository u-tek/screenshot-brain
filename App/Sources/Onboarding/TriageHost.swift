import Core
import DesignSystem
import SwiftUI
import Triage

/// The first triage, straight after the Reveal: the 30 most recent intentions.
struct TriageHost: View {
    @EnvironmentObject private var model: AppModel
    @State private var triage: TriageModel?

    var body: some View {
        ZStack {
            if let triage {
                TriageDeck(model: triage, label: "Your first sort") {
                    model.finishRecap(triage.tally)
                    model.advance(to: .score)
                }
            } else {
                LightField(.sweep(model.palette), drifts: true)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            guard triage == nil else { return }
            let cards = model.recapCards()
            if cards.isEmpty {
                model.advance(to: .score)
            } else {
                model.analytics.track(.triageStarted, counts: ["cards": cards.count])
                triage = TriageModel(cards: cards, database: model.services?.database)
            }
        }
    }
}
