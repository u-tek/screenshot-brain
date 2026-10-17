import Actions
import Core
import DesignSystem
import Store
import SwiftUI
import UIKit

/// This week's shop: the recipes kept, a toggle on each, and one shopping list merged from the
/// ones picked. Premium; whoever opens it does the gating.
struct WeeklyShopScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var note: String?
    private let recipes: [ScreenshotItem]

    /// - Parameter items: Any items; only kept recipes are listed.
    init(items: [ScreenshotItem]) {
        recipes = items.filter { $0.category == .recipe && $0.state == .stillWant }
    }

    /// The picked recipes' ingredient lines, each once, in the order they were read.
    private var list: [String] {
        var seen: Set<String> = []
        var merged: [String] = []
        for recipe in recipes where picked.contains(recipe.id) {
            for line in Ingredients.lines(in: recipe.extractedText ?? "") {
                let key = line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
                if seen.insert(key).inserted {
                    merged.append(line)
                }
            }
        }
        return merged
    }

    var body: some View {
        let list = list
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                SBNavHeader(title: "This week's shop", onLeading: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if recipes.isEmpty {
                            empty
                        } else {
                            SBLabel("Recipes")
                            VStack(spacing: SBSpace.gap) {
                                ForEach(recipes) { recipe in
                                    row(recipe)
                                }
                            }
                            shoppingList(list)
                        }
                    }
                    .padding(.horizontal, SBSpace.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            if let note {
                SBToast(note)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .sbScreen(.calm)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            MistHeadline("Pick a recipe or two you kept.", size: 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// A recipe with a tick: tap anywhere on the row.
    private func row(_ recipe: ScreenshotItem) -> some View {
        let isPicked = picked.contains(recipe.id)
        let kind = SBKind(recipe.category)
        return Button {
            Haptics.selection()
            withAnimation(SBMotion.snappy) {
                if isPicked { picked.remove(recipe.id) } else { picked.insert(recipe.id) }
            }
        } label: {
            HStack(spacing: 14) {
                Text(recipe.title ?? "A recipe you saved")
                    .sbText(.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().strokeBorder(isPicked ? kind.core : SBColor.line, lineWidth: 1.5)
                    if isPicked {
                        Circle().fill(kind.core)
                        SBIconView(.check, size: 14)
                            .foregroundStyle(SBColor.ground)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: SBRadius.cell, style: .continuous).fill(SBColor.surface))
            .overlay(RoundedRectangle(cornerRadius: SBRadius.cell, style: .continuous).strokeBorder(SBColor.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: SBRadius.cell, style: .continuous))
        }
        .buttonStyle(SBPressStyle())
        .accessibilityLabel(Text(recipe.title ?? "A recipe you saved"))
        .accessibilityValue(Text(isPicked ? "In this week's shop" : "Not picked"))
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    @ViewBuilder
    private func shoppingList(_ list: [String]) -> some View {
        if list.isEmpty {
            MistBody(picked.isEmpty ? "Pick a recipe or two you kept." : "No ingredients found in those.", alignment: .leading)
        } else {
            let text = list.joined(separator: "\n")
            SBLabel("Shopping list · \(list.count)")
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(list, id: \.self) { line in
                    Text(line)
                        .sbText(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: SBSpace.gap) {
                SBScenarioButton("Copy list", icon: .system("doc.on.doc"), color: SBKind.recipes.core) {
                    UIPasteboard.general.string = text
                    Haptics.success()
                    flash(list.count == 1 ? "Copied 1 item." : "Copied \(list.count) items.")
                }
                ShareLink(item: text) {
                    SBScenarioLabel("Share list", icon: .send, color: SBKind.recipes.core)
                }
                .buttonStyle(SBPressStyle())
                .accessibilityLabel(Text("Share list"))
            }
            .padding(.top, 8)
        }
    }

    private func flash(_ text: String) {
        withAnimation(SBMotion.snappy) { note = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(SBMotion.settle) {
                if note == text { note = nil }
            }
        }
    }
}
