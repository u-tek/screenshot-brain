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

/// The score, the recap tile, Coming up on the timeline, Still want as kind tiles, then search.
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
            .padding(.horizontal, SBSpace.gutter)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .sbScreen()
    }

    /// The mark, then the score: a big light number, what it's out of, and how far along.
    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                AppMark()
                Spacer()
            }
            .padding(.bottom, 28)
            Text("Score")
                .sbText(.body)
            Text("\(home.score.done)")
                .sbText(.numXL)
                .monospacedDigit()
                .padding(.top, 4)
            Text(home.score.total == 0 ? "nothing kept yet" : "of \(home.score.total) done")
                .sbText(.unit, color: SBColor.ink2)
                .padding(.top, 6)
            ScoreTrack(done: home.score.done, total: home.score.total)
                .padding(.top, 22)
            Text(scoreLine)
                .sbText(.body)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

/// The wide warm tile: tonight's recap and how many are waiting.
private struct RecapPrompt: View {
    let count: Int
    let palette: LightPalette
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous)
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tonight's recap")
                        .sbText(.body, color: SBColor.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(count)")
                            .sbText(.numL)
                            .monospacedDigit()
                        Text("waiting")
                            .sbText(.unit)
                    }
                }
                Spacer()
                SBIconView(.arrow, size: 18)
                    .foregroundStyle(SBColor.ground)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(SBColor.accent))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(
                        stops: [
                            .init(color: SBKind.events.deep, location: 0),
                            .init(color: SBRamp.r2, location: 0.45),
                            .init(color: SBKind.events.core, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    SBLight(SBKind.places.core, width: 240, height: 150, opacity: 0.55)
                        .offset(x: 30, y: 90)
                }
                .clipShape(shape)
            }
            .contentShape(shape)
        }
        .buttonStyle(SBPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(count == 1 ? "Tonight's recap, 1 waiting" : "Tonight's recap, \(count) waiting"))
        .accessibilityAddTraits(.isButton)
    }
}

/// How far along the score is: a warm track with the done part in warm white.
private struct ScoreTrack: View {
    let done: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SBColor.warm(0.14))
                Capsule()
                    .fill(SBColor.accent)
                    .frame(width: proxy.size.width * CGFloat(total > 0 ? Double(done) / Double(total) : 0))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct ComingUpSection: View {
    let items: [ScreenshotItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SBLabel("Coming up")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: HomeRoute.item(item.id)) {
                            ComingUpColumn(item: item, isNext: index == 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SBSpace.gutter)
            }
            .padding(.horizontal, -SBSpace.gutter)
        }
    }
}

/// A folder-tab card standing on the timeline line, the soonest one marked in warm white.
private struct ComingUpColumn: View {
    let item: ScreenshotItem
    let isNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FolderTabCard(tab: dayText, palette: palette) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? "Something you saved")
                        .sbText(.title)
                        .lineLimit(2)
                    Text(relative)
                        .sbText(.labelDim)
                }
            }
            .frame(width: 196, height: 196)
            ZStack(alignment: .leading) {
                Rectangle().fill(SBColor.line).frame(height: 1)
                Circle()
                    .fill(isNext ? SBColor.accent : SBColor.warm(0.3))
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
            SBLabel("Still want")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SBSpace.gap), GridItem(.flexible(), spacing: SBSpace.gap)], spacing: SBSpace.gap) {
                ForEach(shelves) { shelf in
                    NavigationLink(value: HomeRoute.category(shelf.category)) {
                        SBKindTile(kind: SBKind(shelf.category), title: CategoryName.title(shelf.category), count: shelf.items.count, height: 180)
                            .accessibilityHint(Text(detail(shelf)))
                    }
                    .buttonStyle(SBPressStyle())
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
            SBLabel("Find anything you saved")
            HStack(spacing: 10) {
                SBIconView(.search, size: 18)
                    .foregroundStyle(SBColor.ink2)
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
                        SBIconView(.x, size: 14)
                            .foregroundStyle(SBColor.ink2)
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
                    Text("Nothing matches that yet.")
                        .sbText(.body)
                        .padding(.leading, 18)
                } else {
                    VStack(spacing: SBSpace.gap) {
                        ForEach(home.results) { item in
                            NavigationLink(value: HomeRoute.item(item.id)) {
                                ItemRow(item: item)
                            }
                            .buttonStyle(SBPressStyle())
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
                SBColor.surface2
                AssetImage(item.assetLocalID, maxPixelSize: 180)
            }
            .frame(width: 52, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SBColor.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title ?? "Something you saved")
                    .sbText(.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(SBKind(item.category).core)
                        .frame(width: 6, height: 6)
                        .shadow(color: SBKind(item.category).core, radius: 4)
                    Text("\(CategoryName.title(item.category)) · \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .sbText(.labelDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            SBIconView(.system("chevron.right"), size: 14)
                .foregroundStyle(SBColor.ink2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SBColor.surface))
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
            SBLabel("Your Reveals")
            HStack(spacing: SBSpace.gap) {
                Button { onReveal(lastMonth) } label: {
                    LightTile("\(lastMonth.name()) Reveal", detail: isPremium ? "FULL STATS" : "FREE · FULL WITH PREMIUM", palette: palette)
                }
                .buttonStyle(SBPressStyle())
                Button { onReveal(.allTime) } label: {
                    LightTile("All-time Reveal", detail: isPremium ? "EVERY SCREENSHOT" : "PREMIUM", palette: palette.reversed)
                        .overlay(alignment: .topTrailing) {
                            if !isPremium {
                                SBIconView(.system("lock"), size: 14)
                                    .foregroundStyle(SBColor.ink)
                                    .padding(16)
                            }
                        }
                }
                .buttonStyle(SBPressStyle())
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
                    .sbText(.title)
                Text("Clear them out of Photos in one go")
                    .sbText(.body)
            }
            Spacer()
            Button(action: action) {
                SBChip("Delete")
            }
            .buttonStyle(SBPressStyle())
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous).fill(SBColor.surface))
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
