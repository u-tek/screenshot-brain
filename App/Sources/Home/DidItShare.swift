import Actions
import Core
import DesignSystem
import Store
import SwiftUI
import UIKit

/// A month of the did-it log as a 9:16 card: how many things, and what some of them were. Words
/// only, never a screenshot or a photo, and only things safe to show anyone.
struct DidItShareCard: View {
    let month: DidItMonth
    var palette: LightPalette = .sampleTopScreenshots
    /// Rows the card has room for.
    static let rowLimit = 5

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 360
            let shown = Array(month.entries.filter(\.isShareable).prefix(Self.rowLimit))
            let more = month.entries.count - shown.count
            ZStack(alignment: .topLeading) {
                LightField(.sweep(palette), grain: 0.06)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6 * unit) {
                        SBIconView(.bracket, size: 16 * unit)
                        Text("Screenshot Brain")
                            .font(.system(size: 13 * unit, weight: .semibold))
                    }
                    .foregroundStyle(SBColor.ink)
                    Spacer()
                    Text("DID IT · \(month.start.formatted(.dateTime.month(.wide).year()).uppercased())")
                        .font(.system(size: 10 * unit, weight: .regular, design: .monospaced))
                        .foregroundStyle(SBColor.inkSecondary)
                    Text(month.entries.count.formatted())
                        .font(.system(size: 132 * unit, weight: .light))
                        .foregroundStyle(SBColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(markup(unit: unit))
                        .font(.system(size: 26 * unit, weight: .regular))
                        .foregroundStyle(SBColor.inkLight)
                        .padding(.bottom, 22 * unit)
                    VStack(alignment: .leading, spacing: 5 * unit) {
                        ForEach(shown) { entry in
                            row(DoneWords.verb(entry.category), entry.title ?? DoneWords.fallbackTitle(entry.category), unit: unit)
                        }
                        if more > 0 {
                            row("", "+ \(more) more", unit: unit)
                        }
                    }
                    .padding(.bottom, 26 * unit)
                    Text("@screenshotbrain")
                        .font(.system(size: 11 * unit, weight: .regular))
                        .foregroundStyle(SBColor.inkSecondary)
                }
                .padding(28 * unit)
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.lightIsStill, true)
    }

    private func markup(unit: CGFloat) -> AttributedString {
        let one = month.entries.count == 1
        var light = AttributedString(one ? "thing I kept meaning to do. " : "things I kept meaning to do. ")
        light.foregroundColor = SBColor.inkLight
        var bold = AttributedString(one ? "Did it." : "Did them.")
        bold.foregroundColor = SBColor.ink
        bold.font = Font.system(size: 26 * unit, weight: .regular)
        return light + bold
    }

    private func row(_ label: String, _ value: String, unit: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(label.uppercased())
                .frame(width: 84 * unit, alignment: .leading)
                .foregroundStyle(SBColor.inkSecondary)
            Text(value.uppercased())
                .foregroundStyle(SBColor.ink)
                .lineLimit(1)
        }
        .font(.system(size: 10 * unit, weight: .regular, design: .monospaced))
    }

    /// Renders the card at 1080×1920 for the share sheet.
    @MainActor
    static func render(month: DidItMonth, palette: LightPalette) -> UIImage? {
        let renderer = ImageRenderer(content: DidItShareCard(month: month, palette: palette).frame(width: 360, height: 640))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The card, big enough to read, and the button that shares it.
struct DidItShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let month: DidItMonth
    var palette: LightPalette = .sampleTopScreenshots
    var onShared: () -> Void = {}
    /// Rendered when Share is tapped, not before: drawing the card's light at full size is the
    /// slow part, and the sheet should appear at once.
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            // The card takes what the headline and buttons leave, up to 420 tall.
            let cardHeight = min(420, max(240, proxy.size.height - 250))
            VStack(spacing: 18) {
                Spacer(minLength: 12)
                DidItShareCard(month: month, palette: palette)
                    .frame(width: cardHeight * 9 / 16, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(SBColor.warm(0.14), lineWidth: 1))
                    .accessibilityLabel(Text("Your \(month.name()) card"))
                MistHeadline("Nothing to do here? **Show them.**", size: 28)
                    .padding(.horizontal, 24)
                Spacer(minLength: 12)
                VStack(spacing: 10) {
                    ActionBar("Share \(month.name())", systemImage: "square.and.arrow.up", palette: palette) {
                        image = DidItShareCard.render(month: month, palette: palette)
                    }
                    Button { dismiss() } label: {
                        SBChip("Not now")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sbScreen(.calm)
        .sheet(isPresented: Binding(get: { image != nil }, set: { if !$0 { image = nil } })) {
            if let image {
                ActivitySheet(items: [image]) { shared in
                    if shared { onShared() }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}
