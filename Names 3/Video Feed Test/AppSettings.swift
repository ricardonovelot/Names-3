import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @Published var showDownloadOverlay: Bool {
        didSet { UserDefaults.standard.set(showDownloadOverlay, forKey: Self.kShowOverlay) }
    }
    
    private static let kShowOverlay = "settings.showDownloadOverlay"
    
    init() {
        if UserDefaults.standard.object(forKey: Self.kShowOverlay) == nil {
            UserDefaults.standard.set(true, forKey: Self.kShowOverlay)
        }
        self.showDownloadOverlay = UserDefaults.standard.bool(forKey: Self.kShowOverlay)
    }
}