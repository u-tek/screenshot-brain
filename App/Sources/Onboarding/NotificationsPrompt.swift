import DesignSystem
import SwiftUI

/// Our pre-prompt for notifications, then iOS's.
struct NotificationsPrompt: View {
    var palette: LightPalette = .sampleTopScreenshots
    var recapMinutes: Int = 21 * 60 + 30
    var onAllow: () -> Void = {}
    var onSkip: () -> Void = {}

    var body: some View {
        QuestionLayout(
            label: "Your recap",
            headline: "A nudge at **\(WindDownQuestion.timeText(recapMinutes))?**",
            subtext: "One a night at most, and only when there's something new. **Never** \u{201C}don't forget to check the app.\u{201D}",
            light: .sweep(palette.reversed).mirrored(),
            palette: palette,
            footnote: "Change the time any time in Settings",
            actionTitle: "Yes, nudge me",
            onSkip: onSkip,
            onNext: onAllow
        ) {
            FrostedCard(palette: palette) {
                VStack(alignment: .leading, spacing: 6) {
                    SmallLabel("Tonight, for example")
                    Text("That gig you saved is Friday. Still going?")
                        .font(SBFont.body(16, weight: .semibold))
                        .foregroundStyle(SBColor.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
        }
    }
}

/// How to add the widget: the hero of the whole thing.
struct WidgetGuide: View {
    var palette: LightPalette = .sampleTopScreenshots
    var onDone: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 620
            ZStack {
                LightField(.sweep(palette), drifts: true)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    SmallLabel("The widget")
                        .padding(.top, 16)
                        .padding(.bottom, 10)
                    MistHeadline("Tick things off **from your home screen.**", size: compact ? 28 : 32, alignment: .leading)
                        .padding(.bottom, 22)

                    WidgetPreview(palette: palette)
                        .frame(height: compact ? 150 : 170)
                        .padding(.bottom, 22)

                    DataRows([
                        ("01", "Touch and hold your home screen"),
                        ("02", "Tap Edit, then Add Widget"),
                        ("03", "Find Screenshot Brain, pick medium"),
                    ])

                    Spacer()
                    ActionBar("Done, take me home", palette: palette, action: onDone)
                        .padding(.horizontal, -12)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 24)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// What the medium widget looks like, drawn with the app's own components.
struct WidgetPreview: View {
    let palette: LightPalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        HStack(spacing: 12) {
            LightField(.glow(.category(.event)), grain: 0.04)
                .frame(width: 84)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SBColor.warm(0.14), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text("Events")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SBColor.ink.opacity(0.8))
                Text("Mallrat at the Enmore")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SBColor.ink)
                Text("FRIDAY")
                    .font(SBFont.mono(10))
                    .foregroundStyle(SBColor.inkSecondary)
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    DropMark(size: 32)
                    Text("Keep")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SBColor.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .sbGlass(in: Capsule())
                    Spacer(minLength: 0)
                    DoneMark(size: 32)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sbGlass(in: FolderTabShape(tabWidth: 70, tabHeight: 22, radius: 18))
        }
        .padding(10)
        .background {
            LightField(.bloom(.category(.event)).shifted(down: -0.1), grain: 0.04)
                .clipShape(shape)
        }
        .overlay(shape.strokeBorder(SBColor.warm(0.14), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(Text("A preview of the widget, showing a saved gig with Drop, Keep and Done buttons"))
    }
}
