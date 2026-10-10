import Core
import DesignSystem
import Store
import SwiftUI
import UIKit
import WidgetCore
import WidgetKit

struct SavedThingView: View {
    let entry: SavedThingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetBackground(WidgetLightBackground(name: lightName))
    }

    @ViewBuilder
    private var content: some View {
        switch entry.card {
        case .item(let item):
            if family == .systemSmall {
                SmallItemView(item: item)
                    .widgetURL(DeepLink.item(item.id))
            } else {
                MediumItemView(item: item)
                    .widgetURL(DeepLink.item(item.id))
            }
        case .caughtUp(let waiting):
            MessageCard(
                label: waiting > 0 ? "\(waiting) waiting" : "All caught up",
                headline: waiting > 0 ? "All caught up. **Do your recap.**" : "All caught up. **Nice.**",
                compact: family == .systemSmall
            )
            .widgetURL(DeepLink.recap)
        case .screenshotSomething:
            MessageCard(label: "Your widget", headline: "Screenshot **something you want to do.**", compact: family == .systemSmall)
                .widgetURL(DeepLink.home)
        case .locked:
            LockedCard(compact: family == .systemSmall)
                .widgetURL(DeepLink.paywall)
        }
    }

    private var lightName: String {
        switch entry.card {
        case .item(let item): item.lightName
        case .caughtUp, .screenshotSomething, .locked: WidgetLight.fileName(for: .place)
        }
    }
}

// MARK: - Item

private struct MediumItemView: View {
    let item: WidgetItem

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(name: item.thumbnailName)
                .frame(width: 84)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SBKind(item.category).core)
                        .frame(width: 5, height: 5)
                    Text(CategoryTitle.of(item.category).uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(SBColor.ink)
                }
                .padding(.leading, 14)
                .frame(height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SBColor.ink)
                        .lineLimit(2)
                        .widgetAccentable()
                    Text(item.detail.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(SBColor.ink2)
                    Spacer(minLength: 6)
                    DecisionButtons(itemID: item.id, compact: false)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(alignment: .topLeading) {
                FrostPanel(shape: FolderTabShape(tabWidth: 86, tabHeight: 22, radius: 18))
            }
        }
        .insetBeforeIOS17()
    }
}

private struct SmallItemView: View {
    let item: WidgetItem

    var body: some View {
        ZStack(alignment: .bottom) {
            Thumbnail(name: item.thumbnailName)
            DecisionButtons(itemID: item.id, compact: true)
                .padding(8)
        }
        .insetBeforeIOS17()
    }
}

/// Drop, Still want and Done, in the app's order, Still want warm white in the middle. Buttons on
/// iOS 17 and later; before that the whole widget opens the item.
private struct DecisionButtons: View {
    let itemID: String
    let compact: Bool

