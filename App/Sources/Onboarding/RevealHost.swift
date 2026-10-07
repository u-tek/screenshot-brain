import Core
import DesignSystem
import Reveal
import SwiftUI

/// Builds the Reveal from what's been read, then plays it.
struct RevealHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if let story = model.story {
                RevealView(
                    story: story,
                    onShare: { model.analytics.track(.revealShared) },
                    onFinish: {
                        model.analytics.track(.revealCompleted)
                        model.advance(to: .triage)
                    }
                )
                .transition(.opacity)
            } else {
                LightField(.sweep(model.palette), drifts: true)
                    .ignoresSafeArea()
            }
        }
        .task {
            if model.story == nil {
                await model.prepareReveal()
            }
        }
    }
}
