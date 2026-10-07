import DesignSystem
import Paywall
import Reveal
import Store
import SwiftUI
import Triage

/// Opens one screen in a fixed state for the UI snapshot exporter (`UITests/SnapshotExportTests`).
///
/// Launch arguments: `-SBSnapshot <route> -SBAppearance light|dark`. Arguments in this form land in
/// the `UserDefaults` argument domain, so they never persist.
struct SnapshotMode: Sendable {
    enum Appearance: String, Sendable {
        case light
        case dark

        var colorScheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

    let route: String
    let appearance: Appearance

    static let current: SnapshotMode? = {
        let defaults = UserDefaults.standard
        guard let route = defaults.string(forKey: "SBSnapshot"), !route.isEmpty else { return nil }
        let appearance = defaults.string(forKey: "SBAppearance").flatMap(Appearance.init(rawValue:)) ?? .light
        return SnapshotMode(route: route, appearance: appearance)
    }()
}

/// Every screen the exporter can open, by route name.
@MainActor
enum SnapshotGallery {
    static func view(for route: String) -> AnyView? {
        let palette = LightPalette.sampleTopScreenshots
        switch route {
        case "welcome":
            return AnyView(WelcomeScreen())
        case "signin":
            return AnyView(SignInScreen())
        case "photoaccess":
            return AnyView(PhotoAccessPrompt())
        case "sharein":
            return AnyView(ShareRouteScreen())
        case "question1":
            return AnyView(CountQuestion(palette: palette, footnote: QuestionsFlow.footnote(question: 1, read: 0, isScanning: true), initial: 150, onNext: { _ in }))
        case "question2":
            return AnyView(TopCategoryQuestion(palette: palette, footnote: QuestionsFlow.footnote(question: 2, read: 86, isScanning: true), initial: .place, onNext: { _ in }))
        case "question3":
            return AnyView(DoneQuestion(palette: palette, footnote: QuestionsFlow.footnote(question: 3, read: 143, isScanning: true), initial: nil, onNext: { _ in }))
        case "question4":
            return AnyView(WindDownQuestion(palette: palette, footnote: QuestionsFlow.footnote(question: 4, read: 197, isScanning: true), initial: 22 * 60 + 30, onNext: { _ in }))
        case "question5":
            return AnyView(PeakQuestion(palette: palette, footnote: QuestionsFlow.footnote(question: 5, read: 214, isScanning: false), initial: .lateNight, onNext: { _ in }, onSkip: {}))
        case "finishing":
            return AnyView(FinishingUpScreen(palette: palette, read: 182, total: 240))
        case "sharecard":
            return AnyView(ZStack {
                Color(white: 0.86).ignoresSafeArea()
                ShareCardView(story: .sample)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(24)
            })
        case "triage":
            return AnyView(TriageDeck(model: TriageModel(cards: TriageModel.sampleCards(), database: nil), label: "Your first recap", onFinish: {}))
        case "score":
            return AnyView(ScoreMoment(palette: palette, score: Score(done: 2, total: 19), guessedOutOfTen: 3))
        case "home":
            return AnyView(NavigationStack {
                ZStack(alignment: .bottom) {
                    HomeScreen(home: .sample(), palette: palette)
                    GlassTabBar(selection: .constant(.saved), recapCount: 7).padding(.bottom, 4)
                }
            })
        case "item":
            return AnyView(NavigationStack { ItemDetailScreen(itemID: SampleData.gig.id, preview: SampleData.gig) })
        case "caughtup":
            return AnyView(RecapTab())
        case "settings":
            return AnyView(SettingsScreen())
        case "notifications":
            return AnyView(NotificationsPrompt(palette: palette))
        case "widgetguide":
            return AnyView(WidgetGuide(palette: palette))
        case "paywall":
            return AnyView(PaywallView(purchases: PurchaseService(apiKey: nil, appUserID: nil), palette: palette, privacyPolicy: nil, onClose: {}, onPurchased: {}))
        case "lab":
            return AnyView(DesignLabView())
        default:
            if route.hasPrefix("reveal."), let card = RevealCard(rawValue: String(route.dropFirst(7))) {
                return AnyView(RevealView(story: .sample, startAt: card, onFinish: {}))
            }
            guard route.hasPrefix("lab."), let page = DesignLabPage(rawValue: String(route.dropFirst(4))) else {
                return nil
            }
            return AnyView(ZStack(alignment: .top) {
                LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                page.view
            })
        }
    }
}

struct SnapshotHost: View {
    let mode: SnapshotMode

    var body: some View {
        Group {
            if let view = SnapshotGallery.view(for: mode.route) {
                view
            } else {
                Text("Unknown snapshot route \(mode.route)")
            }
        }
        .preferredColorScheme(mode.appearance.colorScheme)
        .environment(\.lightIsStill, true)
        .onAppear {
            UIView.setAnimationsEnabled(false)
        }
    }
}
