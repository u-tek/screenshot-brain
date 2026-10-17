import Core
import Foundation
import Store

/// What Home, Kept and the did-it log show: how many screenshots are waiting to be sorted, the
/// score, what's coming up, what's still wanted, what's been done, and search.
@MainActor
final class HomeModel: ObservableObject {
    struct Shelf: Identifiable, Hashable {
        let category: ItemCategory
        let items: [ScreenshotItem]

        var id: ItemCategory { category }
    }

    @Published private(set) var score = Score(done: 0, total: 0)
    @Published private(set) var comingUp: [ScreenshotItem] = []
    @Published private(set) var shelves: [Shelf] = []
    /// Filed away without sorting: chats, posts, receipts and the rest, by kind.
    @Published private(set) var filed: [Shelf] = []
    @Published private(set) var droppedCount = 0
    /// Everything done, newest first, kept after its screenshot is deleted.
    @Published private(set) var doneLog: [DoneEntry] = []
    /// Screenshots waiting to be sorted (near-duplicates count once).
    @Published private(set) var toSort = 0
    @Published private(set) var results: [ScreenshotItem] = []
    /// A fixed "now" for design snapshots, so the weekend plan doesn't depend on the day CI runs.
    var fixedNow: Date?
    /// How many times today's pick has been swapped today (Premium).
    @Published private(set) var reroll = PickReroll.today()
    @Published var query = "" {
        didSet { scheduleSearch() }
    }

    /// Premium: search by meaning as well as by keyword ("that cosy place", "the thing in March").
    var meaningSearchEnabled = false {
        didSet { if meaningSearchEnabled != oldValue { scheduleSearch() } }
    }

    private let database: AppDatabase?
    private var searchTask: Task<Void, Never>?
    private let meaning = MeaningSearch()

    init(database: AppDatabase?) {
        self.database = database
    }

    var isEmpty: Bool {
        score.total == 0 && comingUp.isEmpty && shelves.isEmpty && filed.isEmpty
    }

    /// Something is typed in the search box, not just spaces.
    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reload(now: Date = Date()) {
        guard let database else { return }
        score = (try? database.score()) ?? score
        comingUp = (try? database.comingUp(now: now)) ?? []
        let grouped = (try? database.stillWant()) ?? [:]
        shelves = Self.shelves(grouped.filter { $0.key.isIntention })
        filed = Self.shelves((try? database.filed()) ?? [:])
        droppedCount = (try? database.dropped().count) ?? 0
        doneLog = (try? database.doneLog()) ?? []
        toSort = (try? database.triageDeck(limit: .max).count) ?? 0
        reroll = PickReroll.today(now: now)
        // What was found may have been decided or deleted since.
        scheduleSearch()
    }

    /// Kept things regrouped by occasion (free, date night, rainy day…), for Kept's shelves.
    var smartShelves: [(SmartShelf, [ScreenshotItem])] {
        SmartShelf.group(shelves.flatMap(\.items))
    }

    /// Another pick (or another weekend), for Premium.
    func pickAnother() {
        reroll = PickReroll.increment()
    }

    /// Kept recipes, for this week's shop.
    var keptRecipes: [ScreenshotItem] {
        shelves.first { $0.category == .recipe }?.items ?? []
    }

    /// The fullest shelf first.
    private static func shelves(_ grouped: [ItemCategory: [ScreenshotItem]]) -> [Shelf] {
        grouped
            .filter { !$0.value.isEmpty }
            .map { Shelf(category: $0.key, items: $0.value) }
            .sorted { $0.items.count == $1.items.count ? $0.category.rawValue < $1.category.rawValue : $0.items.count > $1.items.count }
    }

    /// A Home with things on it, for design snapshots.
    static func sample() -> HomeModel {
        let model = HomeModel(database: nil)
        model.score = Score(done: 6, total: 23)
        model.comingUp = SampleData.comingUp
        model.shelves = SampleData.shelves.map { Shelf(category: $0.0, items: $0.1) }
        model.filed = SampleData.filed.map { Shelf(category: $0.0, items: $0.1) }
        model.toSort = 24
        model.droppedCount = 12
        model.doneLog = SampleData.doneLog
        return model
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let database else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let found: [ScreenshotItem]
            if meaningSearchEnabled {
                found = (try? await meaning.search(query, in: database)) ?? []
            } else {
                found = (try? database.search(query)) ?? []
            }
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    /// Home with nothing left to sort, for design snapshots: "All sorted" and the pick.
    static func sampleSorted() -> HomeModel {
        let model = sample()
        model.toSort = 0
        model.fixedNow = SampleData.tuesday
        return model
    }

    /// "All sorted" on a Friday evening: the weekend plan.
    static func sampleWeekend() -> HomeModel {
        let model = sample()
        model.toSort = 0
        model.fixedNow = SampleData.tuesday.addingTimeInterval(3 * 86_400 + 9 * 3_600)
        return model
    }

    /// "All sorted" with nothing dated: today's pick.
    static func samplePick() -> HomeModel {
        let model = sample()
        model.toSort = 0
        model.comingUp = []
        model.shelves = model.shelves.filter { $0.category != .event }
        model.fixedNow = SampleData.tuesday.addingTimeInterval(10 * 3_600)
        return model
    }
}
