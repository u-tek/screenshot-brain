import DesignSystem
import Reveal
import Store
import SwiftUI
import Triage

/// App Store screenshots, built from the real screens (real Reveal cards, the real triage deck
/// and Home, the widget) with a caption above. Exported at 6.9" by the snapshot pipeline.
enum StoreScreen: Int, CaseIterable {
    case reveal = 1
    case peak
    case triage
    case widget
    case home

    var caption: String {
        switch self {
        case .reveal: "You saved it **for a reason.**"
        case .peak: "See what you've **actually been saving.**"
        case .triage: "Keep it, drop it, or **tick it off.**"
        case .widget: "Done, **from your home screen.**"
        case .home: "Places, gigs, recipes. **Actually done.**"
        }
    }

    var label: String {
        switch self {
        case .reveal: "The Reveal"
        case .peak: "Read on your iPhone, never uploaded"
        case .triage: "Your nightly recap"
        case .widget: "The widget"
        case .home: "Follow-through"
        }
    }

    @MainActor @ViewBuilder
    var screen: some View {
        switch self {
        case .reveal:
            RevealView(story: .sample, startAt: .total, onFinish: {})
        case .peak:
            RevealView(story: .sample, startAt: .categories, onFinish: {})
        case .triage:
            TriageDeck(model: TriageModel(cards: TriageModel.sampleCards(), database: nil), label: "Tonight's recap", onFinish: {})
        case .widget:
            WidgetShowcase()
        case .home:
            ZStack(alignment: .bottom) {
                HomeScreen(home: .sample())
                GlassTabBar(selection: .constant(.saved), recapCount: 7).padding(.bottom, 4)
            }
        }
    }
}

struct StoreScreenView: View {
    let screen: StoreScreen

    var body: some View {
        GeometryReader { proxy in
            let phoneWidth = proxy.size.width * 0.74
            let scale = phoneWidth / 393
            ZStack {
                LightField(.sweep(.sampleTopScreenshots).shifted(down: 0.18), drifts: false)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    SmallLabel(screen.label)
                        .padding(.bottom, 10)
                    MistHeadline(screen.caption, size: 34)
                        .padding(.horizontal, 28)
                    Spacer(minLength: 24)
                    screen.screen
                        .frame(width: 393, height: 852)
                        .clipShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 54, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 6))
                        .shadow(color: .black.opacity(0.08), radius: 40)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: phoneWidth, height: 852 * scale, alignment: .top)
                }
                .padding(.top, 36)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
    }
}

/// The widget on a home screen of mist, with the Lock Screen score above it.
private struct WidgetShowcase: View {
    var body: some View {
        ZStack {
            LightField(.sweep(.sampleTopScreenshots).mirrored(), drifts: false)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Text("9:41")
                    .font(.system(size: 88, weight: .semibold, design: .rounded))
                    .foregroundStyle(SBColor.ink.opacity(0.85))
                WidgetPreview(palette: .sampleTopScreenshots)
                    .frame(height: 170)
                    .padding(.horizontal, 20)
                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 62, height: 62)
                    }
                }
                Spacer()
            }
        }
    }
}
