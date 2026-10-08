import Core
import DesignSystem
import SwiftUI

/// The paywall: the lens over a field of light, the widget being ticked beside it, the plans in
/// frosted cards (the selected one lit by the accent), and the action bar as the purchase button.
/// Restore is always on screen, and so are the trial terms.
public struct PaywallView: View {
    @ObservedObject private var purchases: PurchaseService
    private let palette: LightPalette
    private let privacyPolicy: URL?
    private let onClose: () -> Void
    private let onPurchased: () -> Void
    @State private var selection: PlanOption.Kind?
    @State private var isBusy = false
    @State private var message: String?
    @Environment(\.openURL) private var openURL

    /// Apple's standard licence agreement.
    private static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    public init(purchases: PurchaseService, palette: LightPalette, privacyPolicy: URL?, onClose: @escaping () -> Void, onPurchased: @escaping () -> Void) {
        self.purchases = purchases
        self.palette = palette
        self.privacyPolicy = privacyPolicy
        self.onClose = onClose
        self.onPurchased = onPurchased
    }

    private var plans: [PlanOption] {
        purchases.plans.isEmpty ? PlanOption.placeholders : purchases.plans
    }

    private var selected: PlanOption {
        let kind = selection ?? purchases.defaultPlan
        return plans.first { $0.kind == kind } ?? plans[0]
    }

