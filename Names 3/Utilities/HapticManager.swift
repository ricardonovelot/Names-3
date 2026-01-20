import UIKit

final class HapticManager {
    static let shared = HapticManager()
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    
    private init() {
        prepare()
    }
    
    func prepare() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selection.prepare()
        notification.prepare()
    }
    
    func lightImpact() {
        impactLight.impactOccurred()
    }
    
    func mediumImpact() {
        impactMedium.impactOccurred()
    }
    
    func heavyImpact() {
        impactHeavy.impactOccurred()
    }
    
    func selection() {
        selection.selectionChanged()
    }
    
    func success() {
        notification.notificationOccurred(.success)
    }
    
    func warning() {
        notification.notificationOccurred(.warning)
    }
    
    func error() {
        notification.notificationOccurred(.error)
    }
}