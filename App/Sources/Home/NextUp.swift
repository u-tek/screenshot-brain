import Core
import DesignSystem
import Store
import SwiftUI
import Triage

/// The one thing to look at once there's nothing to sort: the soonest dated thing coming up, or
/// failing that, the thing kept the longest. It's what stops "All sorted" being a dead end, at
/// Home and at the end of a sort.
struct NextUp {
    enum Reason {
        /// Has a date in the next week.
        case comingUp
        /// Kept a while and not done.
        case keptLongest
    }

    let item: ScreenshotItem
    let reason: Reason

    /// Coming up beats kept longest: a date is a real reason to go. Untitled things are skipped,
    /// since "Something you saved" gives nobody a reason to tap.
    static func pick(comingUp: [ScreenshotItem], stillWant: [ScreenshotItem]) -> NextUp? {
        if let item = comingUp.first(where: { $0.title != nil }) {
            return NextUp(item: item, reason: .comingUp)
        }
        let oldest = stillWant
            .filter { $0.title != nil && $0.category.isIntention }
            .min { ($0.stateChangedAt ?? $0.createdAt) < ($1.stateChangedAt ?? $1.createdAt) }
        return oldest.map { NextUp(item: $0, reason: .keptLongest) }
    }

    /// Straight from the database, for the end of a sort.
    static func pick(from database: AppDatabase?, now: Date = Date()) -> NextUp? {
        guard let database else { return nil }
        let comingUp = (try? database.comingUp(now: now)) ?? []
        let stillWant = ((try? database.stillWant()) ?? [:]).values.flatMap { $0 }
        return pick(comingUp: comingUp, stillWant: stillWant)
    }

    /// For analytics: 1 when the pick has a date, 0 when it was kept longest.
    var isDated: Int { reason == .comingUp ? 1 : 0 }
}

extension HomeModel {
    var nextUp: NextUp? {
        NextUp.pick(comingUp: comingUp, stillWant: shelves.flatMap(\.items))
    }
}

/// A folder-tab card for the pick: when it is (or how long it's been kept) on the tab, the thing's
/// name, and one line of why it's here.
struct NextUpCard: View {
    let pick: NextUp

    var body: some View {
        FolderTabCard(tab: tab, palette: palette) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pick.item.title ?? "Something you saved")
                    .sbText(.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .sbText(.labelDim)
            }
        }
        .frame(maxWidth: .infinity)
        // Its own height, not all that's left: it's one thing, not the whole screen.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens it"))
    }

    private var palette: LightPalette {
        .item(category: pick.item.category, colors: pick.item.palette, isSafeToDisplay: pick.item.isSafeToDisplay)
    }

    private var tab: String {
        switch pick.reason {
        case .comingUp:
            guard let due = pick.item.dueDate else { return "Next up" }
            if Calendar.current.isDateInToday(due) { return "Next up · Today" }
            if Calendar.current.isDateInTomorrow(due) { return "Next up · Tomorrow" }
            return "Next up · \(due.formatted(.dateTime.weekday(.wide)))"
        case .keptLongest:
            return "From your saves"
        }
    }

    private var detail: String {
        switch pick.reason {
        case .comingUp:
            let when = pick.item.dueDate?.formatted(.relative(presentation: .named)) ?? ""
            return "\(CategoryName.title(pick.item.category)) · \(when)".uppercased()
        case .keptLongest:
            let since = pick.item.stateChangedAt ?? pick.item.createdAt
            let ago = since.formatted(.relative(presentation: .named))
            return "Kept \(ago) · Still want it?".uppercased()
        }
    }
}

extension EnvironmentValues {
    /// Where screens that aren't handed the app model report events. Off by default, so previews
    /// and snapshots report nothing.
    var analytics: Analytics {
        get { self[AnalyticsKey.self] }
        set { self[AnalyticsKey.self] = newValue }
    }
}

private struct AnalyticsKey: EnvironmentKey {
    static let defaultValue = Analytics.disabled
}

/// Home once nothing is waiting: "All sorted." and, when there's something kept, the pick under it.
struct AllSorted: View {
    let pick: NextUp?
    @Environment(\.analytics) private var analytics

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Text("All sorted.")
                    .sbText(.large)
                Text(pick == nil ? "New screenshots land here as you take them." : "Nothing new to sort. Here's one you already found.")
                    .sbText(.body)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40 - SBSpace.gutter)

            if let pick {
                NavigationLink(value: HomeRoute.item(pick.item.id)) {
                    NextUpCard(pick: pick)
                }
                .buttonStyle(SBPressStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    analytics.track(.nextUpOpened, counts: ["from": 0, "dated": pick.isDated])
                })
                .onAppear {
                    analytics.track(.nextUpShown, counts: ["from": 0, "dated": pick.isDated])
                }
            }
        }
        .padding(.horizontal, SBSpace.gutter)
        .frame(maxWidth: .infinity)
    }
}
