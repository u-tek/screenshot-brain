import Core
import EventKit
import EventKitUI
import MapKit
import Store
import SwiftUI
import UIKit

/// Apple's own event editor, prefilled. On iOS 17 and later it needs no calendar permission:
/// the user saves the event themselves. On iOS 16 it needs access first (see `CalendarAccess`).
public struct EventEditor: UIViewControllerRepresentable {
    private let draft: EventDraft
    private let onFinish: (Bool) -> Void

    public init(draft: EventDraft, onFinish: @escaping (Bool) -> Void) {
        self.draft = draft
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.url = draft.url
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    public final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        public func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action == .saved)
        }
    }
}

public enum CalendarAccess {
    /// Whether the event editor can be shown. Always on iOS 17+; asks on iOS 16.
    public static func prepare() async -> Bool {
        if #available(iOS 17.0, *) {
            return true
        }
        return (try? await EKEventStore().requestAccess(to: .event)) ?? false
    }
}

public enum MapsAction {
    /// Looks the place up and opens it in Maps; falls back to a Maps search.
    @MainActor
    public static func open(_ item: ScreenshotItem) async {
        guard let query = MapsQuery.query(for: item) else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let response = try? await MKLocalSearch(request: request).start(), let place = response.mapItems.first {
            place.openInMaps()
            return
        }
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components?.url {
            await UIApplication.shared.open(url)
        }
    }
}

/// The system share sheet.
public struct ActivitySheet: UIViewControllerRepresentable {
    private let items: [Any]
    private let onFinish: (Bool) -> Void

    public init(items: [Any], onFinish: @escaping (Bool) -> Void = { _ in }) {
        self.items = items
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
