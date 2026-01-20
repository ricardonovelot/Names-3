import Foundation
import UIKit

final class OnboardingManager {
    static let shared = OnboardingManager()
    
    private let hasCompletedOnboardingKey = "Names3.hasCompletedOnboarding"
    private let onboardingVersionKey = "Names3.onboardingVersion"
    private let currentVersion = 1
    
    private init() {}
    
    var hasCompletedOnboarding: Bool {
        get {
            let completed = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
            let version = UserDefaults.standard.integer(forKey: onboardingVersionKey)
            return completed && version >= currentVersion
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey)
            if newValue {
                UserDefaults.standard.set(currentVersion, forKey: onboardingVersionKey)
            }
        }
    }
    
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: onboardingVersionKey)
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}