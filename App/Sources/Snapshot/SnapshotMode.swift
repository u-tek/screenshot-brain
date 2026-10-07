import DesignSystem
import SwiftUI

/// Opens one screen in a fixed state for the UI snapshot exporter (`UITests/SnapshotExportTests`).
///
/// Launch arguments: `-SBSnapshot <route> -SBAppearance light|dark`. Arguments in this form land in
/// the `UserDefaults` argument domain, so they never persist.
struct SnapshotMode: Sendable {
    enum Appearance: String, Sendable {
        case light
        case dark

        var colorScheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

    let route: String
    let appearance: Appearance

    static let current: SnapshotMode? = {
        let defaults = UserDefaults.standard
        guard let route = defaults.string(forKey: "SBSnapshot"), !route.isEmpty else { return nil }
        let appearance = defaults.string(forKey: "SBAppearance").flatMap(Appearance.init(rawValue:)) ?? .light
        return SnapshotMode(route: route, appearance: appearance)
    }()
}

/// Every screen the exporter can open, by route name.
@MainActor
enum SnapshotGallery {
    static func view(for route: String) -> AnyView? {
        switch route {
        case "root":
            return AnyView(RootView())
        case "welcome":
            return AnyView(WelcomeScreen())
        case "question1":
            return AnyView(GuessQuestionScreen())
        case "lab":
            return AnyView(DesignLabView())
        default:
            guard route.hasPrefix("lab."), let page = DesignLabPage(rawValue: String(route.dropFirst(4))) else {
                return nil
            }
            return AnyView(page.view.background(
                LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            ))
        }
    }
}

struct SnapshotHost: View {
    let mode: SnapshotMode

    var body: some View {
        Group {
            if let view = SnapshotGallery.view(for: mode.route) {
                view
            } else {
                Text("Unknown snapshot route \(mode.route)")
            }
        }
        .preferredColorScheme(mode.appearance.colorScheme)
        .onAppear {
            UIView.setAnimationsEnabled(false)
        }
    }
}
