import Foundation
import UIKit

struct OnboardingPage {
    let title: String
    let description: String
    let imageName: String
    let backgroundColor: UIColor
    let imageBackgroundColor: UIColor
    /// When true, this page shows the photos preview and requests permission on Continue.
    let isPhotosPage: Bool
    
    init(title: String, description: String, imageName: String, backgroundColor: UIColor, imageBackgroundColor: UIColor, isPhotosPage: Bool = false) {
        self.title = title
        self.description = description
        self.imageName = imageName
        self.backgroundColor = backgroundColor
        self.imageBackgroundColor = imageBackgroundColor
        self.isPhotosPage = isPhotosPage
    }
    
    static let pages: [OnboardingPage] = [
        OnboardingPage(
            title: NSLocalizedString("onboarding.page1.title", comment: "Onboarding page 1 title"),
            description: NSLocalizedString("onboarding.page1.description", comment: "Onboarding page 1 description"),
            imageName: "person.2.fill",
            backgroundColor: UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
        ),
        OnboardingPage(
            title: NSLocalizedString("onboarding.page2.title", comment: "Onboarding page 2 title"),
            description: NSLocalizedString("onboarding.page2.description", comment: "Onboarding page 2 description"),
            imageName: "note.text",
            backgroundColor: UIColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 1.0)
        ),
        OnboardingPage(
            title: NSLocalizedString("onboarding.page3.title", comment: "Onboarding page 3 title"),
            description: NSLocalizedString("onboarding.page3.description", comment: "Onboarding page 3 description"),
            imageName: "lock.shield.fill",
            backgroundColor: UIColor(red: 0.08, green: 0.1, blue: 0.12, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1.0)
        ),
        OnboardingPage(
            title: NSLocalizedString("onboarding.page4.photos.title", comment: "Onboarding photos page title"),
            description: NSLocalizedString("onboarding.page4.photos.description", comment: "Onboarding photos page description"),
            imageName: "photo.on.rectangle.angled",
            backgroundColor: UIColor(red: 0.1, green: 0.08, blue: 0.18, alpha: 1.0),
            imageBackgroundColor: UIColor(red: 0.4, green: 0.3, blue: 0.7, alpha: 1.0),
            isPhotosPage: true
        )
    ]
}