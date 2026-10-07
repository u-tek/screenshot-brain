import Foundation
import TelemetryDeck

/// Everything the app ever reports. Event names map one-to-one to the funnel in LAUNCH.md.
public enum AnalyticsEvent: String, CaseIterable, Sendable {
    // First open
    case onboardingStarted = "onboarding.started"
    case signedIn = "onboarding.signedIn"
    case photoAccessFull = "photoAccess.full"
    case photoAccessLimited = "photoAccess.limited"
    case photoAccessDenied = "photoAccess.denied"
    case scanCompleted = "scan.completed"
    case revealStarted = "reveal.started"
    case revealCompleted = "reveal.completed"
    case revealShared = "reveal.shared"
    case triageStarted = "triage.started"
    case triageCompleted = "triage.completed"

    // Widget
    case widgetAdded = "widget.added"
    case widgetKeep = "widget.keep"
    case widgetDone = "widget.done"
    case widgetDrop = "widget.drop"

    // Follow-through
    case recapOpened = "recap.opened"
    case actionCalendar = "action.calendar"
    case actionMaps = "action.maps"
    case actionShop = "action.shop"
    case actionCopyIngredients = "action.copyIngredients"
    case actionSend = "action.send"

    // Money
    case paywallShown = "paywall.shown"
    case trialStarted = "purchase.trialStarted"
    case purchaseCompleted = "purchase.completed"
    case purchaseRestored = "purchase.restored"
}

/// Privacy-first analytics: event counts only.
///
/// Parameters are integers by construction, so screenshot content, extracted text and entity
/// values have no way to reach the analytics service.
public struct Analytics: Sendable {
    public typealias Sink = @Sendable (_ name: String, _ parameters: [String: String]) -> Void

    private let sink: Sink

    public init(sink: @escaping Sink) {
        self.sink = sink
    }

    public func track(_ event: AnalyticsEvent, counts: [String: Int] = [:]) {
        sink(event.rawValue, counts.mapValues { String($0) })
    }

    public static let disabled = Analytics { _, _ in }

    /// TelemetryDeck when an app ID is configured, otherwise disabled.
    @MainActor
    public static func telemetryDeck(appID: String?) -> Analytics {
        guard let appID else { return .disabled }
        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
        return Analytics { name, parameters in
            Task { @MainActor in
                TelemetryDeck.signal(name, parameters: parameters)
            }
        }
    }
}
