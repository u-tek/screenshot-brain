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
        .environment(\.analytics, model.analytics)
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
/// finishing a batch shows how it went, with what's left and the dropped ones to clear, and once
/// it's all sorted, one thing to go and do.
struct SortSession: View {
    @EnvironmentObject private var model: AppModel
    @State private var triage: TriageModel?
    @State private var isBatchOver = false
    @State private var left = 0
    @State private var dropped = 0
    /// Everything decided since sorting opened, across batches.
    @State private var sorted = TriageTally()
    @State private var nextUp: NextUp?
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
                    sorted: sorted,
                    nextUp: nextUp,
                    onKeepGoing: keepGoing,
                    onDeleteDropped: { onDeleteDropped(refreshCounts) },
                    onOpenNextUp: openNextUp,
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

    private func keepGoing() {
        model.analytics.track(.sortKeptGoing, counts: ["left": left])
        startBatch()
    }

    /// Closes sorting and opens the pick over Home, the same way a widget link does.
    private func openNextUp(_ pick: NextUp) {
        model.analytics.track(.nextUpOpened, counts: ["from": 1, "dated": pick.isDated])
        model.pendingLink = .item(pick.item.id)
    }

    private func finish(_ triage: TriageModel) {
        model.finishRecap(triage.tally)
        sorted.kept += triage.tally.kept
        sorted.done += triage.tally.done
        sorted.dropped += triage.tally.dropped
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
        nextUp = left == 0 ? NextUp.pick(from: model.services?.database) : nil
    }
}

/// The end of a batch: how many were just sorted and where they went, then either how many are
/// left (with "Keep going") or, once it's all sorted, one thing kept to go and do. Plus a way to
/// clear the dropped ones from Photos, and back to Home.
struct SortDone: View {
    let left: Int
    let dropped: Int
    var sorted = TriageTally()
    var nextUp: NextUp?
    var onKeepGoing: () -> Void = {}
    var onDeleteDropped: () -> Void = {}
    var onOpenNextUp: (NextUp) -> Void = { _ in }
    var onClose: () -> Void = {}
    @Environment(\.analytics) private var analytics

    private var sortedCount: Int { sorted.kept + sorted.done + sorted.dropped }
    /// The pick only shows once the pile's gone, so "Keep going" stays the one thing to do.
    private var pick: NextUp? { left == 0 ? nextUp : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                SBCircleButton(.x, label: "Back to Home", action: onClose)
            }
            .padding(.horizontal, SBSpace.gutter)
            .padding(.top, 8)

            Spacer()

            if sortedCount > 0 {
                tally
            } else {
                VStack(spacing: 12) {
                    Text(left > 0 ? "Nice." : "All sorted.")
                        .sbText(.large)
                    Text(left > 0 ? moreToSort : "New screenshots land here as you take them.")
                        .sbText(.body)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
            }

            if let pick {
                Button { onOpenNextUp(pick) } label: {
                    NextUpCard(pick: pick)
                }
                .buttonStyle(SBPressStyle())
                .padding(.horizontal, SBSpace.gutter)
                .padding(.top, 32)
                .onAppear {
                    analytics.track(.nextUpShown, counts: ["from": 1, "dated": pick.isDated])
                }
            }

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
        .onAppear {
            // Clearing the whole pile is the moment worth feeling.
            if sortedCount > 0, left == 0 { Haptics.success() }
        }
    }

    /// "12 sorted", where they went, and what's left: the same big number as Home's pile.
    private var tally: some View {
        VStack(spacing: 0) {
            Text("\(sortedCount)")
                .sbText(.numXL)
                .monospacedDigit()
            Text("sorted")
                .sbText(.unit, color: SBColor.ink2)
                .padding(.top, 6)
            Text(breakdown)
                .sbText(.body, color: SBColor.ink)
                .padding(.top, 18)
            Text(left > 0 ? moreToSort : "That's the lot. All sorted.")
                .sbText(.body)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
    }

    /// "4 still want · 2 done · 6 dropped", leaving out the empty ones.
    private var breakdown: String {
        [
            sorted.kept > 0 ? "\(sorted.kept) still want" : nil,
            sorted.done > 0 ? "\(sorted.done) done" : nil,
            sorted.dropped > 0 ? "\(sorted.dropped) dropped" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var moreToSort: String {
        left == 1 ? "1 more to sort." : "\(left) more to sort."
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
