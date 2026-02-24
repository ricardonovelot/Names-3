//
//  ContactPhotoSelectorCoordinator.swift
//  Names 3
//
//  State machine coordinator for contact photo selection flow.
//  Manages: source selection → library/camera → crop → apply.
//

import SwiftUI
import SwiftData

/// Coordinator for the contact photo selection flow. Encapsulates state and transitions.
@MainActor
final class ContactPhotoSelectorCoordinator: ObservableObject {

    // MARK: - State

    enum Phase: Equatable {
        /// Idle; user has not started selection.
        case idle
        /// Presenting photo library grid (newest first, Take Photo as first cell).
        case presentingLibrary
        /// Presenting camera (if available).
        case presentingCamera
        /// User selected an image; presenting crop view.
        case presentingCrop(image: UIImage, date: Date?)
        /// Applying selected photo to contact.
        case applying
    }

    /// Current phase of the selection flow.
    @Published private(set) var phase: Phase = .idle

    /// Image pending crop (selected from library or camera).
    @Published private(set) var pendingImage: UIImage?
    @Published private(set) var pendingDate: Date?

    /// Whether the camera is available on this device.
    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    // MARK: - Transitions

    /// Start the photo selection flow. Goes directly to the photo grid (no source picker).
    func startSelection() {
        phase = .presentingLibrary
    }

    /// User tapped Take Photo cell in the grid. Present camera.
    func chooseCamera() {
        phase = .presentingCamera
    }

    /// User selected an image from library or camera.
    func didSelectImage(_ image: UIImage, date: Date?) {
        pendingImage = image
        pendingDate = date
        phase = .presentingCrop(image: image, date: date)
    }

    /// User completed crop (or cancelled crop).
    func didFinishCrop(croppedImage: UIImage?, scale: CGFloat, offset: CGSize) {
        pendingImage = nil
        pendingDate = nil
        phase = .idle
    }

    /// Dismiss library/camera without selecting.
    func dismissPicker() {
        phase = .idle
        pendingImage = nil
        pendingDate = nil
    }

    /// Mark as applying (before persisting).
    func willApply() {
        phase = .applying
    }

    /// Selection flow complete.
    func didComplete() {
        phase = .idle
        pendingImage = nil
        pendingDate = nil
    }

    /// Cancel the entire flow.
    func cancel() {
        phase = .idle
        pendingImage = nil
        pendingDate = nil
    }
}
