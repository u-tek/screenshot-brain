import Core
import DesignSystem
import SwiftUI

/// Debug sheet with every token, light, glass surface and component, on one scrollable page.
/// Each section is also a snapshot route (`lab.tokens`, `lab.light`, ...).
struct DesignLabView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(DesignLabPage.allCases, id: \.self) { page in
                    page.view
                        .frame(minHeight: 760)
                }
            }
        }
        .background(LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea(edges: .bottom)
    }
}

enum DesignLabPage: String, CaseIterable {
    case tokens
    case light
    case components
    case surfaces

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .tokens: TokensPage()
        case .light: LightPage()
        case .components: ComponentsPage()
        case .surfaces: SurfacesPage()
        }
    }
}

private struct LabSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SmallLabel(title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tokens

private struct Swatch: Identifiable {
    let name: String
    let color: Color
    let hex: String
    var id: String { name }
}

private struct TokensPage: View {
    private let swatches = [
        Swatch(name: "mist", color: SBColor.mistTop, hex: "#F2F2F5"),
        Swatch(name: "ink", color: SBColor.ink, hex: "#16161A"),
        Swatch(name: "ink.light", color: SBColor.inkLight, hex: "#5E5E68"),
        Swatch(name: "ink.2nd", color: SBColor.inkSecondary, hex: "#6B6B76"),
        Swatch(name: "accent", color: SBColor.accent, hex: "#FF6A3D"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            MistHeadline("Design Lab · **Tokens**", size: 30, alignment: .leading)

            LabSection("Ground, ink and accent") {
                HStack(spacing: 10) {
                    ForEach(swatches) { swatch in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(swatch.color)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SBColor.hairline))
                                .frame(height: 56)
                            Text(swatch.name).font(SBFont.body(11, weight: .medium)).foregroundStyle(SBColor.ink)
                            Text(swatch.hex).font(SBFont.mono(10)).foregroundStyle(SBColor.inkSecondary)
                        }
                    }
                }
            }

            LabSection("Category light") {
                HStack(spacing: 10) {
                    ForEach(ItemCategory.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            LightField(.bloom(.category(category)), grain: 0.04)
                                .frame(height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(category.rawValue.capitalized).font(SBFont.body(11, weight: .medium)).foregroundStyle(SBColor.ink)
                        }
                    }
                }
            }

            LabSection("Type") {
                VStack(alignment: .leading, spacing: 14) {
                    MistHeadline("You saved it **for a reason.**", size: 34, alignment: .leading)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("214").font(SBFont.number(84)).foregroundStyle(SBColor.ink)
                        Text("screenshots").font(SBFont.body(17, weight: .semibold)).foregroundStyle(SBColor.ink)
                    }
                    MistBody("Body copy at 15pt with **one bold phrase.**", alignment: .leading)
                    SmallLabel("Small label · 13pt · ink.secondary")
                    Text("SAVED      2026-09-14  21:40").font(SBFont.mono(12)).foregroundStyle(SBColor.inkSecondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}

// MARK: - Light

private struct LightPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MistHeadline("Design Lab · **Light**", size: 30, alignment: .leading)
            LabSection("Sweep (questions) · passage (welcome)") {
                HStack(spacing: 12) {
                    LightField(.sweep(.sampleTopScreenshots))
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    LightField(.passage(.sampleTopScreenshots))
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            LabSection("From screenshots: sunset bar · gig poster · top screenshots") {
                HStack(spacing: 12) {
                    ForEach([LightPalette.sampleSunsetBar, .sampleGigPoster, .sampleTopScreenshots], id: \.self) { palette in
                        LightField(.sweep(palette))
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            LabSection("Glass lens over light") {
                ZStack {
                    LightField(.pocket(.sampleTopScreenshots, center: LightPoint(0.5, 0.5), radius: 0.28, aspect: 0.5))
                    GlassLens(diameter: 124)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}

// MARK: - Components

private struct ComponentsPage: View {
    @State private var guess = 150

    var body: some View {
        ZStack {
            LightField(.sweep(.sampleTopScreenshots))
            VStack(alignment: .leading, spacing: 22) {
                MistHeadline("Design Lab · **Glass**", size: 30, alignment: .leading)
                LabSection("Chip · icon button · done · drop") {
                    HStack(spacing: 12) {
                        Chip("Close entry", closable: true)
                        Chip("Places")
                        GlassIconButton("square.and.arrow.up", label: "Share") {}
                        DoneMark()
                        DropMark()
                    }
                }
                LabSection("Action bar") {
                    ActionBar("Keep going", palette: .sampleTopScreenshots) {}
                }
                LabSection("Ruler") {
                    TickRuler(value: $guess, in: 0...5000, step: 10)
                }
                LabSection("Timeline line · peak hour") {
                    TimelineLine(values: (0..<24).map { hour in Double((hour * 7 + 3) % 10) / 10 }, highlight: 0)
                }
                LabSection("Score") {
                    ScoreView(done: 6, total: 23)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
    }
}

// MARK: - Surfaces

private struct SurfacesPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            MistHeadline("Design Lab · **Surfaces**", size: 30, alignment: .leading)
            LabSection("Folder-tab card (triage, widget)") {
                FolderTabCard(tab: "Events", palette: .sampleGigPoster) {
                    VStack(alignment: .leading, spacing: 6) {
                        MistHeadline("That gig is **this Friday.**", size: 22, alignment: .leading)
                        HStack {
                            Text("FRI 14 NOV · 20:00").font(SBFont.mono(11)).foregroundStyle(SBColor.inkSecondary)
                            Spacer()
                            DropMark(size: 36)
                            DoneMark(size: 36)
                        }
                    }
                }
                .frame(height: 220)
            }
            LabSection("Light tiles (Home)") {
                HStack(spacing: 12) {
                    LightTile("Places", detail: "12 SAVED", palette: .category(.place))
                    LightTile("Products", detail: "7 SAVED", palette: .category(.product))
                }
            }
            LabSection("Frosted card") {
                FrostedCard(palette: .sampleSunsetBar) {
                    VStack(alignment: .leading, spacing: 8) {
                        MistHeadline("You guessed clothes. **It's places.**", size: 22, alignment: .leading)
                        Text("GUESS      clothes\nACTUAL     places · 61").font(SBFont.mono(11)).foregroundStyle(SBColor.inkSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}
