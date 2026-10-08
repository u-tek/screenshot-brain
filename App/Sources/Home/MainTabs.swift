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

    var systemImage: String {
        switch self {
        case .saved: "square.stack"
        case .recap: "rectangle.on.rectangle.angled"
        case .settings: "slider.horizontal.3"
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

/// The floating glass tab bar.
struct GlassTabBar: View {
    @Binding var selection: MainTab
    var recapCount: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    Haptics.selection()
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: selection == tab ? .regular : .light))
                            .overlay(alignment: .topTrailing) {
                                if tab == .recap, recapCount > 0 {
                                    Circle().fill(SBColor.accent).frame(width: 7, height: 7).offset(x: 6, y: -2)
                                }
                            }
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selection == tab ? SBColor.ink : SBColor.inkSecondary)
                    .frame(width: 88, height: 54)
                    .background {
                        if selection == tab {
                            Capsule().fill(Color.white.opacity(0.35))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab == .recap && recapCount > 0 ? "Recap, \(recapCount) waiting" : tab.title))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .sbGlass(in: Capsule())
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
                SmallLabel("Recap")
                MistHeadline("All caught up. **Nice.**", size: 32)
                MistBody("New screenshots turn up here at **wind-down time.**")
                    .padding(.horizontal, 36)
                    .padding(.bottom, 120)
            }
        }
    }
}

/// Everything kept in one category, oldest untouched first.
struct CategoryScreen: View {
    @Environment(\.dismiss) private var dismiss
    let category: ItemCategory
    let items: [ScreenshotItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    GlassIconButton("chevron.left", label: "Back") { dismiss() }
                    Spacer()
                }
                SmallLabel(items.count == 1 ? "1 kept" : "\(items.count) kept")
                MistHeadline("Still want: **\(CategoryName.title(category).lowercased()).**", size: 30, alignment: .leading)
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        NavigationLink(value: HomeRoute.item(item.id)) {
                            ItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background {
            LightField(.bloom(.category(category)).shifted(down: -0.1), drifts: true)
                .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
