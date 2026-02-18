import SwiftUI
import Combine
import UIKit

/// Publishes keyboard height for layout that treats the keyboard as a permanent element.
/// Use when the keyboard is always visible (e.g. quiz input) and the UI must fit above it.
@MainActor
final class KeyboardHeightObserver: ObservableObject {
    static let shared = KeyboardHeightObserver()
    
    @Published private(set) var keyboardHeight: CGFloat = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let show = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        let hide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        let change = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        
        Publishers.Merge3(show, hide, change)
            .compactMap { note -> CGFloat? in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return nil }
                let screenHeight = UIScreen.main.bounds.height
                let keyboardTop = frame.origin.y
                let height = screenHeight - keyboardTop
                return height > 50 ? height : 0
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.keyboardHeight, on: self)
            .store(in: &cancellables)
    }
    
    /// True when keyboard is visible (typical height ~291pt on iPhone)
    var isKeyboardVisible: Bool { keyboardHeight > 50 }
    
    /// Typical keyboard height when visible; use for initial layout before notification fires.
    static let typicalKeyboardHeight: CGFloat = 291
}
