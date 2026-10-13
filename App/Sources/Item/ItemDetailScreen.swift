import Actions
import Core
import DesignSystem
import Media
import PhotosUI
import Store
import SwiftUI
import Triage
import UIKit

/// One saved thing: what it is, the screenshot in a lit tile, what was read from it, and what to
/// do about it.
struct ItemDetailScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var item: ScreenshotItem?
    @State private var isMissing = false
    @State private var showsEventEditor = false
    @State private var showsCookMode = false
    @State private var sendItems: [Any]?
    @State private var note: String?
    /// The did-it log's entry, once it's done.
    @State private var entry: DoneEntry?
    let itemID: String
    var onChange: () -> Void = {}
    /// Shown instead of loading from the database (design snapshots).
    var preview: ScreenshotItem?
    var previewEntry: DoneEntry?
    /// Opens the plans, for the premium-only "Cook it" when it isn't on yet.
    var onShowPlans: () -> Void = {}

    var body: some View {
        ZStack {
            if let item {
                content(item)
            } else if isMissing {
                missing
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            item = preview ?? (try? model.services?.database.item(id: itemID))
            entry = previewEntry ?? (try? model.services?.database.doneEntry(forItem: itemID))
            isMissing = item == nil
        }
        .sheet(isPresented: $showsEventEditor) {
            if let item, let draft = EventDraft(item: item) {
                EventEditor(draft: draft) { saved in
                    showsEventEditor = false
                    if saved {
                        model.analytics.track(.actionCalendar)
                        flash("In your calendar.")
                    }
                }
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $showsCookMode) {
            if let item {
                CookModeScreen(item: item) {
                    Haptics.done()
                    decide(.done, item)
                }
            }
        }
        .sheet(isPresented: Binding(get: { sendItems != nil }, set: { if !$0 { sendItems = nil } })) {
            if let sendItems {
                ActivitySheet(items: sendItems) { sent in
                    if sent { model.analytics.track(.actionSend) }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// A link to something that's been deleted since: say so, with a way back.
    private var missing: some View {
        VStack(alignment: .leading, spacing: 12) {
            SBNavHeader(onLeading: { dismiss() })
                .padding(.horizontal, -SBSpace.gutter)
            Spacer()
            MistHeadline("This one's **gone.**", size: 30, alignment: .leading)
            MistBody("It may have been deleted, here or in Photos.", alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, SBSpace.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sbScreen()
    }

    private func content(_ item: ScreenshotItem) -> some View {
        let kind = SBKind(item.category)
        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SBNavHeader(onLeading: { dismiss() }) {
                        decisionMenu(item)
                    }
                    .padding(.horizontal, -SBSpace.gutter)

                    // What it is: the kind and when, the name, and the day for events.
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(kind.core)
                                .frame(width: 6, height: 6)
                                .shadow(color: kind.core, radius: 4)
                            SBLabel("\(CategoryName.title(item.category)) · Saved \(item.createdAt.formatted(.relative(presentation: .named)))", dim: false)
                        }
                        Text(item.title ?? "Something you saved")
                            .sbText(.large)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                        if let day = dayLine(item) {
                            Text(day)
                                .sbText(.body)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // The screenshot, lit from behind in its kind's colour. The tile shows the
                    // light until the screenshot loads (or if it's gone).
                    ZStack {
                        SBColor.surface
                        SBLight(kind.core, width: 260, height: 300, opacity: 0.5, blur: 50)
                        // Whole, not cropped: a landscape or scrolling screenshot keeps all of itself.
                        AssetImage(item.assetLocalID, maxPixelSize: 1400, allowsNetwork: true, contentMode: .fit, backdrop: true)
                            .aspectRatio(9 / 19.5, contentMode: .fit)
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.shot, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: SBRadius.shot, style: .continuous).strokeBorder(SBColor.warm(0.14), lineWidth: 1))
                            .shadow(color: .black.opacity(0.55), radius: 24, y: 24)
                            .padding(.vertical, 22)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous))

                    // What to do, then done, then the details: everything in the page's flow, so
                    // nothing floats over text. Once it's done, what happened comes straight after
                    // "Done", where the button was.
                    if item.state == .done, let entry {
                        primaryAction(item)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        MemorySection(entry: entry, kind: kind, onChange: memoryChanged)
                            .transition(.opacity)
                        actions(item)
                    } else {
                        actions(item)
                        primaryAction(item)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }

                    DataRows(rows(item))
                }
                .padding(.horizontal, SBSpace.gutter)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            // A note after an action ("In your calendar.") floats briefly at the bottom.
            if let note {
                SBToast(note)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .sbScreen(.kind(kind))
    }

    // MARK: Parts

    /// "Today" or the weekday, for events.
    private func dayLine(_ item: ScreenshotItem) -> String? {
        guard let due = item.dueDate, item.category == .event else { return nil }
        return Calendar.current.isDateInToday(due) ? "Today" : due.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func rows(_ item: ScreenshotItem) -> [(String, String)] {
        var rows: [(String, String)] = [("Saved", item.createdAt.formatted(date: .abbreviated, time: .shortened))]
        if let due = item.dueDate {
            rows.append(("When", due.formatted(date: .abbreviated, time: item.dueDateHasTime ? .shortened : .omitted)))
        }
        if let address = item.entities.first(where: { $0.kind == .address })?.text {
            rows.append(("Where", address))
        }
        if let price = item.entities.first(where: { $0.kind == .price })?.text {
            rows.append(("Price", price))
        }
        if let link = ShopLink.detectedURL(for: item)?.host {
            rows.append(("Link", link))
        }
        if let expires = item.expiresAt {
            rows.append(("Expires", expires.formatted(date: .abbreviated, time: .omitted)))
        }
        rows.append(("State", stateText(item.state)))
        return rows
    }

    private func stateText(_ state: ItemState) -> String {
        switch state {
        case .unreviewed: "Not decided yet"
        case .stillWant: "Still want"
        case .done: "Done"
        case .dropped: "Dropped"
        case .reference: "Filed away"
        }
    }

    /// What to do about it: the first action as a solid pill, the rest as outlined pills in rows of
    /// up to three, all lit in the item's kind.
    private func actions(_ item: ScreenshotItem) -> some View {
        let available = ItemAction.available(for: item)
        let kind = SBKind(item.category)
        let rest = Array(available.dropFirst())
        let rows = stride(from: 0, to: rest.count, by: 3).map { Array(rest[$0..<min($0 + 3, rest.count)]) }
        return VStack(alignment: .leading, spacing: SBSpace.gap) {
            if !available.isEmpty {
                SBLabel("Do it")
                    .padding(.bottom, 4)
            }
            if let first = available.first {
                SBScenarioButton(
                    first.shortTitle,
                    icon: SBIcon(systemName: first.systemImage),
                    color: kind.core,
                    fill: LinearGradient(colors: [SBRamp.r4, kind.core], startPoint: UnitPoint(x: 0, y: 0.4), endPoint: UnitPoint(x: 1, y: 0.6))
                ) {
                    run(first, on: item)
                }
                .accessibilityLabel(Text(first.title))
            }
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: SBSpace.gap) {
                    ForEach(rows[index]) { action in
                        SBScenarioButton(action.shortTitle, icon: SBIcon(systemName: action.systemImage), color: kind.core) {
                            run(action, on: item)
                        }
                        .accessibilityLabel(Text(action.title))
                    }
                }
            }
            if item.category == .recipe {
                cookButton(kind: kind)
            }
        }
    }

    /// "Cook it": step-by-step cook mode. Premium; the lock shows until it's on.
    private func cookButton(kind: SBKind) -> some View {
        let isPremium = model.isPremium
        return Button {
            Haptics.selection()
            if isPremium {
                showsCookMode = true
            } else {
                onShowPlans()
            }
        } label: {
            SBScenarioLabel("Cook it", icon: .system("flame"), color: kind.core)
                .overlay(alignment: .trailing) {
                    if !isPremium {
                        SBIconView(.system("lock"), size: 16)
                            .foregroundStyle(SBColor.ink2)
                            .padding(.trailing, 16)
                    }
                }
        }
        .buttonStyle(SBPressStyle())
        .accessibilityLabel(Text(isPremium ? "Cook it" : "Cook it, Premium"))
    }

    private func decisionMenu(_ item: ScreenshotItem) -> some View {
        Menu {
            Button { decide(.stillWant, item) } label: { Label("Still want", systemImage: "heart") }
            Button { decide(.dropped, item) } label: { Label("Drop", systemImage: "xmark") }
            if item.state != .reference {
                Button { decide(.reference, item) } label: { Label("File away", systemImage: "archivebox") }
            }
        } label: {
            SBCircleLabel(.more)
        }
        .accessibilityLabel(Text("More"))
    }

    @ViewBuilder
    private func primaryAction(_ item: ScreenshotItem) -> some View {
        if item.state == .reference {
            // Filed away: there's nothing to mark done. "Still want" in the menu brings it back.
            EmptyView()
        } else if item.state == .done {
            ActionBar("Done. Undo?", systemImage: "arrow.uturn.backward", palette: palette(item)) {
                decide(.stillWant, item)
            }
        } else {
            ActionBar("Mark it done", systemImage: "checkmark", palette: palette(item)) {
                Haptics.done()
                decide(.done, item)
            }
        }
    }

    // MARK: Doing things

    private func palette(_ item: ScreenshotItem) -> LightPalette {
        .item(category: item.category, colors: item.palette, isSafeToDisplay: item.isSafeToDisplay)
    }

    private func decide(_ state: ItemState, _ item: ScreenshotItem) {
        guard let database = model.services?.database else { return }
        _ = try? database.decide(state, forItem: item.id)
        withAnimation(SBMotion.snappy) {
            self.item = try? database.item(id: item.id)
            entry = try? database.doneEntry(forItem: item.id)
        }
        model.itemsChanged()
        onChange()
    }

    /// A photo or note added: show it, and let Home's log know.
    private func memoryChanged(_ updated: DoneEntry) {
        withAnimation(SBMotion.snappy) { entry = updated }
        onChange()
    }

    private func run(_ action: ItemAction, on item: ScreenshotItem) {
        Haptics.selection()
        switch action {
        case .calendar:
            Task {
                if await CalendarAccess.prepare() {
                    showsEventEditor = true
                } else {
                    flash("Calendar access is off. You can turn it on in Settings.")
                }
            }
        case .maps:
            model.analytics.track(.actionMaps)
            Task { await MapsAction.open(item) }
        case .shop, .lookUp:
            if let url = ShopLink.url(for: item) {
                model.analytics.track(.actionShop)
                openURL(url)
            }
        case .ingredients:
            let lines = Ingredients.lines(in: item.extractedText ?? "")
            guard !lines.isEmpty else {
                flash("Couldn't find any ingredients.")
                return
            }
            UIPasteboard.general.string = lines.joined(separator: "\n")
            model.analytics.track(.actionCopyIngredients)
            Haptics.success()
            flash(lines.count == 1 ? "Copied 1 ingredient." : "Copied \(lines.count) ingredients.")
        case .send:
            Task {
                let image = await AssetImageLoader.image(localIdentifier: item.assetLocalID, maxPixelSize: 1600, allowsNetwork: true)
                var items: [Any] = []
                if let image {
                    items.append(UIImage(cgImage: image))
                }
                items.append(SendMessage.text)
                sendItems = items
            }
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
