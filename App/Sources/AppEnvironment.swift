import Core
import Foundation
import Store

/// The app's long-lived services, created once at launch.
@MainActor
final class AppEnvironment: ObservableObject {
    enum DatabaseState {
        case ready(AppDatabase)
        case failed(String)
    }

    let configuration: AppConfiguration
    let analytics: Analytics
    let database: DatabaseState

    init(configuration: AppConfiguration, analytics: Analytics, database: DatabaseState) {
        self.configuration = configuration
        self.analytics = analytics
        self.database = database
    }

    static func live() -> AppEnvironment {
        let configuration = AppConfiguration.main
        let database: DatabaseState
        do {
            database = .ready(try AppDatabase.openShared(configuration: configuration))
        } catch {
            Log.store.fault("Opening the shared database failed: \(error.localizedDescription, privacy: .public)")
            database = .failed(error.localizedDescription)
        }
        return AppEnvironment(
            configuration: configuration,
            analytics: .telemetryDeck(appID: configuration.telemetryDeckAppID),
            database: database
        )
    }
}
