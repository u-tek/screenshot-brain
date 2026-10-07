import DesignSystem
import SwiftUI

/// The one-screen pitch. The lens enters from the left edge over a pocket of the user's light,
/// with the kinds of things they save orbiting it.
struct WelcomeScreen: View {
    var palette: LightPalette = .sampleTopScreenshots
    var onContinue: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppMark()
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            Spacer()
            SmallLabel("For the things you meant to do")
                .padding(.bottom, 10)
            MistHeadline("You saved it\n**for a reason.**", size: 34, alignment: .leading)
                .padding(.bottom, 28)
            ActionBar("Show me", systemImage: "arrow.up.right", palette: palette, action: onContinue)
                .padding(.horizontal, -12)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .background {
            GeometryReader { proxy in
                let size = proxy.size
                let lensDiameter = size.width * 0.88
                let lensCenter = CGPoint(x: size.width * 0.02, y: size.height * 0.37)
                let orbitDiameter = lensDiameter * 1.16
                let orbitRight = lensCenter.x + orbitDiameter / 2

                ZStack(alignment: .topLeading) {
                    // The light passes behind the lens and out past its rim, so the glass bends it.
                    LightField(.passage(palette), drifts: true)
                    LensOrbit(diameter: orbitDiameter, dotAngle: 0)
                        .position(lensCenter)
                    GlassLens(diameter: lensDiameter)
                        .position(lensCenter)
                    OrbitLabels(active: "That ramen place", above: "That gig on Friday", below: "Those sneakers")
                        .position(x: orbitRight + 32 + OrbitLabels.width / 2, y: lensCenter.y)
                }
                .frame(width: size.width, height: size.height)
            }
            .ignoresSafeArea()
        }
    }
}

/// Three things the lens is reading, the middle one in focus, joined to the orbit by a hairline.
private struct OrbitLabels: View {
    static let width: CGFloat = 156

    let active: String
    let above: String
    let below: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(above)
                .font(SBFont.body(13))
                .foregroundStyle(SBColor.inkSecondary.opacity(0.55))
            HStack(spacing: 10) {
                Rectangle()
                    .fill(SBColor.accent.opacity(0.7))
                    .frame(width: 22, height: 1)
                Text(active)
                    .font(SBFont.body(15, weight: .semibold))
                    .foregroundStyle(SBColor.ink)
            }
            .padding(.leading, -32)
            Text(below)
                .font(SBFont.body(13))
                .foregroundStyle(SBColor.inkSecondary.opacity(0.55))
        }
        .frame(width: Self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
