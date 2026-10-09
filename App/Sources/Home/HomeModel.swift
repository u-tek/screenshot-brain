import Core
import Foundation
import Store

/// What Home and Kept show: how many screenshots are waiting to be sorted, the score, what's
/// coming up, what's still wanted, and search.
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
    @Published private(set) var droppedCount = 0
    /// Screenshots waiting to be sorted (near-duplicates count once).
    @Published private(set) var toSort = 0
    @Published private(set) var results: [ScreenshotItem] = []
    @Published var query = "" {
        didSet { scheduleSearch() }
    }

    private let database: AppDatabase?
    private var searchTask: Task<Void, Never>?

    init(database: AppDatabase?) {
        self.database = database
    }

    var isEmpty: Bool {
        score.total == 0 && comingUp.isEmpty && shelves.isEmpty
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
        shelves = grouped
            .filter { $0.key.isIntention && !$0.value.isEmpty }
            .map { Shelf(category: $0.key, items: $0.value) }
            .sorted { $0.items.count == $1.items.count ? $0.category.rawValue < $1.category.rawValue : $0.items.count > $1.items.count }
        droppedCount = (try? database.dropped().count) ?? 0
        toSort = (try? database.triageDeck(limit: .max).count) ?? 0
        // What was found may have been decided or deleted since.
        scheduleSearch()
    }

    /// A Home with things on it, for design snapshots.
    static func sample() -> HomeModel {
        let model = HomeModel(database: nil)
        model.score = Score(done: 6, total: 23)
        model.comingUp = SampleData.comingUp
        model.shelves = SampleData.shelves.map { Shelf(category: $0.0, items: $0.1) }
        model.toSort = 24
        model.droppedCount = 12
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
            results = (try? database.search(query)) ?? []
        }
    }
}
