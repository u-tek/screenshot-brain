import Core
import Store
import SwiftUI

@main
struct ScreenshotBrainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            Group {
                if let snapshot = SnapshotMode.current {
                    SnapshotHost(mode: snapshot)
                } else {
                    RootView()
                }
            }
            .environmentObject(environment)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private var lifecycleObservers: [NSObjectProtocol] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                AppDatabase.suspendSharedAccess()
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                AppDatabase.resumeSharedAccess()
            },
        ]
        return true
    }
}
