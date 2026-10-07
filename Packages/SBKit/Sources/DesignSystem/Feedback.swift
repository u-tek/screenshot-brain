import SwiftUI
import UIKit

/// The haptics map. Every haptic in the app comes from here, so they stay consistent.
@MainActor
public enum Haptics {
    /// A light tick as a number counts up.
    public static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }

    /// A firm thud when something is done.
    public static func done() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.9)
    }

    /// A soft tap when something is dropped. Dropping carries no penalty, so it feels light.
    public static func drop() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }

    /// A medium knock when something is kept.
    public static func keep() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
    }

    /// Advancing a story card, picking an answer.
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A finished moment: the Reveal's last card, the score.
    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Named motion. Springs everywhere; nothing linear except the slow drift of light.
public enum SBMotion {
    /// Most transitions: settles without bounce.
    public static var settle: Animation { .spring(response: 0.55, dampingFraction: 0.86) }
    /// Small, quick responses: chips, toggles, marks.
    public static var snappy: Animation { .spring(response: 0.3, dampingFraction: 0.78) }
    /// Large surfaces arriving: Reveal cards, sheets.
    public static var reveal: Animation { .spring(response: 0.75, dampingFraction: 0.84) }
    /// Cards flung off the triage deck.
    public static var fling: Animation { .spring(response: 0.42, dampingFraction: 0.9) }
    /// How long a Reveal number takes to count up.
    public static let countUpDuration: Double = 1.1
    /// One loop of the light's drift.
    public static let driftPeriod: Double = 12
}

extension EnvironmentValues {
    /// Freezes the light's drift, for snapshots and previews.
    public var lightIsStill: Bool {
        get { self[LightIsStillKey.self] }
        set { self[LightIsStillKey.self] = newValue }
    }
}

private struct LightIsStillKey: EnvironmentKey {
    static let defaultValue = false
}
