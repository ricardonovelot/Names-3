//
//  ShakeDetector.swift
//  Names 3
//
//  Detects device shake for native undo (e.g. contact movement undo).
//

import SwiftUI
import UIKit

// MARK: - View modifier

extension View {
    /// Calls `action` when the user shakes the device. Use for native shake-to-undo.
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetectorModifier(action: action))
    }
}

private struct ShakeDetectorModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .background(ShakeDetectorHost(action: action))
    }
}

// MARK: - Host view that becomes first responder to receive motion events

private struct ShakeDetectorHost: UIViewControllerRepresentable {
    let action: () -> Void

    func makeUIViewController(context: Context) -> ShakeDetectorViewController {
        ShakeDetectorViewController(action: action)
    }

    func updateUIViewController(_ uiViewController: ShakeDetectorViewController, context: Context) {
        uiViewController.action = action
    }
}

private final class ShakeDetectorViewController: UIViewController {
    var action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            action()
        }
        super.motionEnded(motion, with: event)
    }
}