    var body: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 0) {
                Button(intent: DropItemIntent(itemID: itemID)) {
                    Mark(icon: .x, filled: false, size: compact ? 34 : 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Drop"))
                Spacer(minLength: 0)
                Button(intent: KeepItemIntent(itemID: itemID)) {
                    Mark(icon: .bookmark, filled: true, size: compact ? 34 : 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Still want"))
                Spacer(minLength: 0)
                Button(intent: DoneItemIntent(itemID: itemID)) {
                    Mark(icon: .check, filled: false, size: compact ? 34 : 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Done"))
            }
        } else {
            HStack {
                Text("Tap to open")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(SBColor.ink2)
                Spacer()
            }
        }
    }
}

/// The main one warm white with a dark glyph; the others dark with a dim glyph.
private struct Mark: View {
    let icon: SBIcon
    let filled: Bool
    let size: CGFloat

    var body: some View {
        SBIconView(icon, size: size * 0.5)
            .foregroundStyle(filled ? SBColor.ground : SBColor.ink2)
            .frame(width: size, height: size)
            .background {
                if filled {
                    Circle().fill(SBColor.accent).widgetAccentable()
                } else {
                    Circle().fill(SBColor.surface2)
                }
            }
    }
}

private struct Thumbnail: View {
    let name: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        // The filled image is an overlay on a base that takes the offered space: in a ZStack it
        // would report its own, larger size and push the rest of the widget out of place.
        SBColor.surface2
            .overlay(alignment: .top) {
                if let url = WidgetStore.url(in: .thumbnails, name: name), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(shape)
        .overlay(shape.strokeBorder(SBColor.warm(0.14), lineWidth: 1))
    }
}

// MARK: - States

private struct MessageCard: View {
    let label: String
    let headline: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AppMark(size: 13)
            Spacer(minLength: 0)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(SBColor.ink2)
            Text(WidgetMarkup.attributed(headline, size: compact ? 17 : 20))
                .lineLimit(3)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .insetBeforeIOS17()
    }
}

private struct LockedCard: View {
    let compact: Bool

    var body: some View {
        ZStack {
            // One blurred card: what the widget would be showing.
            FrostPanel(shape: FolderTabShape(tabWidth: 80, tabHeight: 20, radius: 18))
                .padding(14)
                .blur(radius: 6)
            VStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(SBColor.ink)
                Text(WidgetMarkup.attributed("Your trial's over. **Unlock the widget.**", size: compact ? 14 : 16))
                    .multilineTextAlignment(.center)
            }
            .padding(14)
        }
    }
}

// MARK: - Lock Screen

struct ScoreAccessoryView: View {
    let entry: SavedThingEntry

    var body: some View {
        if entry.card == .locked {
            VStack(alignment: .leading, spacing: 2) {
                Label("Screenshot Brain", systemImage: "lock")
                    .font(.system(size: 13, weight: .semibold))
                Text("Unlock the widget with Premium")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .widgetBackground(Color.clear)
            .widgetURL(DeepLink.paywall)
        } else {
            score(entry.score)
        }
    }

    private func score(_ score: Score) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Done \(score.done) of \(score.total)")
                .font(.system(size: 15, weight: .semibold))
                .widgetAccentable()
            Gauge(value: Double(score.done), in: 0...Double(max(score.total, 1))) {
                Text("Score")
            }
            .gaugeStyle(.accessoryLinearCapacity)
            Text("Screenshot Brain")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .widgetBackground(Color.clear)
        .widgetURL(DeepLink.home)
    }
}

// MARK: - Surfaces

/// The pre-rendered light, on the mist.
struct WidgetLightBackground: View {
    let name: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom)
            if let url = WidgetStore.url(in: .widgetLight, name: name), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }
}

/// Widgets can't blur what's behind them, so glass here is a dark warm veil with a warm hairline.
struct FrostPanel<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(SBColor.surface.opacity(0.88))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [SBColor.warm(0.2), SBColor.warm(0.06)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
    }
}

enum CategoryTitle {
    static func of(_ category: ItemCategory) -> String {
        switch category {
        case .place: "Places"
        case .event: "Events"
        case .product: "Products"
        case .recipe: "Recipes"
        case .reference: "Reference"
        case .other: "Saved"
        }
    }
}

/// Two-tone words: dim, with one bright phrase, as in the app.
enum WidgetMarkup {
    static func attributed(_ markup: String, size: CGFloat) -> AttributedString {
        var result = AttributedString()
        for (index, part) in markup.components(separatedBy: "**").enumerated() where !part.isEmpty {
            var run = AttributedString(part)
            let bold = index % 2 == 1
            run.font = .system(size: size, weight: .regular)
            run.foregroundColor = bold ? SBColor.ink : SBColor.ink2
            result.append(run)
        }
        return result
    }
}

extension View {
    /// iOS 17 insets widget content by the system's margins; before that, add our own.
    @ViewBuilder
    func insetBeforeIOS17() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self
        } else {
            padding(14)
        }
    }

    /// iOS 17 needs the background declared as the widget's container background.
    @ViewBuilder
    func widgetBackground<Background: View>(_ background: Background) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { background }
        } else {
            self.background(background)
        }
    }
}
