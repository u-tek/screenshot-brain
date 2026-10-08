import XCTest

/// Exports PNGs of screens for design review. Not a regression test: it never compares images.
///
/// One launch covers every screen: the app shows the first shot, and after each capture the test
/// posts a Darwin notification and the app steps to the next one in place. If a screen crashes
/// the app, it's noted and the app is relaunched with the shots that are left.
///
/// Environment (pass from xcodebuild with a `TEST_RUNNER_` prefix):
/// - `SB_SNAPSHOT_ROUTES`: comma-separated routes (see `SnapshotGallery` in the app).
/// - `SB_SNAPSHOT_APPEARANCES`: comma-separated, `light` and/or `dark`. Default `light,dark`.
/// - `SB_SNAPSHOT_DIR`: directory to write `<route>-<appearance>.png` into.
final class SnapshotExportTests: XCTestCase {
    private static let nextNotification = "com.screenshotbrain.snapshot.next"

    @MainActor
    func testExportSnapshots() throws {
        let environment = ProcessInfo.processInfo.environment
        let routes = list(environment["SB_SNAPSHOT_ROUTES"], default: ["welcome"])
        let appearances = list(environment["SB_SNAPSHOT_APPEARANCES"], default: ["light", "dark"])
        let outputDirectory = environment["SB_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        let shots = routes.flatMap { route in appearances.map { "\(route)@\($0)" } }
        var failures: [String] = []
        var remaining = shots[...]
        let app = XCUIApplication()

        while !remaining.isEmpty {
            app.launchArguments = ["-SBSnapshots", remaining.joined(separator: ",")]
            app.launch()
            // The first frame of the first screen.
            Thread.sleep(forTimeInterval: 2.5)

            var crashed = false
            for (offset, shot) in remaining.enumerated() {
                if offset > 0 {
                    postNext()
                    Thread.sleep(forTimeInterval: 0.9)
                }
                guard app.state == .runningForeground else {
                    // This screen crashed the app: note it and carry on from the next one.
                    failures.append(shot)
                    remaining = remaining.dropFirst(offset + 1)
                    crashed = true
                    break
                }
                let name = shot.replacingOccurrences(of: "@", with: "-")
                let screenshot = XCUIScreen.main.screenshot()
                if let outputDirectory {
                    try screenshot.pngRepresentation.write(to: outputDirectory.appendingPathComponent("\(name).png"))
                } else {
                    // Run from Xcode: keep it in the test report instead.
                    let attachment = XCTAttachment(screenshot: screenshot)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            if !crashed {
                remaining = []
            }
            app.terminate()
        }

        if let outputDirectory, !failures.isEmpty {
            try failures.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("failures.txt"), atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(failures.isEmpty, "These screens didn't render: \(failures.joined(separator: ", "))")
    }

    private func postNext() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.nextNotification as CFString),
            nil,
            nil,
            true
        )
    }

    private func list(_ value: String?, default fallback: [String]) -> [String] {
        let items = (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? fallback : items
    }
}
