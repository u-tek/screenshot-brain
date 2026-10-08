import BackgroundTasks
import Core
import Foundation
import ScanEngine
import Store

/// The app's long-lived, thread-safe services. Shared by the UI and background tasks.
final class AppServices: Sendable {
    /// Nil only if the database can't be opened, which the UI reports.
    static let shared: AppServices? = {
        do {
            return try AppServices()
        } catch {
            Log.store.fault("Opening the shared database failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    let database: AppDatabase
    let pipeline: ScanPipeline

    private init() throws {
        database = try AppDatabase.openShared()
        pipeline = ScanPipeline(database: database)
    }
}

/// Background task identifiers, always taken from Info.plist's list. Sideloading can change the
/// bundle ID, and registering an identifier the list doesn't contain crashes the app at launch.
enum BackgroundTaskID {
    static func permitted(suffix: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?
            .first { $0.hasSuffix(suffix) }
    }
}

/// Reads new screenshots in the background, so the widget and the recap stay fresh.
enum ScanScheduler {
    static var identifier: String? {
        BackgroundTaskID.permitted(suffix: ".scan")
    }

    /// Must run before the app finishes launching.
    static func register() {
        guard let identifier else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task)
        }
    }

    static func schedule() {
        guard let identifier else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.scan.error("Couldn't schedule the background scan: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGTask) {
        schedule()
        let box = BackgroundTaskBox(task)
        guard let services = AppServices.shared, ScreenshotLibrary.currentAccess() == .full || ScreenshotLibrary.currentAccess() == .limited else {
            box.task.setTaskCompleted(success: true)
            return
        }
        let work = Task {
            let succeeded = await SharedAccess.hold("Background scan") { () async -> Bool in
                do {
                    try services.pipeline.discover()
                    try await services.pipeline.readPending(includeBackfill: true)
                    await WidgetRefresher.refresh(services: services)
                    return true
                } catch {
                    return false
                }
            }
            box.task.setTaskCompleted(success: succeeded)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}

/// `BGTask` isn't Sendable, but completing it from the work task is how the API is meant to be used.
private final class BackgroundTaskBox: @unchecked Sendable {
    let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }
}
