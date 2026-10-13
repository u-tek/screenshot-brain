import Core
import Notifications
import Store
import SwiftUI
import UserNotifications

@main
struct ScreenshotBrainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let snapshot = SnapshotMode.current {
                    SnapshotHost(mode: snapshot)
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
            .environmentObject(model)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var lifecycleObservers: [NSObjectProtocol] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ScanScheduler.register()
        NightlyRecap.register()
        UNUserNotificationCenter.current().delegate = self
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SharedAccess.enteredBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SharedAccess.enteredForeground() }
            },
        ]
        return true
    }

    /// Tapping tonight's notification goes where it points (the recap, an item, the paywall).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let kind = response.notification.request.content.threadIdentifier
        guard let link = response.notification.request.content.userInfo["link"] as? String, let url = URL(string: link) else { return }
        await opened(kind: kind)
        await open(url)
    }

    /// Which kind of notification was tapped, as a number (analytics parameters are counts only).
    @MainActor
    private func opened(kind: String) async {
        let number = PlannedNotification.Kind.allCases.firstIndex { $0.rawValue == kind } ?? -1
        Analytics.telemetryDeck(appID: AppConfiguration.main.telemetryDeckAppID).track(.notificationOpened, counts: ["kind": number])
    }

    @MainActor
    private func open(_ url: URL) async {
        if url.host == "recap" {
            Analytics.telemetryDeck(appID: AppConfiguration.main.telemetryDeckAppID).track(.recapOpened)
        }
        await UIApplication.shared.open(url)
    }
}
