import UIKit
import os.log

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Push")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // For CloudKit push-triggered mirroring; no user-facing permission required.
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        logger.info("Requested registration for remote notifications")
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Registered for remote notifications")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }
}