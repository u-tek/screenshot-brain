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
    case kept
    case settings
}

/// Home has one job: how many screenshots are waiting, and the button that sorts them. What's
/// been kept is one quiet line underneath; settings is the gear. The light behind is livelier the
/// more there is to sort, and settles once it's all sorted.
struct HomeScreen: View {
    @ObservedObject var home: HomeModel
    var onSort: () -> Void = {}
    var onKept: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                AppMark()
                Spacer()
                SBCircleButton(.sliders, label: "Settings", action: onSettings)
            }
            .padding(.horizontal, SBSpace.gutter)
            .padding(.top, 8)

            Spacer(minLength: 24)

            if home.toSort > 0 {
                pile
            } else {
                allSorted
            }

            Spacer(minLength: 24)

            keptLine
                .padding(.bottom, 20)
        }
        .sbScreen(ambience)
    }

    /// The count, big, and the one button.
    private var pile: some View {
        VStack(spacing: 0) {
            Text("\(home.toSort)")
                .sbText(.numXL)
                .monospacedDigit()
            Text(home.toSort == 1 ? "screenshot to sort" : "screenshots to sort")
                .sbText(.unit, color: SBColor.ink2)
                .padding(.top, 6)
            StartSortingButton(title: "Start sorting", action: onSort)
                .padding(.top, 44)
        }
        .frame(maxWidth: .infinity)
    }

    private var allSorted: some View {
        VStack(spacing: 12) {
            Text("All sorted.")
                .sbText(.large)
            Text("New screenshots land here as you take them.")
                .sbText(.body)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    /// "17 kept · 6 done", opening Kept. Nothing at all until something's been kept.
    @ViewBuilder
    private var keptLine: some View {
        let score = home.score
        if score.total > 0 {
            Button(action: onKept) {
                HStack(spacing: 8) {
                    Text("\(score.total - score.done) kept · \(score.done) done")
                        .sbText(.body, color: SBColor.ink)
                    SBIconView(.arrow, size: 14)
                        .foregroundStyle(SBColor.ink2)
                }
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Capsule().fill(SBColor.warm(0.08)))
                .contentShape(Capsule())
            }
            .buttonStyle(SBPressStyle())
            .accessibilityLabel(Text("\(score.total - score.done) kept, \(score.done) done. Open what you kept."))
        }
    }

    private var ambience: SBAmbience {
        home.toSort == 0 ? .calm : SBAmbience(energy: min(0.85, 0.4 + Double(home.toSort) / 60))
    }
}

/// The one obvious button: wide, warm white, softly lit from below.
struct StartSortingButton: View {
    let title: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var textSize: CGFloat = 19

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: textSize, weight: .semibold))
                SBIconView(.arrow, size: 18)
            }
            .foregroundStyle(SBColor.ground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
            .background(Capsule().fill(SBColor.accent))
            .shadow(color: SBRamp.r4.opacity(0.45), radius: 26, y: 10)
            .contentShape(Capsule())
        }
        .buttonStyle(SBPressStyle())
        .padding(.horizontal, 32)
        .accessibilityLabel(Text(title))
    }
}

/// Everything kept, one tap from Home: the score, what's coming up, kept things by kind, search,
/// the Reveals, and dropped screenshots waiting to be cleared from Photos.
struct KeptScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var home: HomeModel
    var palette: LightPalette = .sampleTopScreenshots
    var isPremium = false
    var onDeleteDropped: () -> Void = {}
    var onReveal: (RevealPeriod) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            SBNavHeader(title: "Kept", onLeading: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    if home.score.total > 0 {
                        score
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
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sbScreen(SBAmbience(energy: 0.25))
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Done so far, out of everything kept, and how far along that is.
    private var score: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(home.score.done)")
                    .sbText(.numL)
                    .monospacedDigit()
                Text("of \(home.score.total) done")
                    .sbText(.unit, color: SBColor.ink2)
            }
            ScoreTrack(done: home.score.done, total: home.score.total)
            Text(scoreLine)
                .sbText(.body)
        }
        .accessibilityElement(children: .combine)
    }

    private var scoreLine: String {
        let score = home.score
        if score.done == 0 { return "\(score.total) kept. None done yet. We can fix that." }
        if score.done == score.total { return "Everything you kept, done." }
        return "Drops don't count against you."
    }
}

// MARK: - Sections

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
            // Two to a row, inside the margins, soonest first.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SBSpace.gap), GridItem(.flexible(), spacing: SBSpace.gap)], spacing: SBSpace.gap) {
                ForEach(items) { item in
                    NavigationLink(value: HomeRoute.item(item.id)) {
                        ComingUpColumn(item: item)
                    }
                    .buttonStyle(SBPressStyle())
                }
            }
        }
    }
}

/// A folder-tab card: the day on its tab, the thing's name and how long until it.
private struct ComingUpColumn: View {
    let item: ScreenshotItem

    var body: some View {
        FolderTabCard(tab: dayText, palette: palette) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "Something you saved")
                    .sbText(.title)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(relative)
                    .sbText(.labelDim)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
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
