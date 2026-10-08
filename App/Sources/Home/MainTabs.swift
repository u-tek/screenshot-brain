import Core
import DesignSystem
import Paywall
import Reveal
import Store
import SwiftUI
import Triage

enum MainTab: String, CaseIterable, Identifiable {
    case saved
    case recap
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved: "Saved"
        case .recap: "Recap"
        case .settings: "Settings"
        }
    }

    var icon: SBIcon {
        switch self {
        case .saved: .bookmark
        case .recap: .stack
        case .settings: .sliders
        }
    }
}

/// Home, the recap and settings, under a floating glass tab bar.
struct MainTabs: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var home: HomeModel
    @State private var tab: MainTab = .saved
    @State private var path = NavigationPath()
    @State private var deleteError: String?
    @State private var showsPaywall = false
    @State private var reveal: RevealStory?
    @Environment(\.scenePhase) private var scenePhase

    init(database: AppDatabase?) {
        _home = StateObject(wrappedValue: HomeModel(database: database))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .saved:
                NavigationStack(path: $path) {
                    HomeScreen(
                        home: home,
                        palette: model.palette,
                        isPremium: model.isPremium,
                        onRecap: { tab = .recap },
                        onDeleteDropped: deleteDropped,
                        onReveal: openReveal
                    )
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: HomeRoute.self) { route in
                            switch route {
                            case .item(let id):
                                ItemDetailScreen(itemID: id) { home.reload() }
                            case .category(let category):
                                CategoryScreen(category: category, items: home.shelves.first { $0.category == category }?.items ?? [])
                            }
                        }
                }
            case .recap:
                RecapTab {
                    home.reload()
                    tab = .saved
                }
            case .settings:
                SettingsScreen(onShowPlans: { showsPaywall = true })
            }

            if path.isEmpty {
                GlassTabBar(selection: $tab, recapCount: home.recapCount)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(SBMotion.settle, value: path.isEmpty)
        .onAppear { home.reload() }
        .onChange(of: model.isScanning) { scanning in
            if !scanning { home.reload() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { home.reload() }
        }
        .onChange(of: model.pendingLink) { link in
            follow(link)
        }
        .onAppear { follow(model.pendingLink) }
        .fullScreenCover(isPresented: $showsPaywall) {
            PaywallView(
                purchases: model.purchases,
                palette: model.palette,
                privacyPolicy: model.configuration.privacyPolicyURL,
                onClose: { showsPaywall = false },
                onPurchased: {
                    model.purchased()
                    showsPaywall = false
                }
            )
            .onAppear { model.analytics.track(.paywallShown) }
        }
        .fullScreenCover(isPresented: Binding(get: { reveal != nil }, set: { if !$0 { reveal = nil } })) {
            if let reveal {
                RevealView(story: reveal, onShare: { model.analytics.track(.revealShared) }, onFinish: { self.reveal = nil })
            }
        }
        .alert("Couldn't delete them", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func follow(_ link: AppLink?) {
        guard let link else { return }
        model.pendingLink = nil
        switch link {
        case .item(let id):
            tab = .saved
            path = NavigationPath()
            path.append(HomeRoute.item(id))
        case .recap:
            path = NavigationPath()
            tab = .recap
        case .home:
            tab = .saved
            path = NavigationPath()
        case .paywall:
            showsPaywall = true
        }
    }

    private func openReveal(_ period: RevealPeriod) {
        if period == .allTime, !model.isPremium {
            showsPaywall = true
            return
        }
        Task {
            reveal = await model.buildReveal(period)
        }
    }

    private func deleteDropped() {
        Task {
            do {
                let deleted = try await model.deleteDropped()
                if deleted > 0 { Haptics.success() }
            } catch {
                // Declining iOS's confirmation lands here too; that's not worth an alert.
                let declined = (error as NSError).domain == "PHPhotosErrorDomain" && (error as NSError).code == 3072
                if !declined {
                    deleteError = "Photos said no. Try again from Photos itself."
                }
            }
            home.reload()
        }
    }
}

/// The floating tab bar: a warm glass capsule, the current tab lit.
struct GlassTabBar: View {
    @Binding var selection: MainTab
    var recapCount: Int = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    Haptics.selection()
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        SBIconView(tab.icon, size: 20)
                            .overlay(alignment: .topTrailing) {
                                if tab == .recap, recapCount > 0 {
                                    Circle()
                                        .fill(SBColor.accent)
                                        .frame(width: 7, height: 7)
                                        .shadow(color: SBKind.events.core, radius: 4)
                                        .offset(x: 6, y: -2)
                                }
                            }
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selection == tab ? SBColor.ink : SBColor.ink2)
                    .frame(width: 96, height: 56)
                    .background {
                        if selection == tab {
                            Capsule().fill(SBColor.warm(0.12))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(SBPressStyle())
                .accessibilityLabel(Text(tab == .recap && recapCount > 0 ? "Recap, \(recapCount) waiting" : tab.title))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(SBColor.tabBarFill)
                Capsule().strokeBorder(SBColor.line, lineWidth: 1)
                Capsule().strokeBorder(LinearGradient(colors: [SBColor.warm(0.08), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 15, y: 10)
        }
    }
}

/// The nightly recap: what's new since last time, a few older ones, then done.
struct RecapTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var triage: TriageModel?
    var onFinish: () -> Void = {}

    var body: some View {
        ZStack {
            if let triage, !triage.cards.isEmpty {
                TriageDeck(model: triage) {
                    model.finishRecap(triage.tally)
                    self.triage = nil
                    onFinish()
                }
                // The tab bar stays under the deck, so the decision row sits above it.
                .environment(\.sbBottomClearance, SBSpace.tabBarHeight + 4)
            } else {
                CaughtUp(palette: model.palette)
            }
        }
        .onAppear {
            if triage == nil {
                triage = TriageModel(cards: model.recapCards(), database: model.services?.database)
            }
        }
    }
}

private struct CaughtUp: View {
    let palette: LightPalette

    var body: some View {
        ZStack {
            LightField(.sweep(palette).shifted(down: 0.08), drifts: true)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer()
                GlassLens(diameter: 140)
                Spacer()
                SBLabel("Recap")
                MistHeadline("All caught up. **Nice.**", size: 32)
                MistBody("New screenshots turn up here at **wind-down time.**")
                    .padding(.horizontal, 36)
                    .padding(.bottom, 120)
            }
        }
        .sbScreen()
    }
}

/// Everything kept in one category, oldest untouched first.
struct CategoryScreen: View {
    @Environment(\.dismiss) private var dismiss
    let category: ItemCategory
    let items: [ScreenshotItem]

    var body: some View {
        VStack(spacing: 0) {
            SBNavHeader(title: CategoryName.title(category), onLeading: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SBLabel("Still want · \(items.count)")
                    VStack(spacing: SBSpace.gap) {
                        ForEach(items) { item in
                            NavigationLink(value: HomeRoute.item(item.id)) {
                                ItemRow(item: item)
                            }
                            .buttonStyle(SBPressStyle())
                        }
                    }
                }
                .padding(.horizontal, SBSpace.gutter)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .sbScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}
