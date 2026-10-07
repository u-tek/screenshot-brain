import Core
import DesignSystem
import SwiftUI
import UIKit

/// The 9:16 share card: numbers and words only, never a screenshot. A misty ground, one strong
/// smear of the user's colours, a huge thin number and a light/bold line.
public struct ShareCardView: View {
    let story: RevealStory

    public init(story: RevealStory) {
        self.story = story
    }

    public var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 360
            ZStack(alignment: .topLeading) {
                LightField(.sweep(story.palette), grain: 0.06)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6 * unit) {
                        FrameCorners()
                            .stroke(SBColor.ink, style: StrokeStyle(lineWidth: 1.4 * unit, lineCap: .round))
                            .frame(width: 13 * unit, height: 13 * unit)
                        Text("Screenshot Brain")
                            .font(.system(size: 13 * unit, weight: .semibold))
                    }
                    .foregroundStyle(SBColor.ink)
                    Spacer()
                    Text(story.isLimited ? "SCREENSHOTS I PICKED" : "SCREENSHOTS · \(story.periodLabel.uppercased())")
                        .font(.system(size: 10 * unit, weight: .regular, design: .monospaced))
                        .foregroundStyle(SBColor.inkSecondary)
                    Text(story.total.formatted())
                        .font(.system(size: 132 * unit, weight: .ultraLight))
                        .foregroundStyle(SBColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(markup(unit: unit))
                        .font(.system(size: 26 * unit, weight: .light))
                        .foregroundStyle(SBColor.inkLight)
                        .padding(.bottom, 22 * unit)
                    VStack(alignment: .leading, spacing: 4 * unit) {
                        if let peak = story.peakTimeText {
                            row("Peak", peak, unit: unit)
                        }
                        if let top = story.topCategory {
                            row("Mostly", CategoryWords.plural(top), unit: unit)
                        }
                        row("Done", story.doneCount.formatted(), unit: unit)
                    }
                    .padding(.bottom, 26 * unit)
                    Text("@screenshotbrain")
                        .font(.system(size: 11 * unit, weight: .regular))
                        .foregroundStyle(SBColor.inkSecondary)
                }
                .padding(28 * unit)
            }
        }
        .environment(\.colorScheme, .light)
        .environment(\.lightIsStill, true)
    }

    private func markup(unit: CGFloat) -> AttributedString {
        var light = AttributedString("screenshots. ")
        light.foregroundColor = SBColor.inkLight
        var bold = AttributedString("\(story.doneCount) actually done.")
        bold.foregroundColor = SBColor.ink
        bold.font = Font.system(size: 26 * unit, weight: .semibold)
        return light + bold
    }

    private func row(_ label: String, _ value: String, unit: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(label.uppercased())
                .frame(width: 70 * unit, alignment: .leading)
                .foregroundStyle(SBColor.inkSecondary)
            Text(value.uppercased())
                .foregroundStyle(SBColor.ink)
        }
        .font(.system(size: 10 * unit, weight: .regular, design: .monospaced))
    }

    /// Renders the card at 1080×1920 for the share sheet.
    @MainActor
    public static func render(story: RevealStory) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(story: story).frame(width: 360, height: 640))
        renderer.scale = 3
        return renderer.uiImage
    }
}
