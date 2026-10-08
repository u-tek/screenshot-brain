import Store
import UIKit

/// The shared database is suspended whenever the app is in the background, so it never holds a
/// lock when iOS suspends the app (which iOS punishes with 0xdead10cc). Work that runs in the
/// background (the background scan, the recap refresh, the replan as the app leaves) holds access
/// open while it runs. When the last holder finishes and the app is still in the background,
/// access is suspended again.
@MainActor
enum SharedAccess {
    private static var holders = 0
    private static var inForeground = UIApplication.shared.applicationState != .background

    static func enteredForeground() {
        inForeground = true
        AppDatabase.resumeSharedAccess()
    }

    static func enteredBackground() {
        inForeground = false
        if holders == 0 {
            AppDatabase.suspendSharedAccess()
        }
    }

    /// Runs `work` (off the main actor) with database access open and background time from iOS
    /// to finish it.
    static func hold<T: Sendable>(_ name: String, _ work: @Sendable () async -> T) async -> T {
        holders += 1
        AppDatabase.resumeSharedAccess()
        let time = BackgroundTime(name)
        let result = await work()
        holders -= 1
        if holders == 0 && !inForeground {
            AppDatabase.suspendSharedAccess()
        }
        time.end()
        return result
    }
}

/// Asks iOS for time to finish after the app leaves the foreground.
@MainActor
private final class BackgroundTime {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(_ name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Out of time: let go of the database now rather than be suspended holding a lock.
            AppDatabase.suspendSharedAccess()
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
