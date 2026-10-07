import Core
import DesignSystem
import Store
import SwiftUI
import WidgetCore
import WidgetKit

/// Keeps the widget fresh: pre-renders the light for anything it might show (widgets can't run
/// the app's light), then tells WidgetKit to reload.
enum WidgetRefresher {
    /// Light images are small: the widget only ever shows them softly behind glass.
    static let lightSize = CGSize(width: 180, height: 90)

    @MainActor
    static func refresh(services: AppServices) async {
        renderLights(for: (try? services.database.widgetCandidates(now: Date(), includeSurfaced: true)) ?? [])
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    static func renderLights(for items: [ScreenshotItem]) {
        guard let directory = try? AppGroup.directory(.widgetLight) else { return }
        let fileManager = FileManager.default
        for category in ItemCategory.allCases {
            let url = directory.appendingPathComponent(WidgetLight.fileName(for: category))
            if !fileManager.fileExists(atPath: url.path) {
                write(.category(category), to: url)
            }
        }
        for item in items {
            let url = directory.appendingPathComponent(WidgetLight.fileName(forItem: item.id))
            guard !fileManager.fileExists(atPath: url.path) else { continue }
            write(.item(category: item.category, colors: item.palette, isSafeToDisplay: item.isSafeToDisplay), to: url)
        }
    }

    @MainActor
    private static func write(_ palette: LightPalette, to url: URL) {
        let view = LightField(.bloom(palette).shifted(down: -0.05), ground: false, grain: 0.05)
            .frame(width: lightSize.width, height: lightSize.height)
            .environment(\.lightIsStill, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = false
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }
}
