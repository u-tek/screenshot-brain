import Core
import Foundation
import Store
import WidgetCore
import WidgetKit

struct SavedThingEntry: TimelineEntry {
    let date: Date
    let card: WidgetCard
    let score: Score

    /// The database couldn't be read: the same "screenshot something" card, which opens the app.
    static var openTheApp: SavedThingEntry {
        SavedThingEntry(date: Date(), card: .screenshotSomething, score: Score(done: 0, total: 0))
    }

    static let placeholder = SavedThingEntry(
        date: Date(),
        card: .item(WidgetItem(id: "placeholder", title: "That ramen place", category: .place, detail: "Saved 3 weeks ago", isUnreviewed: false, thumbnailName: nil, lightName: WidgetLight.fileName(for: .place))),
        score: Score(done: 6, total: 23)
    )
}

/// Reads the shared database the app and the background scan keep up to date. Never reads a
/// full screenshot: only the small thumbnails and lights the app pre-renders.
struct SavedThingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SavedThingEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SavedThingEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        // A snapshot only looks: it mustn't mark anything surfaced or touch the schedule.
        let plan = WidgetStore.timeline(commit: false)
        completion(plan.entries.first.map(SavedThingEntry.init) ?? .openTheApp)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SavedThingEntry>) -> Void) {
        let plan = WidgetStore.timeline()
        let entries = plan.entries.map(SavedThingEntry.init)
        completion(Timeline(entries: entries.isEmpty ? [.openTheApp] : entries, policy: .after(plan.reloadAt)))
    }
}

/// The score alone. No side effects: only the saved-thing widget schedules and surfaces items.
struct ScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> SavedThingEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SavedThingEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SavedThingEntry>) -> Void) {
        // The app and the widget's buttons reload this whenever the score changes.
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> SavedThingEntry {
        let score = (try? WidgetStore.database?.score()) ?? nil
        let card: WidgetCard = WidgetAccess.current() == .locked ? .locked : .screenshotSomething
        return SavedThingEntry(date: Date(), card: card, score: score ?? Score(done: 0, total: 0))
    }
}

extension SavedThingEntry {
    init(_ plan: WidgetEntryPlan) {
        self.init(date: plan.date, card: plan.card, score: plan.score)
    }
}

/// The extension's view of the shared container.
enum WidgetStore {
    static let database: AppDatabase? = try? AppDatabase.openShared()

    static func timeline(now: Date = Date(), commit: Bool = true) -> (entries: [WidgetEntryPlan], reloadAt: Date) {
        guard let database else {
            // Can't read the shared database: say so with a real state, and try again soon.
            let card: WidgetCard = WidgetAccess.current(now: now) == .locked ? .locked : .screenshotSomething
            return ([WidgetEntryPlan(date: now, card: card, score: Score(done: 0, total: 0))], now.addingTimeInterval(3_600))
        }
        return WidgetTimeline(database: database, defaults: AppGroup.defaults()).build(access: .current(now: now), now: now, commit: commit)
    }

    static func url(in directory: AppGroup.Directory, name: String?) -> URL? {
        guard let name, let base = try? AppGroup.directory(directory) else { return nil }
        let url = base.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Links back into the app.
enum DeepLink {
    static func item(_ id: String) -> URL {
        URL(string: "screenshotbrain://item/\(id)")!
    }

    static let recap = URL(string: "screenshotbrain://recap")!
    static let paywall = URL(string: "screenshotbrain://paywall")!
    static let home = URL(string: "screenshotbrain://home")!
}
