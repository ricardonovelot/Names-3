import UIKit
import Photos
import UserNotifications
import os
import os.signpost

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let launchLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Launch")

    /// Observer that invalidates Name Faces carousel cache when the photo library changes.
    private var nameFacesCacheInvalidationObserver: PHPhotoLibraryChangeObserver?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        installUncaughtExceptionHandler()
        UNUserNotificationCenter.current().delegate = self
        let t0 = CFAbsoluteTimeGetCurrent()
        let signpostState = LaunchProfiler.beginPhase("DidFinishLaunching")
        LaunchProfiler.logCheckpoint("didFinishLaunching started (\(LaunchProfiler.mainThreadTag))")

        // Photo library observer is registered in post-launch (see Names_3App .task).

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        LaunchProfiler.endPhase("DidFinishLaunching", signpostState)
        LaunchProfiler.logCheckpoint("didFinishLaunching done in \(String(format: "%.3f", elapsed))s")
        Self.launchLogger.info("✅ App launched")

        // Process report pipeline: init coordinator (registers stateless reporters + memory warning observer)
        ProcessReportCoordinator.shared.reportAll(trigger: "launch")

        return true
    }

    /// Log ObjC uncaught exceptions (and re-raise). Does not catch Swift fatalError/force-unwrap.
    private func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "nil"
            let name = exception.name.rawValue
            let symbols = (exception.callStackSymbols as [String]).joined(separator: "\n")
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Crash")
                .critical("Uncaught exception: \(name) – \(reason)\n\(symbols)")
            // Re-raise so default behavior (e.g. crash report) still happens
            NSSetUncaughtExceptionHandler(nil)
            exception.raise()
        }
    }
    
    // MARK: - Post-launch (deferred from didFinishLaunching for fast launch)

    // MARK: - Notification tap handling (quiz reminder → choose practice mode)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        if identifier == QuizReminderService.dailyReminderIdentifier {
            QuizReminderService.hasPendingQuizReminderTap = true
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .quizReminderTapped, object: nil)
            }
        }
        completionHandler()
    }

    // MARK: - Post-launch (deferred from didFinishLaunching for fast launch)

    /// Registers the photo library change observer for Name Faces cache invalidation.
    /// Call from post-launch (e.g. WindowGroup .task) so didFinishLaunching stays minimal.
    func registerPhotoLibraryObserverIfNeeded() {
        guard nameFacesCacheInvalidationObserver == nil else { return }
        nameFacesCacheInvalidationObserver = PhotoLibraryService.shared.observeChanges {
            UserDefaults.standard.set(true, forKey: WelcomeFaceNamingViewController.cacheInvalidatedKey)
        }
        Self.launchLogger.info("🚀 [Launch] Photo library observer registered (post-launch)")
    }
}