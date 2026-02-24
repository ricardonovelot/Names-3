//
//  CameraImagePicker.swift
//  Names 3
//
//  SwiftUI wrapper for UIImagePickerController with source type .camera.
//  Used when user chooses "Take Photo" for contact photo selection.
//

import SwiftUI
import UIKit

/// Presents the system camera for capturing a new photo.
struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage, Date?) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage, Date?) -> Void
        let onCancel: () -> Void

        init(onImagePicked: @escaping (UIImage, Date?) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            let date = Date()
            onImagePicked(image, date)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onCancel()
        }
    }
}
