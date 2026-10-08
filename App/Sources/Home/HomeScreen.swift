import Core
import DesignSystem
import Media
import Reveal
import Store
import SwiftUI
import Triage

enum HomeRoute: Hashable {
    case item(String)
    case category(ItemCategory)
}

/// The score, then Coming up on the timeline, then Still want as light tiles, then search.
struct HomeScreen: View {
    @ObservedObject var home: HomeModel
    var palette: LightPalette = .sampleTopScreenshots
    var isPremium = false
    var onRecap: () -> Void = {}
    var onDeleteDropped: () -> Void = {}
    var onReveal: (RevealPeriod) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                // Shown even before anything's kept: new screenshots waiting is the way in.
                if home.recapCount > 0 {
                    RecapPrompt(count: home.recapCount, palette: palette, action: onRecap)
                }
                if home.isEmpty && home.query.isEmpty {
                    EmptyHome()
                } else {
                    if !home.comingUp.isEmpty {
                        ComingUpSection(items: home.comingUp)
                    }
                    if !home.shelves.isEmpty {
                        StillWantSection(shelves: home.shelves)
                    }
                }
                SearchSection(home: home)
                RevealsSection(isPremium: isPremium, palette: palette, onReveal: onReveal)
                if home.droppedCount > 0 {
                    DroppedRow(count: home.droppedCount, action: onDeleteDropped)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            LightField(.sweep(palette).shifted(down: -0.08), drifts: true)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AppMark()
                Spacer()
            }
            .padding(.bottom, 18)
            SmallLabel("Your score")
            ScoreView(done: home.score.done, total: home.score.total)
            SmallLabel(scoreLine)
                .padding(.top, 6)
        }
    }

    private var scoreLine: String {
        let score = home.score
        if score.total == 0 { return "Keep a few things and they'll count here." }
        if score.done == 0 { return "\(score.total) kept. None done yet. We can fix that." }
        if score.done == score.total { return "Everything you kept, done." }
        return "Done \(score.done) of \(score.total). Drops don't count against you."
    }
}

// MARK: - Sections

private struct RecapPrompt: View {
    let count: Int
    let palette: LightPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FrostedCard(palette: palette) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        SmallLabel(count == 1 ? "1 waiting" : "\(count) waiting")
                        MistHeadline("Time for **your recap.**", size: 24, alignment: .leading)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(SBColor.ink)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ComingUpSection: View {
    let items: [ScreenshotItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmallLabel("Coming up")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: HomeRoute.item(item.id)) {
                            ComingUpColumn(item: item, isNext: index == 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
    }
}

/// A folder-tab card standing on the timeline line, the soonest one marked in orange.
private struct ComingUpColumn: View {
    let item: ScreenshotItem
    let isNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FolderTabCard(tab: dayText, palette: palette) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? "Something you saved")
                        .font(SBFont.body(15, weight: .semibold))
                        .foregroundStyle(SBColor.ink)
                        .lineLimit(2)
                    Text(relative)
                        .font(SBFont.mono(11))
                        .foregroundStyle(SBColor.inkSecondary)
                }
            }
            .frame(width: 196, height: 196)
            ZStack(alignment: .leading) {
                Rectangle().fill(SBColor.hairline).frame(height: 1)
                Circle()
                    .fill(isNext ? SBColor.accent : SBColor.inkSecondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .padding(.leading, 18)
            }
            .frame(width: 210)
        }
        .padding(.trailing, 14)
        .accessibilityElement(children: .combine)
    }

    private var palette: LightPalette {
        .item(category: item.category, colors: item.palette, isSafeToDisplay: item.isSafeToDisplay)
    }

    private var dayText: String {
        guard let due = item.dueDate else { return CategoryName.title(item.category) }
        if Calendar.current.isDateInToday(due) { return "Today" }
        if Calendar.current.isDateInTomorrow(due) { return "Tomorrow" }
        return due.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private var relative: String {
        guard let due = item.dueDate else { return "" }
        return due.formatted(.relative(presentation: .named)).uppercased()
    }
}

