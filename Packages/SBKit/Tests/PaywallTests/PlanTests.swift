import Testing
@testable import Paywall

@Suite struct PlanTests {
    @Test func annualIsTheDefaultUnlessTheExperimentSaysOtherwise() {
        #expect(PaywallExperiment.defaultPlan(metadata: [:]) == .annual)
        #expect(PaywallExperiment.defaultPlan(metadata: ["default_plan": "weekly"]) == .weekly)
        #expect(PaywallExperiment.defaultPlan(metadata: ["default_plan": "nonsense"]) == .annual)
    }

    @Test func trialTermsAreClear() {
        let annual = PlanOption(kind: .annual, price: "$39.99", trialDays: 7)
        #expect(annual.terms == "Free for 7 days, then $39.99 a year. Cancel any time in Settings, at least a day before it renews.")
        #expect(annual.actionTitle == "Start my free week")
        #expect(PlanOption(kind: .lifetime, price: "$79.99").priceLine == "$79.99 once")
    }
}