    public var body: some View {
        GeometryReader { proxy in
            // Phones without a notch (iPhone 8, SE): about 650 points to work with.
            let compact = proxy.size.height < 700
            ZStack {
                // The sweep passes behind the lens in the hero.
                LightField(.sweep(palette).mirrored(), drifts: true)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button(action: restore) {
                            Chip("Restore purchases")
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(action: onClose) {
                            Chip("Not now", closable: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Hero(palette: palette, compact: compact)
                        .frame(height: compact ? 112 : 200)
                        .padding(.vertical, compact ? 2 : 12)

                    VStack(alignment: .leading, spacing: 8) {
                        SmallLabel("Screenshot Brain Premium")
                        MistHeadline("Keep it all **on your home screen.**", size: compact ? 26 : 30, alignment: .leading)
                        SmallLabel("The widget on your home and Lock Screen, the all-time Reveal and full monthly stats. Everything else stays free.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    VStack(spacing: 8) {
                        ForEach(plans) { plan in
                            PlanCard(plan: plan, isSelected: plan.kind == selected.kind, palette: palette) {
                                Haptics.selection()
                                withAnimation(SBMotion.snappy) { selection = plan.kind }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Text(message ?? selected.terms)
                        .font(SBFont.body(12))
                        .foregroundStyle(SBColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .padding(.vertical, compact ? 6 : 10)

                    ActionBar(isBusy ? "One moment…" : selected.actionTitle, palette: palette, action: buy)
                        .padding(.horizontal, 12)
                        .disabled(isBusy)

                    HStack(spacing: 16) {
                        Button("Terms") { openURL(Self.terms) }
                        if let privacyPolicy {
                            Button("Privacy") { openURL(privacyPolicy) }
                        }
                    }
                    .font(SBFont.body(12))
                    .foregroundStyle(SBColor.inkSecondary)
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .task {
            await purchases.start()
        }
    }

    private func buy() {
        guard purchases.isAvailable else {
            message = "Purchases aren't set up in this build."
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if try await purchases.purchase(selected.kind) {
                    Haptics.success()
                    onPurchased()
                }
            } catch {
                message = "That didn't go through. Nothing was charged."
            }
        }
    }

    private func restore() {
        guard purchases.isAvailable else {
            message = "Purchases aren't set up in this build."
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            if (try? await purchases.restore()) == true {
                Haptics.success()
                onPurchased()
            } else {
                message = "Nothing to restore on this Apple ID."
            }
        }
    }
}

extension PlanOption {
    /// Shown while the App Store's prices load (and in design snapshots).
    public static let placeholders = [
        PlanOption(kind: .annual, price: "$39.99", trialDays: 7, weeklyEquivalent: "$0.77 a week"),
        PlanOption(kind: .weekly, price: "$4.99"),
        PlanOption(kind: .lifetime, price: "$79.99"),
    ]
}

private struct PlanCard: View {
    let plan: PlanOption
    let isSelected: Bool
    let palette: LightPalette
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? SBColor.accent : Color.clear)
                    .overlay(Circle().strokeBorder(isSelected ? Color.clear : SBColor.inkSecondary.opacity(0.4), lineWidth: 1))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(SBFont.body(16, weight: .semibold))
                            .foregroundStyle(SBColor.ink)
                        if let trialDays = plan.trialDays {
                            Text("\(trialDays) DAYS FREE")
                                .font(SBFont.mono(10))
                                .foregroundStyle(SBColor.accent)
                        }
                    }
                    if let weekly = plan.weeklyEquivalent {
                        Text(weekly)
                            .font(SBFont.body(12))
                            .foregroundStyle(SBColor.inkSecondary)
                    }
                }
                Spacer()
                Text(plan.priceLine)
                    .font(SBFont.body(15))
                    .foregroundStyle(SBColor.ink)
            }
            .padding(.horizontal, 18)
            .frame(height: 60)
            .background {
                if isSelected {
                    LightField(.bloom(palette), ground: false, grain: 0)
                        .opacity(0.5)
                        .clipShape(shape)
                }
            }
            .sbGlass(in: shape)
            .overlay(shape.strokeBorder(SBColor.accent.opacity(isSelected ? 0.7 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(plan.title), \(plan.priceLine)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The lens over the light, with the widget being ticked beside it.
private struct Hero: View {
    let palette: LightPalette
    let compact: Bool

    var body: some View {
        HStack(spacing: -24) {
            if !compact {
                GlassLens(diameter: 150)
                    .zIndex(1)
            }
            TickingWidget()
                .frame(width: compact ? 300 : 250, height: compact ? 112 : 128)
        }
    }
}

/// A medium widget ticking things off: ✓ pulses, the card lifts away, the next arrives.
struct TickingWidget: View {
    private static let items: [(category: ItemCategory, title: String, detail: String)] = [
        (.event, "Mallrat at the Enmore", "FRIDAY"),
        (.place, "Ramen Ikkyu", "SAVED 3 WEEKS AGO"),
        (.recipe, "Crispy chilli noodles", "SAVED 2 MONTHS AGO"),
    ]

    @State private var index = 0
    @State private var ticking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lightIsStill) private var lightIsStill

    var body: some View {
        let item = Self.items[index]
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        HStack(spacing: 10) {
            LightField(.glow(.category(item.category)), grain: 0.04)
                .frame(width: 62)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBColor.ink)
                    .lineLimit(1)
                Text(item.detail)
                    .font(SBFont.mono(9))
                    .foregroundStyle(SBColor.inkSecondary)
                Spacer(minLength: 4)
                HStack {
                    DropMark(size: 28)
                    Spacer()
                    DoneMark(size: 28)
                        .scaleEffect(ticking ? 1.25 : 1)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(10)
        .background {
            LightField(.bloom(.category(item.category)).shifted(down: -0.1), grain: 0.04)
                .clipShape(shape)
        }
        .overlay(shape.strokeBorder(SBColor.warm(0.14), lineWidth: 1))
        .offset(y: ticking ? -14 : 0)
        .opacity(ticking ? 0 : 1)
        .accessibilityElement()
        .accessibilityLabel(Text("The widget, ticking off saved things"))
        .task {
            guard !reduceMotion, !lightIsStill else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(.easeOut(duration: 0.35)) { ticking = true }
                try? await Task.sleep(nanoseconds: 380_000_000)
                index = (index + 1) % Self.items.count
                withAnimation(SBMotion.settle) { ticking = false }
            }
        }
    }
}
