import Actions
import Core
import DesignSystem
import Media
import Store
import SwiftUI
import UIKit

/// Cook mode: a recipe's steps one at a time, in big text, with the screen kept awake. Swipe or
/// tap Next and Back; the last step ends in "Done cooking".
struct CookModeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var stepSize: CGFloat = 30
    @State private var index = 0
    let item: ScreenshotItem
    /// The last step's "Done cooking": the parent marks the item done.
    var onDone: () -> Void = {}

    private var steps: [String] { RecipeSteps.steps(in: item.extractedText ?? "") }

    var body: some View {
        let steps = steps
        VStack(spacing: 0) {
            SBNavHeader(
                title: steps.isEmpty ? item.title ?? "Cook it" : "Step \(index + 1) of \(steps.count)",
                leading: .x,
                leadingLabel: "Close",
                onLeading: { dismiss() }
            )
            if steps.isEmpty {
                noSteps
            } else {
                stepPages(steps)
                controls(count: steps.count)
            }
        }
        .sbScreen(.calm)
        // Hands are messy: the screen mustn't lock mid-step.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func stepPages(_ steps: [String]) -> some View {
        TabView(selection: $index) {
            ForEach(steps.indices, id: \.self) { position in
                ScrollView {
                    Text(steps[position])
                        .font(.system(size: stepSize, weight: .regular))
                        .foregroundStyle(SBColor.ink)
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SBSpace.gutter + 8)
                        .padding(.vertical, 24)
                        .accessibilityLabel(Text("Step \(position + 1) of \(steps.count). \(steps[position])"))
                }
                .tag(position)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    private func controls(count: Int) -> some View {
        let isLast = index >= count - 1
        return VStack(spacing: 12) {
            if isLast {
                StartSortingButton(title: "Done cooking") {
                    Haptics.done()
                    onDone()
                    dismiss()
                }
            }
            HStack(spacing: SBSpace.gap) {
                if index > 0 {
                    SBSegButton("Back", icon: .back) { go(to: index - 1) }
                }
                if !isLast {
                    SBSegButton("Next", icon: .arrow, isPrimary: true) { go(to: index + 1) }
                }
            }
            .padding(.horizontal, SBSpace.gutter)
        }
        .padding(.bottom, SBSpace.gutter)
    }

    private func go(to position: Int) {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : SBMotion.settle) { index = position }
    }

    /// Nothing that looks like steps: say so, and show the whole screenshot.
    private var noSteps: some View {
        VStack(spacing: 12) {
            MistHeadline("Couldn't find the steps in this one.", size: 28)
            MistBody("Here's the whole screenshot instead.")
            AssetImage(item.assetLocalID, maxPixelSize: 1600, allowsNetwork: true, contentMode: .fit, backdrop: true)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.shot, style: .continuous))
                .padding(.top, 8)
                .padding(.bottom, SBSpace.gutter)
                .accessibilityLabel(Text("Your recipe screenshot"))
        }
        .padding(.horizontal, SBSpace.gutter)
        .frame(maxHeight: .infinity)
    }
}
