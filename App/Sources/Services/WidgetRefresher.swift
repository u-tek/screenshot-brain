import WidgetKit

/// Tells the widgets that items changed. The widget extension reads the shared database itself.
enum WidgetRefresher {
    @MainActor
    static func refresh(services: AppServices) async {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
