import Core
import Foundation
import RevenueCat
import WidgetKit

/// Premium through RevenueCat: one entitlement, three ways to pay (annual with a 7-day trial,
/// weekly, lifetime). Shares the result with the widget through the App Group.
@MainActor
public final class PurchaseService: ObservableObject {
    /// The entitlement every product unlocks, as set up in RevenueCat.
    public static let entitlementID = "premium"

    @Published public private(set) var plans: [PlanOption] = []
    @Published public private(set) var defaultPlan: PlanOption.Kind = .annual
    /// The last attempt to load plans failed (or found none): the paywall offers a retry.
    @Published public private(set) var plansFailed = false
    @Published public private(set) var isPremium: Bool
    /// False when no RevenueCat key is configured: the paywall shows, purchases can't happen.
    public let isAvailable: Bool
    private var packages: [PlanOption.Kind: Package] = [:]
    private var listener: Task<Void, Never>?

    public init(apiKey: String?, appUserID: String?) {
        isAvailable = apiKey != nil
        isPremium = Entitlement.isPremium() ?? false
        if let apiKey, !Purchases.isConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
        }
    }

    /// Loads the plans and starts following purchase changes.
    public func start() async {
        guard isAvailable else { return }
        if listener == nil {
            listener = Task { [weak self] in
                for await info in Purchases.shared.customerInfoStream {
                    self?.apply(info)
                }
            }
        }
        await loadPlans()
    }

    public func loadPlans() async {
        guard isAvailable else { return }
        let offering: Offering
        do {
            guard let current = try await Purchases.shared.offerings().current else {
                plansFailed = true
                return
            }
            offering = current
        } catch {
            plansFailed = true
            return
        }
        plansFailed = false
        var options: [PlanOption] = []
        var found: [PlanOption.Kind: Package] = [:]
        let weekly = offering.weekly
        if let annual = offering.annual {
            found[.annual] = annual
            // The trial is only promised to someone who can still have it.
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: annual.storeProduct)
            options.append(PlanOption(
                kind: .annual,
                price: annual.storeProduct.localizedPriceString,
                trialDays: eligibility == .eligible ? Self.trialDays(annual.storeProduct) : nil,
                weeklyEquivalent: annual.storeProduct.localizedPricePerWeek.map { "\($0) a week" }
            ))
        }
        if let weekly {
            found[.weekly] = weekly
            options.append(PlanOption(kind: .weekly, price: weekly.storeProduct.localizedPriceString))
        }
        if let lifetime = offering.lifetime {
            found[.lifetime] = lifetime
            options.append(PlanOption(kind: .lifetime, price: lifetime.storeProduct.localizedPriceString))
        }
        packages = found
        plans = options
        defaultPlan = PaywallExperiment.defaultPlan(metadata: offering.metadata)
    }

    /// How a purchase ended.
    public enum PurchaseOutcome: Sendable {
        case purchased
        case cancelled
        /// Neither: Ask to Buy, or a payment still being approved. Premium arrives when it is.
        case pending
    }

    public func purchase(_ kind: PlanOption.Kind) async throws -> PurchaseOutcome {
        guard let package = packages[kind] else { return .cancelled }
        let result = try await Purchases.shared.purchase(package: package)
        apply(result.customerInfo)
        if result.userCancelled { return .cancelled }
        return isPremium ? .purchased : .pending
    }

    public func restore() async throws -> Bool {
        // Without a RevenueCat key (the sideload build), Purchases.shared would trap.
        guard isAvailable else { return isPremium }
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
        return isPremium
    }

    /// Ties purchases to the Sign in with Apple user, so they follow the account to a new phone.
    public func logIn(appUserID: String) async {
        guard isAvailable, let result = try? await Purchases.shared.logIn(appUserID) else { return }
        apply(result.customerInfo)
    }

    public func refresh() async {
        guard isAvailable, let info = try? await Purchases.shared.customerInfo() else { return }
        apply(info)
    }

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[Self.entitlementID]
        let active = entitlement?.isActive == true
        let trialEnds = entitlement?.periodType == .trial ? entitlement?.expirationDate : nil
        // Nil for lifetime. The widget locks itself if this passes without a refresh.
        let expiresAt = active ? entitlement?.expirationDate : nil
        // A trial that ran out without becoming a purchase.
        let trialEnded = entitlement?.periodType == .trial && !active
        let defaults = AppGroup.defaults()
        let changed = active != isPremium || Entitlement.isPremium() != active || Entitlement.trialEndsAt() != trialEnds
            || (defaults?.object(forKey: Self.expiryKey) as? Date) != expiresAt
            || defaults?.bool(forKey: Self.trialEndedKey) != trialEnded
        isPremium = active
        Entitlement.setPremium(active)
        Entitlement.setTrialEndsAt(trialEnds)
        if let expiresAt {
            defaults?.set(expiresAt, forKey: Self.expiryKey)
        } else {
            defaults?.removeObject(forKey: Self.expiryKey)
        }
        defaults?.set(trialEnded, forKey: Self.trialEndedKey)
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The App Group keys the widget reads (`WidgetAccess.expiryKey` and `trialEndedKey`; Paywall
    /// and WidgetCore can't import each other, so the strings are repeated).
    static let expiryKey = "premium.expiresAt"
    static let trialEndedKey = "premium.trialEnded"

    private static func trialDays(_ product: StoreProduct) -> Int? {
        guard let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial else { return nil }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }
}
