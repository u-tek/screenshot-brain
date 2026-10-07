import Foundation

/// Whether the user has premium (a subscription, its free trial, or lifetime), shared with the
/// widget through the App Group. Written by the paywall whenever RevenueCat reports a change.
public enum Entitlement {
    private static let key = "premium.active"

    /// Nil until a purchase state has been read for the first time.
    public static func isPremium(_ defaults: UserDefaults? = AppGroup.defaults()) -> Bool? {
        guard let defaults, defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    public static func setPremium(_ isPremium: Bool, defaults: UserDefaults? = AppGroup.defaults()) {
        defaults?.set(isPremium, forKey: key)
    }
}

extension Entitlement {
    private static let trialKey = "premium.trialEndsAt"

    /// When the free trial ends, while one is running. For the day-5 reminder.
    public static func trialEndsAt(_ defaults: UserDefaults? = AppGroup.defaults()) -> Date? {
        defaults?.object(forKey: trialKey) as? Date
    }

    public static func setTrialEndsAt(_ date: Date?, defaults: UserDefaults? = AppGroup.defaults()) {
        defaults?.set(date, forKey: trialKey)
    }
}
