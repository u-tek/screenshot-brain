import Core
import DesignSystem
import Store
import SwiftUI

/// Shelves that build themselves from what's been kept: free things, date nights, rainy days.
/// Free users get the first two that have something on them; the rest show a lock and ask for
/// the paywall.
struct SmartShelvesSection: View {
    let shelves: [(SmartShelf, [ScreenshotItem])]
    let isPremium: Bool
    var palette: LightPalette = .sampleTopScreenshots
    let onLocked: () -> Void
    let open: (SmartShelf) -> Void

    /// How many shelves a free user can open.
    static let freeShelfCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SBLabel("Shelves")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SBSpace.gap), GridItem(.flexible(), spacing: SBSpace.gap)], spacing: SBSpace.gap) {
                ForEach(shelves.indices, id: \.self) { index in
                    tile(shelf: shelves[index].0, count: shelves[index].1.count, index: index)
                }
            }
        }
    }

    private func tile(shelf: SmartShelf, count: Int, index: Int) -> some View {
        let locked = !isPremium && index >= Self.freeShelfCount
        return Button {
            if locked { onLocked() } else { open(shelf) }
        } label: {
            LightTile(
                shelf.title,
                detail: locked ? "PREMIUM" : "\(count) KEPT",
                palette: index.isMultiple(of: 2) ? palette : palette.reversed
            )
            .overlay(alignment: .topTrailing) {
                if locked {
                    SBIconView(.system("lock"), size: 14)
                        .foregroundStyle(SBColor.ink)
                        .padding(16)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(SBPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(locked ? "\(shelf.title), premium, locked" : "\(shelf.title), \(count) kept"))
        .accessibilityHint(Text(locked ? "Shows the plans" : "Opens the shelf"))
    }
}

/// One smart shelf's items, as rows. Modelled on `CategoryScreen`.
struct SmartShelfScreen: View {
    @Environment(\.dismiss) private var dismiss
    let shelf: SmartShelf
    let items: [ScreenshotItem]

    var body: some View {
        VStack(spacing: 0) {
            SBNavHeader(title: shelf.title, onLeading: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SBLabel("\(items.count) kept")
                    VStack(spacing: SBSpace.gap) {
                        ForEach(items) { item in
                            NavigationLink(value: HomeRoute.item(item.id)) {
                                ItemRow(item: item)
                            }
                            .buttonStyle(SBPressStyle())
                        }
                    }
                }
                .padding(.horizontal, SBSpace.gutter)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .sbScreen()
        .toolbar(.hidden, for: .navigationBar)
        // The last one was decided: nothing left to show here.
        .onChange(of: items.isEmpty) { isEmpty in
            if isEmpty { dismiss() }
        }
    }
}
