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
    case filed(ItemCategory)
    case kept
    case didIt
    case settings
}

/// Home has one job: how many screenshots are waiting, and the button that sorts them. What's
/// been kept and what's been done are two quiet buttons underneath; settings is the gear. The light behind is livelier the
/// more there is to sort, and settles once it's all sorted.
struct HomeScreen: View {
    @ObservedObject var home: HomeModel
    var onSort: () -> Void = {}
    var onKept: () -> Void = {}
    var onDidIt: () -> Void = {}
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

    /// Not a dead end: once it's all sorted, one thing from what's been kept to go and do.
    private var allSorted: some View {
        AllSorted(pick: home.nextUp)
    }

    /// "17 kept" opening Kept, and "6 done" opening the did-it log. Each shows once there's
    /// something in it.
    @ViewBuilder
    private var keptLine: some View {
        let kept = home.score.total - home.score.done
        let done = home.doneLog.count
        HStack(spacing: SBSpace.gap) {
            if home.score.total > 0 {
                QuietButton(title: "\(kept) kept", accessibility: "\(kept) kept. Open what you kept.", action: onKept)
            }
            if done > 0 {
                QuietButton(title: "\(done) done", accessibility: "\(done) done. Open what you did.", action: onDidIt)
            }
        }
    }

    private var ambience: SBAmbience {
        home.toSort == 0 ? .calm : SBAmbience(energy: min(0.85, 0.4 + Double(home.toSort) / 60))
    }
}

/// A quiet capsule under Home's count: a few words and an arrow.
private struct QuietButton: View {
    let title: String
    let accessibility: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
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
        .accessibilityLabel(Text(accessibility))
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
    var onDidIt: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            SBNavHeader(title: "Kept", onLeading: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    if home.score.total > 0 {
                        score
                    }
                    if home.isEmpty && !home.isSearching {
                        EmptyHome()
                    } else {
                        if !home.comingUp.isEmpty {
                            ComingUpSection(items: home.comingUp)
                        }
                        if !home.shelves.isEmpty {
                            StillWantSection(shelves: home.shelves)
                        }
                        if !home.filed.isEmpty {
                            FiledSection(shelves: home.filed)
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
            if !home.doneLog.isEmpty {
                Button(action: onDidIt) {
                    HStack(spacing: 8) {
                        Text("See what you did")
                            .sbText(.body, color: SBColor.ink)
                        SBIconView(.arrow, size: 14)
                            .foregroundStyle(SBColor.ink2)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SBPressStyle())
            }
        }
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
                // Two lines, wrapping rather than cut short: the card grows to fit.
                Text(item.title ?? "Something you saved")
                    .sbText(.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(relative)
                    .sbText(.labelDim)
            }
        }
        .frame(maxWidth: .infinity)
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
        guard !item.dueDateHasTime else {
            return due.formatted(.relative(presentation: .named)).uppercased()
        }
        // A day with no time: count days, not hours to a noon nobody wrote.
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: due)).day ?? 0
        if days == 0 { return "ALL DAY" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: days)).uppercased()
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
        return "\(shelf.items.count) kept, oldest \(oldest)"
    }
}

/// Kept without being sorted: there was nothing to do about them. A row of small tiles, one per
/// kind.
private struct FiledSection: View {
    let shelves: [HomeModel.Shelf]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SBLabel("Filed away · Nothing to do")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SBSpace.gap), GridItem(.flexible(), spacing: SBSpace.gap)], spacing: SBSpace.gap) {
                ForEach(shelves) { shelf in
                    NavigationLink(value: HomeRoute.filed(shelf.category)) {
                        SBKindTile(kind: SBKind(shelf.category), title: CategoryName.title(shelf.category), count: shelf.items.count, height: 112)
                    }
                    .buttonStyle(SBPressStyle())
                }
            }
        }
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

            if home.isSearching {
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
            .accessibilityLabel(Text(count == 1 ? "Delete 1 dropped screenshot from Photos" : "Delete \(count) dropped screenshots from Photos"))
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
