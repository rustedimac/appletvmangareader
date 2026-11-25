import UIKit
import MangaCore

/// Silent pushes from the iCloud zone subscription start a sync. Only
/// registers in builds with an iCloud container; without the Push
/// Notifications capability registration just fails and the app keeps
/// syncing on launch, on wake and after changes.
final class SyncAppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static weak var controller: CloudSyncController?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if CloudSyncAvailability.containerIdentifier() != nil,
           !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            Self.controller?.syncNow()
            completionHandler(.newData)
        }
    }
}
