import Core
import DesignSystem
import SwiftUI

/// Everything after the Reveal: triage, the score moment, the paywall, the notifications
/// pre-prompt, the widget guide and Home.
struct AfterRevealFlow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            LightField(.sweep(model.palette), drifts: true)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                SmallLabel("Up next")
                MistHeadline("Now let's **sort the keepers.**", size: 32)
            }
            .padding(.horizontal, 28)
        }
    }
}
