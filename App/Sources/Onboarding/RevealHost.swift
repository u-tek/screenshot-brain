import Core
import DesignSystem
import Reveal
import SwiftUI

/// Builds the Reveal from what's been read, then plays it.
struct RevealHost: View {
    @EnvironmentObject private var model: AppModel
    @State private var failed = false

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
                if failed {
                    // Never a dead end: without a story, carry on to triage.
                    VStack(alignment: .leading, spacing: 14) {
                        Spacer()
                        MistHeadline("Your Reveal **needs a few more.**", size: 32, alignment: .leading)
                        MistBody("It'll be ready once more of your screenshots have been read. Carry on for now.", alignment: .leading)
                            .padding(.bottom, 14)
                        ActionBar("Carry on", palette: model.palette) {
                            model.advance(to: .triage)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
        }
        .task {
            if model.story == nil {
                await model.prepareReveal()
            }
            withAnimation(.easeOut(duration: 0.3)) {
                failed = model.story == nil
            }
        }
    }
}
