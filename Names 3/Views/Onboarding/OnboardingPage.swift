import Foundation
import UIKit

struct OnboardingPage {
    let title: String
    let description: String
    let imageName: String
    let backgroundColor: UIColor
    let imageBackgroundColor: UIColor
    
    static let pages: [OnboardingPage] = [
        OnboardingPage(
            title: NSLocalizedString("onboarding.page1.title", comment: "Onboarding page 1 title"),
            description: NSLocalizedString("onboarding.page1.description", comment: "Onboarding page 1 description"),
            imageName: "person.3.fill",
            backgroundColor: UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
        ),
        OnboardingPage(
            title: NSLocalizedString("onboarding.page2.title", comment: "Onboarding page 2 title"),
            description: NSLocalizedString("onboarding.page2.description", comment: "Onboarding page 2 description"),
            imageName: "camera.fill",
            backgroundColor: UIColor(red: 0.15, green: 0.1, blue: 0.15, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1.0)
        ),
        OnboardingPage(
            title: NSLocalizedString("onboarding.page3.title", comment: "Onboarding page 3 title"),
            description: NSLocalizedString("onboarding.page3.description", comment: "Onboarding page 3 description"),
            imageName: "mappin.and.ellipse",
            backgroundColor: UIColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 1.0)
        ),
        OnboardingPage(
            title: NSLocalizedString("onboarding.page4.title", comment: "Onboarding page 4 title"),
            description: NSLocalizedString("onboarding.page4.description", comment: "Onboarding page 4 description"),
            imageName: "note.text",
            backgroundColor: UIColor(red: 0.15, green: 0.1, blue: 0.1, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1.0)
        ),
        OnboardingPage(
            title: NSLocalizedString("onboarding.page5.title", comment: "Onboarding page 5 title"),
            description: NSLocalizedString("onboarding.page5.description", comment: "Onboarding page 5 description"),
            imageName: "brain.head.profile",
            backgroundColor: UIColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 0.0, green: 0.8, blue: 0.8, alpha: 1.0)
        )
    ]
}