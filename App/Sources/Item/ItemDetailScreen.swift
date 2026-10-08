import Actions
import Core
import DesignSystem
import Media
import Store
import SwiftUI
import Triage
import UIKit

/// One saved thing: the screenshot lifted over a huge soft blur of itself, what was read from
/// it, and what to do about it.
struct ItemDetailScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var item: ScreenshotItem?
    @State private var isMissing = false
    @State private var showsEventEditor = false
    @State private var sendItems: [Any]?
    @State private var note: String?
    let itemID: String
    var onChange: () -> Void = {}
    /// Shown instead of loading from the database (design snapshots).
    var preview: ScreenshotItem?

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
            GlassIconButton("chevron.left", label: "Back") { dismiss() }
            Spacer()
            MistHeadline("This one's **gone.**", size: 30, alignment: .leading)
            MistBody("It may have been deleted, here or in Photos.", alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LightField(.sweep(model.palette)).ignoresSafeArea())
    }

    private func content(_ item: ScreenshotItem) -> some View {
        ZStack(alignment: .bottom) {
            // A huge, soft blur of the screenshot itself, misted over.
            AssetImage(item.assetLocalID, maxPixelSize: 200)
                .blur(radius: 60)
                .scaleEffect(1.4)
                .opacity(0.8)
                .overlay(LinearGradient(colors: [SBColor.mistTop.opacity(0.45), SBColor.mistBottom.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                .background(LightField(.sweep(palette(item))))
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        GlassIconButton("chevron.left", label: "Back") { dismiss() }
                        Spacer()
                        decisionMenu(item)
                    }

                    // The item's own light shows until the screenshot loads (or if it's gone).
                    AssetImage(item.assetLocalID, maxPixelSize: 1400, allowsNetwork: true)
                        .background(LightField(.glow(palette(item)), grain: 0.04))
                        .aspectRatio(9 / 19.5, contentMode: .fit)
                        .frame(maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: SBRadius.card, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        .shadow(color: .black.opacity(0.06), radius: 40)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        SmallLabel("\(CategoryName.title(item.category)) · Saved \(item.createdAt.formatted(.relative(presentation: .named)))")
                        MistHeadline(headline(item), size: 30, alignment: .leading)
                    }

                    DataRows(rows(item))

                    actions(item)

                    if let note {
                        SmallLabel(note)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }

            primaryAction(item)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    // MARK: Parts

    private func headline(_ item: ScreenshotItem) -> String {
        let title = item.title ?? "Something you saved"
        guard let due = item.dueDate, item.category == .event else { return "**\(title)**" }
        let day = Calendar.current.isDateInToday(due) ? "today" : due.formatted(.dateTime.weekday(.wide))
        return "\(title) is **\(day).**"
    }

    private func rows(_ item: ScreenshotItem) -> [(String, String)] {
        var rows: [(String, String)] = [("Saved", item.createdAt.formatted(date: .abbreviated, time: .shortened))]
        if let due = item.dueDate {
            rows.append(("When", due.formatted(date: .abbreviated, time: .shortened)))
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
        case .reference: "Reference"
        }
    }

    private func actions(_ item: ScreenshotItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ItemAction.available(for: item)) { action in
                    Button {
                        run(action, on: item)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 13, weight: .light))
                            Text(action.shortTitle)
                                .font(SBFont.body(14))
                        }
                        .foregroundStyle(SBColor.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .sbGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(action.title))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    private func decisionMenu(_ item: ScreenshotItem) -> some View {
        Menu {
            Button { decide(.stillWant, item) } label: { Label("Still want", systemImage: "heart") }
            Button { decide(.dropped, item) } label: { Label("Drop", systemImage: "xmark") }
            if item.category != .reference {
                Button { decide(.reference, item) } label: { Label("Just for reference", systemImage: "archivebox") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(SBColor.ink)
                .frame(width: SBRadius.iconButton, height: SBRadius.iconButton)
                .sbGlass(in: Circle())
        }
        .accessibilityLabel(Text("More"))
    }

    @ViewBuilder
    private func primaryAction(_ item: ScreenshotItem) -> some View {
        if item.state == .done {
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
        }
        model.itemsChanged()
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
        case .shop:
            if let url = ShopLink.url(for: item) {
                model.analytics.track(.actionShop)
                openURL(url)
            }
        case .ingredients:
            let lines = Ingredients.lines(in: item.extractedText ?? "")
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
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(SBMotion.settle) {
                if note == text { note = nil }
            }
        }
    }
}
