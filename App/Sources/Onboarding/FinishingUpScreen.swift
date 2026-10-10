import DesignSystem
import SwiftUI

/// When the scan outlasts the questions: the lens turns over the user's own light while the last
/// screenshots are read. The orbit's dot travels round as they go, instead of a loading bar or a
/// count (the count is the Reveal's to tell).
struct FinishingUpScreen: View {
    var palette: LightPalette = .sampleTopScreenshots
    var read: Int = 0
    var total: Int = 0

    private var progress: Double {
        total > 0 ? min(Double(read) / Double(total), 1) : 0
    }

    var body: some View {
        GeometryReader { proxy in
            let lens = min(proxy.size.width * 0.56, 240)
            ZStack {
                // The sweep crosses the lens, so the glass bends it and its rim stands out.
                LightField(.sweep(palette).shifted(down: 0.12), drifts: true)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        LensOrbit(diameter: lens * 1.22, dotAngle: -.pi / 2 + progress * 2 * .pi)
                            .animation(SBMotion.settle, value: progress)
                        GlassLens(diameter: lens)
                    }
                    Spacer()
                    // No counts: the total is the Reveal's opening line.
                    SmallLabel("Reading on this iPhone")
                        .padding(.bottom, 10)
                    MistHeadline("Hang on. **Nearly there.**", size: 32)
                        .padding(.horizontal, 28)
                    MistBody("Reading the last few. Your Reveal is **almost ready.**")
                        .padding(.top, 10)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 56)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}
