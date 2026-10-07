import Foundation

/// One way to pay. Prices come from the App Store through RevenueCat, already localised.
public struct PlanOption: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case annual
        case weekly
        case lifetime
    }

    public var kind: Kind
    /// "$39.99"
    public var price: String
    /// Days free before the first payment, if the plan has a trial.
    public var trialDays: Int?
    /// "$0.77 a week", to set the annual plan against the weekly one.
    public var weeklyEquivalent: String?

    public init(kind: Kind, price: String, trialDays: Int? = nil, weeklyEquivalent: String? = nil) {
        self.kind = kind
        self.price = price
        self.trialDays = trialDays
        self.weeklyEquivalent = weeklyEquivalent
    }

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .annual: "Yearly"
        case .weekly: "Weekly"
        case .lifetime: "Lifetime"
        }
    }

    public var priceLine: String {
        switch kind {
        case .annual: "\(price) a year"
        case .weekly: "\(price) a week"
        case .lifetime: "\(price) once"
        }
    }

    /// The small print, in plain words. Always on screen with the button.
    public var terms: String {
        switch kind {
        case .annual:
            if let trialDays {
                return "Free for \(trialDays) days, then \(price) a year. Cancel any time in Settings, at least a day before it renews."
            }
            return "\(price) a year, renewing yearly. Cancel any time in Settings."
        case .weekly:
            return "\(price) a week, renewing weekly. Cancel any time in Settings."
        case .lifetime:
            return "One payment of \(price). Yours for good."
        }
    }

    public var actionTitle: String {
        switch kind {
        case .annual: trialDays.map { $0 == 7 ? "Start my free week" : "Start \($0) days free" } ?? "Go yearly"
        case .weekly: "Go weekly"
        case .lifetime: "Buy it once"
        }
    }
}

/// The paywall experiment (see docs/EXPERIMENTS.md): each RevenueCat offering says which plan
/// starts selected, in its metadata as {"default_plan": "weekly"}. Annual unless told otherwise.
public enum PaywallExperiment {
    public static let metadataKey = "default_plan"

    public static func defaultPlan(metadata: [String: Any]) -> PlanOption.Kind {
        (metadata[metadataKey] as? String).flatMap(PlanOption.Kind.init(rawValue:)) ?? .annual
    }
}
