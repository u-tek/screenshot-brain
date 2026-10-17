import Core
import DesignSystem
import Media
import Store
import SwiftUI

/// Everything done, month by month: the proof there was plenty to do. Each thing keeps the photo
/// and note added to it, and outlives its screenshot. A month can be shared as a card.
struct DidItScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var home: HomeModel
    var palette: LightPalette = .sampleTopScreenshots
    var onShared: () -> Void = {}
    @State private var sharing: DidItMonth?

    var body: some View {
        VStack(spacing: 0) {
            SBNavHeader(title: "Did it", onLeading: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    if home.doneLog.isEmpty {
                        empty
                    } else {
                        hero
                        ForEach(DidItMonth.months(home.doneLog)) { month in
                            MonthSection(month: month) { sharing = month }
                        }
                    }
                }
                .padding(.horizontal, SBSpace.gutter)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .sbScreen(SBAmbience(energy: 0.3))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sharing) { month in
            DidItShareSheet(month: month, palette: palette, onShared: onShared)
        }
    }

    /// How many, big, and since when.
    private var hero: some View {
        let count = home.doneLog.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(count)")
                    .sbText(.numL)
                    .monospacedDigit()
                Text(count == 1 ? "thing you actually did" : "things you actually did")
                    .sbText(.unit, color: SBColor.ink2)
            }
            Text(sinceLine)
                .sbText(.body)
        }
        .accessibilityElement(children: .combine)
    }

    private var sinceLine: String {
        guard let first = home.doneLog.last?.doneAt else { return "" }
        let since = "Since \(first.formatted(.dateTime.day().month(.wide)))."
        return home.doneLog.count >= 3 ? since + " And they say there's nothing to do." : since
    }

    private var empty: some View {
        VStack(spacing: 16) {
            GlassLens(diameter: 120)
                .padding(.vertical, 12)
            MistHeadline("Nothing done **yet.**", size: 28)
            MistBody("Mark something done and it lands here. Add a photo of it actually happening.")
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// One month of the log.
struct DidItMonth: Identifiable, Hashable {
    let start: Date
    /// Newest first.
    let entries: [DoneEntry]

    var id: Date { start }

    /// "October", or "October 2025" outside this year.
    func name(now: Date = Date(), calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: now)
        return sameYear
            ? start.formatted(.dateTime.month(.wide))
            : start.formatted(.dateTime.month(.wide).year())
    }

    /// The log split into months, newest first.
    static func months(_ log: [DoneEntry], calendar: Calendar = .current) -> [DidItMonth] {
        var months: [DidItMonth] = []
        for entry in log.sorted(by: { $0.doneAt > $1.doneAt }) {
            let start = calendar.dateInterval(of: .month, for: entry.doneAt)?.start ?? entry.doneAt
            if let last = months.last, last.start == start {
                months[months.count - 1] = DidItMonth(start: start, entries: last.entries + [entry])
            } else {
                months.append(DidItMonth(start: start, entries: [entry]))
            }
        }
        return months
    }
}

private struct MonthSection: View {
    let month: DidItMonth
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SBLabel("\(month.name()) · \(month.entries.count)")
                Spacer()
                Button(action: onShare) {
                    SBChip("Share", icon: .send)
                }
                .buttonStyle(SBPressStyle())
                .accessibilityLabel(Text("Share \(month.name())"))
            }
            VStack(spacing: SBSpace.gap + 4) {
                ForEach(month.entries) { entry in
                    if let itemID = entry.itemID {
                        NavigationLink(value: HomeRoute.item(itemID)) {
                            DoneCard(entry: entry)
                        }
                        .buttonStyle(SBPressStyle())
                    } else {
                        // The screenshot's gone; what was done stays.
                        DoneCard(entry: entry)
                    }
                }
            }
        }
    }
}

/// One thing done: a folder-tab card with the day on its tab, the photo added to it (or its
/// kind's light), and what it was, with the note underneath.
struct DoneCard: View {
    let entry: DoneEntry

    var body: some View {
        let shape = FolderTabShape()
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.doneAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .sbText(.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.leading, 18)
                .frame(height: 30)
            if let photo = entry.photoName {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        AssetImage(MemoryPhotos.identifier(for: photo), maxPixelSize: 1400)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.tile - 8, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
            } else {
                Spacer(minLength: 44)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title ?? DoneWords.fallbackTitle(entry.category))
                    .sbText(.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(DoneWords.verb(entry.category))
                    .sbText(.labelDim)
                if let note = entry.note {
                    Text(note)
                        .sbText(.body, color: SBColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SBRadius.tile - 8, style: .continuous).fill(SBColor.surface))
            .padding(8)
        }
        .background {
            ZStack {
                SBColor.surface2
                LightField(.bloom(.category(entry.category)).shifted(down: 0.12), ground: false, grain: 0.04)
            }
            .clipShape(shape)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

/// How the log talks about things done.
enum DoneWords {
    /// What doing it was: "Cooked it", "Went".
    static func verb(_ category: ItemCategory) -> String {
        switch category {
        case .place: "Been"
        case .event, .travel: "Went"
        case .product: "Got it"
        case .recipe: "Cooked it"
        case .watch: "Watched"
        case .listen: "Listened"
        case .read: "Read it"
        case .message, .post, .reference, .other: "Done"
        }
    }

    static func fallbackTitle(_ category: ItemCategory) -> String {
        switch category {
        case .place: "A place you saved"
        case .event: "A gig you saved"
        case .product: "A thing you wanted"
        case .recipe: "A recipe you saved"
        case .watch: "A show you saved"
        case .listen: "An album you saved"
        case .read: "A book you saved"
        case .travel: "A trip you saved"
        case .message, .post, .reference, .other: "Something you saved"
        }
    }
}
