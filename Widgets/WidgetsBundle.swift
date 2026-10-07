import SwiftUI
import WidgetKit

@main
struct ScreenshotBrainWidgets: WidgetBundle {
    var body: some Widget {
        SavedThingWidget()
        ScoreWidget()
    }
}

/// The hero: a saved thing, with Keep, Done and Drop on iOS 17 and later.
struct SavedThingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.savedThing, provider: SavedThingProvider()) { entry in
            SavedThingView(entry: entry)
        }
        .configurationDisplayName("Saved things")
        .description("The things you saved, one at a time. Tick them off from here.")
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}

/// The score on the Lock Screen.
struct ScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.score, provider: ScoreProvider()) { entry in
            ScoreAccessoryView(entry: entry)
        }
        .configurationDisplayName("Score")
        .description("How many of the things you kept are done.")
        .supportedFamilies([.accessoryRectangular])
    }
}

enum WidgetKind {
    static let savedThing = "SavedThing"
    static let score = "Score"
}