private struct StillWantSection: View {
    let shelves: [HomeModel.Shelf]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmallLabel("Still want")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(shelves) { shelf in
                    NavigationLink(value: HomeRoute.category(shelf.category)) {
                        LightTile(CategoryName.title(shelf.category), detail: detail(shelf), palette: palette(shelf))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detail(_ shelf: HomeModel.Shelf) -> String {
        let oldest = shelf.items.first.map { ($0.stateChangedAt ?? $0.createdAt).formatted(.relative(presentation: .numeric, unitsStyle: .narrow)) } ?? ""
        return "\(shelf.items.count) KEPT · OLDEST \(oldest.uppercased())"
    }

    private func palette(_ shelf: HomeModel.Shelf) -> LightPalette {
        // The tile glows with the colours of the oldest safe thing on the shelf.
        if let item = shelf.items.first(where: \.isSafeToDisplay) {
            return .item(category: item.category, colors: item.palette, isSafeToDisplay: true)
        }
        return .category(shelf.category)
    }
}

private struct SearchSection: View {
    @ObservedObject var home: HomeModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmallLabel("Find anything you saved")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(SBColor.inkSecondary)
                TextField("Wifi password, that address, the recipe…", text: $home.query)
                    .font(SBFont.body(16))
                    .foregroundStyle(SBColor.ink)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !home.query.isEmpty {
                    Button {
                        home.query = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SBColor.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear search"))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .sbGlass(in: Capsule())

            if !home.query.isEmpty {
                if home.results.isEmpty {
                    SmallLabel("Nothing matches that yet.")
                        .padding(.leading, 18)
                } else {
                    VStack(spacing: 8) {
                        ForEach(home.results) { item in
                            NavigationLink(value: HomeRoute.item(item.id)) {
                                ItemRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// A compact row: the screenshot, its title, its category and date.
struct ItemRow: View {
    let item: ScreenshotItem

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                LightField(.glow(.item(category: item.category, colors: item.palette, isSafeToDisplay: item.isSafeToDisplay)), grain: 0)
                AssetImage(item.assetLocalID, maxPixelSize: 180)
            }
            .frame(width: 52, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "Something you saved")
                    .font(SBFont.body(15, weight: .semibold))
                    .foregroundStyle(SBColor.ink)
                    .lineLimit(1)
                Text("\(CategoryName.title(item.category).uppercased()) · \(item.createdAt.formatted(date: .abbreviated, time: .omitted).uppercased())")
                    .font(SBFont.mono(11))
                    .foregroundStyle(SBColor.inkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(SBColor.inkSecondary)
        }
        .padding(10)
        .sbGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Last month's Reveal (short for free, full with premium) and the all-time one (premium).
private struct RevealsSection: View {
    let isPremium: Bool
    let palette: LightPalette
    let onReveal: (RevealPeriod) -> Void

    var body: some View {
        let lastMonth = RevealPeriod.lastMonth()
        VStack(alignment: .leading, spacing: 14) {
            SmallLabel("Your Reveals")
            HStack(spacing: 12) {
                Button { onReveal(lastMonth) } label: {
                    LightTile("\(lastMonth.name()) Reveal", detail: isPremium ? "FULL STATS" : "FREE · FULL WITH PREMIUM", palette: palette)
                }
                .buttonStyle(.plain)
                Button { onReveal(.allTime) } label: {
                    LightTile("All-time Reveal", detail: isPremium ? "EVERY SCREENSHOT" : "PREMIUM", palette: palette.reversed)
                        .overlay(alignment: .topTrailing) {
                            if !isPremium {
                                Image(systemName: "lock")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundStyle(SBColor.ink)
                                    .padding(14)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DroppedRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(count == 1 ? "1 dropped screenshot" : "\(count) dropped screenshots")
                    .font(SBFont.body(15, weight: .semibold))
                    .foregroundStyle(SBColor.ink)
                SmallLabel("Clear them out of Photos in one go")
            }
            Spacer()
            Button(action: action) {
                Chip("Delete")
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .sbGlass(in: RoundedRectangle(cornerRadius: SBRadius.card, style: .continuous))
    }
}

private struct EmptyHome: View {
    var body: some View {
        VStack(spacing: 16) {
            GlassLens(diameter: 120)
                .padding(.vertical, 12)
            MistHeadline("Nothing kept yet. **Screenshot something.**", size: 28)
            MistBody("A gig, a place, a thing you want. It turns up here, and on your widget.")
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
