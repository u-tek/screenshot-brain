import Core
import DesignSystem
import Store
import SwiftUI
import Triage

/// The one thing to look at once there's nothing to sort: the soonest dated thing coming up, or
/// failing that, today's pick from what's been kept. It's what stops "All sorted" being a dead
/// end, at Home and at the end of a sort.
struct NextUp {
    enum Reason: Equatable {
        /// Has a date in the next week.
        case comingUp
        /// Today's pick, and the line that says why.
        case today(String)
    }

    let item: ScreenshotItem
    let reason: Reason

    /// Coming up beats today's pick: a date is a real reason to go. Untitled things are skipped,
    /// since "Something you saved" gives nobody a reason to tap.
    static func pick(comingUp: [ScreenshotItem], stillWant: [ScreenshotItem], now: Date = Date(), reroll: Int = 0) -> NextUp? {
        if let item = comingUp.first(where: { $0.title != nil }) {
            return NextUp(item: item, reason: .comingUp)
        }
        return DailyPick.pick(from: stillWant, now: now, reroll: reroll).map { NextUp(item: $0.item, reason: .today($0.reason)) }
    }

    /// Straight from the database, for the end of a sort.
    static func pick(from database: AppDatabase?, now: Date = Date()) -> NextUp? {
        guard let database else { return nil }
        let comingUp = (try? database.comingUp(now: now)) ?? []
        let stillWant = ((try? database.stillWant()) ?? [:]).values.flatMap { $0 }
        return pick(comingUp: comingUp, stillWant: stillWant, now: now, reroll: PickReroll.today(now: now))
    }

    /// For analytics: 1 when the pick has a date, 0 when it's today's pick.
    var isDated: Int { reason == .comingUp ? 1 : 0 }
}

/// How many times today's pick has been swapped today (Premium). Starts again each day.
enum PickReroll {
    private static let key = "pick.reroll"

    static func today(now: Date = Date(), defaults: UserDefaults = .standard) -> Int {
        guard let saved = defaults.string(forKey: key), saved.hasPrefix(day(now) + ":") else { return 0 }
        return Int(saved.split(separator: ":").last ?? "") ?? 0
    }

    static func increment(now: Date = Date(), defaults: UserDefaults = .standard) -> Int {
        let next = today(now: now, defaults: defaults) + 1
        defaults.set("\(day(now)):\(next)", forKey: key)
        return next
    }

    private static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

extension HomeModel {
    var nextUp: NextUp? {
        NextUp.pick(comingUp: comingUp, stillWant: shelves.flatMap(\.items), now: fixedNow ?? Date(), reroll: reroll)
    }

    /// Thursday evening to Sunday: two or three kept things for the weekend, or nothing.
    var weekendPlan: [ScreenshotItem] {
        guard WeekendPlan.isOn(fixedNow ?? Date()) else { return [] }
        var seen: Set<String> = []
        let kept = (comingUp.filter { $0.state == .stillWant } + shelves.flatMap(\.items)).filter { seen.insert($0.id).inserted }
        return WeekendPlan.pick(from: kept, now: fixedNow ?? Date(), reroll: reroll)
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
                if case .today(let why) = pick.reason {
                    Text(why)
                        .sbText(.body)
                } else {
                    Text(detail)
                        .sbText(.labelDim)
                }
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
        case .today:
            return "Today's pick"
        }
    }

    private var detail: String {
        switch pick.reason {
        case .comingUp:
            let when = pick.item.dueDate?.formatted(.relative(presentation: .named)) ?? ""
            return "\(CategoryName.title(pick.item.category)) · \(when)".uppercased()
        case .today(let why):
            return why
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

/// Home once nothing is waiting: "All sorted." and, when there's something kept, the pick under
/// it (or, Thursday evening to Sunday, the weekend plan). Premium can ask for another; free gets
/// one a day.
struct AllSorted: View {
    let pick: NextUp?
    var weekend: [ScreenshotItem] = []
    var isPremium = false
    var onAnother: () -> Void = {}
    var onShowPlans: () -> Void = {}
    @Environment(\.analytics) private var analytics

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Text("All sorted.")
                    .sbText(.large)
                Text(subtitle)
                    .sbText(.body)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40 - SBSpace.gutter)

            if !weekend.isEmpty {
                WeekendCard(items: weekend)
                    .onAppear { analytics.track(.weekendPlanShown, counts: ["count": weekend.count]) }
                another(title: "Swap them")
            } else if let pick {
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
                if pick.isDated == 0 {
                    another(title: "Pick another")
                }
            }
        }
        .padding(.horizontal, SBSpace.gutter)
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        if !weekend.isEmpty { return "Nothing new to sort. Here's your weekend, from your saves." }
        return pick == nil ? "New screenshots land here as you take them." : "Nothing new to sort. Here's one you already found."
    }

    /// Premium swaps it; free gets one a day, and the button says so.
    private func another(title: String) -> some View {
        Button {
            analytics.track(.pickRerolled, counts: ["premium": isPremium ? 1 : 0])
            isPremium ? onAnother() : onShowPlans()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .sbText(.body, color: SBColor.ink)
                if !isPremium {
                    Text("PREMIUM")
                        .sbText(.labelDim)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Capsule().fill(SBColor.warm(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(SBPressStyle())
        .accessibilityHint(Text(isPremium ? "Shows a different one" : "One pick a day on free. Shows the plans"))
    }
}

/// The weekend plan: a folder-tab card with two or three kept things, each one tappable.
struct WeekendCard: View {
    let items: [ScreenshotItem]

    var body: some View {
        FolderTabCard(tab: "This weekend", palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    NavigationLink(value: HomeRoute.item(item.id)) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title ?? "Something you saved")
                                    .sbText(.title)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(when(item).uppercased())
                                    .sbText(.labelDim)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SBPressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("Opens it"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var palette: LightPalette {
        guard let first = items.first else { return .sampleTopScreenshots }
        return .item(category: first.category, colors: first.palette, isSafeToDisplay: first.isSafeToDisplay)
    }

    private func when(_ item: ScreenshotItem) -> String {
        guard let due = item.dueDate else { return CategoryName.title(item.category) }
        return "\(CategoryName.title(item.category)) · \(due.formatted(.dateTime.weekday(.wide)))"
    }
}

/// Asked once, after something's been done, for someone who skipped notifications in onboarding.
struct NudgeOffer: View {
    let time: String
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Want a nudge at \(time) when something's coming up?")
                    .sbText(.title)
                    .fixedSize(horizontal: false, vertical: true)
                Text("One a night, tops.")
                    .sbText(.body)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                Button { onAnswer(true) } label: {
                    Text("Yes, nudge me")
                        .sbText(.body, color: SBColor.ground)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(SBColor.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(SBPressStyle())
                Button { onAnswer(false) } label: {
                    Text("No thanks")
                        .sbText(.body, color: SBColor.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(SBColor.warm(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(SBPressStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous).fill(SBColor.surface))
    }
}
