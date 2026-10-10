import Core
import DesignSystem
import Paywall
import Reveal
import Store
import SwiftUI
import Triage

/// The app after onboarding: Home, with Kept, an item and Settings pushed on top of it, and
/// sorting, the paywall and a Reveal covering it.
struct MainScreen: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var home: HomeModel
    @State private var path = NavigationPath()
    @State private var isSorting = false
    @State private var deleteError: String?
    @State private var showsPaywall = false
    @State private var reveal: RevealStory?
    @Environment(\.scenePhase) private var scenePhase

    init(database: AppDatabase?) {
        _home = StateObject(wrappedValue: HomeModel(database: database))
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(
                home: home,
                onSort: { isSorting = true },
                onKept: { path.append(HomeRoute.kept) },
                onSettings: { path.append(HomeRoute.settings) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .item(let id):
                    ItemDetailScreen(itemID: id) { home.reload() }
                case .category(let category):
                    CategoryScreen(category: category, items: home.shelves.first { $0.category == category }?.items ?? [])
                case .filed(let category):
                    CategoryScreen(category: category, items: home.filed.first { $0.category == category }?.items ?? [], label: "Filed away")
                case .kept:
                    KeptScreen(
                        home: home,
                        palette: model.palette,
                        isPremium: model.isPremium,
                        onDeleteDropped: { deleteDropped() },
                        onReveal: openReveal
                    )
                case .settings:
                    SettingsScreen(onShowPlans: { showsPaywall = true })
                }
            }
        }
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
        .fullScreenCover(isPresented: $isSorting, onDismiss: { home.reload() }) {
            SortSession(onDeleteDropped: deleteDropped) {
                isSorting = false
            }
            .environmentObject(model)
        }
        .fullScreenCover(isPresented: $showsPaywall) {
            PaywallView(
                purchases: model.purchases,
                palette: model.palette,
                items: model.paywallItems(),
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

    /// A widget or notification link: an item opens over Home, the recap opens sorting.
    private func follow(_ link: AppLink?) {
        guard let link else { return }
        model.pendingLink = nil
        switch link {
        case .item(let id):
            isSorting = false
            path = NavigationPath()
            path.append(HomeRoute.item(id))
        case .recap:
            path = NavigationPath()
            isSorting = true
        case .home:
            isSorting = false
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

    /// Deletes the dropped screenshots from Photos behind iOS's one confirmation, then calls
    /// `then` so whatever showed the count can refresh it.
    private func deleteDropped(then: @escaping @MainActor () -> Void = {}) {
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
            then()
        }
    }
}

/// Sorting, from Home: the pile 30 at a time, newest first. "Finish later" goes straight back;
/// finishing a batch shows how it went, with what's left and the dropped ones to clear.
struct SortSession: View {
    @EnvironmentObject private var model: AppModel
    @State private var triage: TriageModel?
    @State private var isBatchOver = false
    @State private var left = 0
    @State private var dropped = 0
    var onDeleteDropped: (@escaping @MainActor () -> Void) -> Void = { _ in }
    var onClose: () -> Void = {}

    var body: some View {
        ZStack {
            if let triage, !triage.cards.isEmpty, !isBatchOver {
                TriageDeck(model: triage, label: "Sort") {
                    finish(triage)
                }
                .id(ObjectIdentifier(triage))
            } else {
                SortDone(
                    left: left,
                    dropped: dropped,
                    onKeepGoing: startBatch,
                    onDeleteDropped: { onDeleteDropped(refreshCounts) },
                    onClose: onClose
                )
                .transition(.opacity)
            }
        }
        .animation(SBMotion.settle, value: isBatchOver)
        .onAppear {
            if triage == nil { startBatch() }
        }
    }

    private func startBatch() {
        let cards = model.sortCards()
        if !cards.isEmpty {
            model.analytics.track(.triageStarted, counts: ["cards": cards.count])
        }
        triage = TriageModel(cards: cards, database: model.services?.database)
        isBatchOver = cards.isEmpty
        refreshCounts()
    }

    private func finish(_ triage: TriageModel) {
        model.finishRecap(triage.tally)
        if triage.isFinished {
            refreshCounts()
            isBatchOver = true
        } else {
            onClose()
        }
    }

    private func refreshCounts() {
        left = model.toSortCount()
        dropped = model.droppedCount()
    }
}

/// The end of a batch: all sorted (or how many are left), a way to clear the dropped ones from
/// Photos, and back to Home.
struct SortDone: View {
    let left: Int
    let dropped: Int
    var onKeepGoing: () -> Void = {}
    var onDeleteDropped: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                SBCircleButton(.x, label: "Back to Home", action: onClose)
            }
            .padding(.horizontal, SBSpace.gutter)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                Text(left > 0 ? "Nice." : "All sorted.")
                    .sbText(.large)
                Text(left > 0 ? (left == 1 ? "1 more to sort." : "\(left) more to sort.") : "New screenshots land here as you take them.")
                    .sbText(.body)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 14) {
                if left > 0 {
                    StartSortingButton(title: "Keep going", action: onKeepGoing)
                }
                if dropped > 0 {
                    Button(action: onDeleteDropped) {
                        Text(dropped == 1 ? "Delete 1 dropped screenshot from Photos" : "Delete \(dropped) dropped from Photos")
                            .sbText(.body, color: SBColor.ink)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 48)
                            .background(Capsule().fill(SBColor.warm(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(SBPressStyle())
                }
                if left == 0 {
                    StartSortingButton(title: "Back to Home", action: onClose)
                }
            }
            .padding(.bottom, 28)
        }
        .sbScreen(left > 0 ? SBAmbience(energy: 0.55) : .calm)
    }
}

/// Everything kept (or filed) in one category.
struct CategoryScreen: View {
    @Environment(\.dismiss) private var dismiss
    let category: ItemCategory
    let items: [ScreenshotItem]
    var label = "Still want"

    var body: some View {
        VStack(spacing: 0) {
            SBNavHeader(title: CategoryName.title(category), onLeading: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SBLabel("\(label) · \(items.count)")
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
        .sbScreen(.kind(SBKind(category)))
        .toolbar(.hidden, for: .navigationBar)
    }
}
