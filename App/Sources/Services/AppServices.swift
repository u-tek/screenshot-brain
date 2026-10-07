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

/// Reads new screenshots in the background, so the widget and the recap stay fresh.
enum ScanScheduler {
    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "ScreenshotBrain") + ".scan"
    }

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task)
        }
    }

    static func schedule() {
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
            do {
                try services.pipeline.discover()
                try await services.pipeline.readPending(includeBackfill: true)
                await WidgetRefresher.refresh(services: services)
                box.task.setTaskCompleted(success: true)
            } catch {
                box.task.setTaskCompleted(success: false)
            }
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
