import XCTest

/// Exports PNGs of screens for design review. Not a regression test: it never compares images.
///
/// Environment (pass from xcodebuild with a `TEST_RUNNER_` prefix):
/// - `SB_SNAPSHOT_ROUTES`: comma-separated routes (see `SnapshotGallery` in the app). Default `root`.
/// - `SB_SNAPSHOT_APPEARANCES`: comma-separated, `light` and/or `dark`. Default `light,dark`.
/// - `SB_SNAPSHOT_DIR`: directory to write `<route>-<appearance>.png` into. Screenshots are also
///   attached to the result bundle.
final class SnapshotExportTests: XCTestCase {
    @MainActor
    func testExportSnapshots() throws {
        let environment = ProcessInfo.processInfo.environment
        let routes = list(environment["SB_SNAPSHOT_ROUTES"], default: ["root"])
        let appearances = list(environment["SB_SNAPSHOT_APPEARANCES"], default: ["light", "dark"])
        let outputDirectory = environment["SB_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        var failures: [String] = []
        for route in routes {
            for appearance in appearances {
                let app = XCUIApplication()
                app.launchArguments = ["-SBSnapshot", route, "-SBAppearance", appearance]
                app.launch()
                // Let the first frames of the light fields render.
                Thread.sleep(forTimeInterval: 2)
                guard app.state == .runningForeground else {
                    // Crashed: note it and carry on with the other screens.
                    failures.append("\(route)-\(appearance)")
                    continue
                }

                let name = "\(route)-\(appearance)"
                let screenshot = XCUIScreen.main.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
                if let outputDirectory {
                    try screenshot.pngRepresentation.write(to: outputDirectory.appendingPathComponent("\(name).png"))
                }
                app.terminate()
            }
        }
        if let outputDirectory, !failures.isEmpty {
            try failures.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("failures.txt"), atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(failures.isEmpty, "These screens didn't render: \(failures.joined(separator: ", "))")
    }

    private func list(_ value: String?, default fallback: [String]) -> [String] {
        let items = (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? fallback : items
    }
}
