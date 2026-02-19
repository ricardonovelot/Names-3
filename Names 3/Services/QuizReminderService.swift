import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted when the user taps the quiz reminder notification. ContentView should switch to practice tab and show the choose-practice-mode view.
    static let quizReminderTapped = Notification.Name("Names3.QuizReminderTapped")
}

private let pendingQuizReminderTapKey = "Names3.pendingQuizReminderTap"

extension QuizReminderService {
    /// When the user taps the quiz notification before ContentView is mounted (e.g. cold start), we store this flag.
    /// ContentView checks it on appear and navigates to choose practice mode.
    static var hasPendingQuizReminderTap: Bool {
        get { UserDefaults.standard.bool(forKey: pendingQuizReminderTapKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingQuizReminderTapKey) }
    }
}

/// Schedules a single daily local notification to remind the user to practice (Face Quiz or Memory Rehearsal).
/// Permission is requested only once, after the user completes their first quiz of any type.
/// User can enable/disable the reminder in Settings; one notification per day regardless of quiz type.
final class QuizReminderService {
    static let shared = QuizReminderService()
    
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let hasRequestedQuizReminderPermission = "quiz_reminder_permission_requested"
        /// User preference: daily practice reminder on/off. Default true when key missing (existing users keep reminder on).
        static let isDailyReminderEnabled = "quiz_reminder_enabled"
        /// Number of times the user has exited the quiz view. Used to prompt for notifications on 2nd exit.
        static let quizExitCount = "quiz_reminder_exit_count"
    }
    
    /// Identifier for the one daily reminder. Reused so we never have more than one pending.
    /// Exposed so AppDelegate can recognize it when the user taps the notification.
    static let dailyReminderIdentifier = "quiz_daily_reminder"
    
    /// Default time for the daily reminder (9:00 AM local).
    private static let defaultReminderHour = 9
    private static let defaultReminderMinute = 0
    
    private init() {}
    
    // MARK: - User preference (Settings toggle)
    
    /// Whether the user wants the daily practice reminder. When false, no notification is scheduled.
    var isDailyReminderEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.isDailyReminderEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.isDailyReminderEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.isDailyReminderEnabled)
            if !newValue {
                removePendingQuizReminder()
            } else {
                enableAndScheduleDailyReminder()
            }
        }
    }
    
    /// Turns the daily reminder on: requests permission if needed, then schedules. If permission is denied, opens System Settings.
    /// Call when user toggles the reminder ON in Settings.
    func enableAndScheduleDailyReminder() {
        defaults.set(true, forKey: Keys.isDailyReminderEnabled)
        getAuthorizationStatus { [weak self] status in
            guard let self else { return }
            switch status {
            case .authorized, .provisional:
                self.scheduleDailyReminder()
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        self.scheduleDailyReminder()
                    }
                }
            case .denied, .ephemeral:
                DispatchQueue.main.async {
                    self.openAppNotificationSettings()
                }
            @unknown default:
                break
            }
        }
    }
    
    /// Turns the daily reminder off: removes the pending notification and saves preference.
    func disableDailyReminder() {
        defaults.set(false, forKey: Keys.isDailyReminderEnabled)
        removePendingQuizReminder()
    }
    
    /// Opens the app’s notification settings in System Settings (pro pattern when permission is denied).
    func openAppNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
    }
    
    /// Fetches current notification authorization status on a background queue and calls the handler on main.
    func getAuthorizationStatus(handler: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                handler(settings.authorizationStatus)
            }
        }
    }
    
    // MARK: - First-time user: prompt on 2nd quiz exit
    
    /// Call each time the user exits the quiz view (completes or taps X). On the second exit,
    /// requests notification permission and, if granted, schedules the daily reminder.
    func maybeRequestPermissionOnQuizExit() {
        guard !defaults.bool(forKey: Keys.hasRequestedQuizReminderPermission) else { return }
        
        let count = defaults.integer(forKey: Keys.quizExitCount) + 1
        defaults.set(count, forKey: Keys.quizExitCount)
        
        guard count >= 2 else { return }
        
        defaults.set(true, forKey: Keys.hasRequestedQuizReminderPermission)
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            guard let self, granted else { return }
            if self.isDailyReminderEnabled {
                self.scheduleDailyReminder()
            }
        }
    }
    
    /// Schedules a single daily notification at the default time. Replaces any existing quiz reminder.
    func scheduleDailyReminder() {
        removePendingQuizReminder()
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("quiz_reminder_title", value: "Time to practice", comment: "Daily quiz reminder notification title")
        content.body = NSLocalizedString("quiz_reminder_body", value: "Keep your streak going — do a quick Face Quiz or Memory Rehearsal.", comment: "Daily quiz reminder body")
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = Self.defaultReminderHour
        dateComponents.minute = Self.defaultReminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.dailyReminderIdentifier, content: content, trigger: trigger)
        
        center.add(request) { _ in }
    }
    
    /// Removes the single quiz reminder (e.g. when user turns it off in Settings).
    func removePendingQuizReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])
    }
    
    /// Whether we have already asked the user for quiz reminder permission (after first quiz).
    var hasRequestedQuizReminderPermission: Bool {
        defaults.bool(forKey: Keys.hasRequestedQuizReminderPermission)
    }

    /// Call when app enters foreground. If user wants the reminder and has authorized notifications, ensures the daily notification is scheduled (e.g. after they enabled in System Settings).
    func ensureScheduledIfEnabledAndAuthorized() {
        guard isDailyReminderEnabled else { return }
        getAuthorizationStatus { [weak self] status in
            guard let self else { return }
            if status == .authorized || status == .provisional {
                self.scheduleDailyReminder()
            }
        }
    }
}
