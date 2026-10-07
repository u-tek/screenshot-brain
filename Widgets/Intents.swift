import AppIntents
import Core
import Store
import WidgetKit

/// Keep, Done and Drop, straight from the widget (iOS 17 and later). Drop only marks the item
/// dropped: a widget can't show iOS's delete confirmation, so deleting from Photos happens in
/// the app's batch flow.
@available(iOS 17.0, *)
struct KeepItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Still want"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Item")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        WidgetDecision.apply(.stillWant, to: itemID, event: .widgetKeep)
        return .result()
    }
}

@available(iOS 17.0, *)
struct DoneItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Done"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Item")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        WidgetDecision.apply(.done, to: itemID, event: .widgetDone)
        return .result()
    }
}

@available(iOS 17.0, *)
struct DropItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Drop"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Item")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        WidgetDecision.apply(.dropped, to: itemID, event: .widgetDrop)
        return .result()
    }
}

enum WidgetDecision {
    static func apply(_ state: ItemState, to itemID: String, event: AnalyticsEvent) {
        guard let database = WidgetStore.database else { return }
        _ = try? database.decide(state, forItem: itemID)
        Analytics.telemetryDeck(appID: AppConfiguration.main.telemetryDeckAppID).track(event)
        // The interactive widget reloads itself after the intent; the score widget needs telling.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.score)
    }
}
