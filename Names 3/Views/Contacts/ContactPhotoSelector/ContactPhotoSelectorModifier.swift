//
//  ContactPhotoSelectorModifier.swift
//  Names 3
//
//  ViewModifier that presents photo selection sheets (source picker, library, camera, crop)
//  and applies the selected photo to the contact.
//

import SwiftUI
import SwiftData

/// Modifier that wires up the contact photo selection flow: source picker, library, camera, crop, and apply.
struct ContactPhotoSelectorModifier: ViewModifier {
    @Bindable var contact: Contact
    @ObservedObject var coordinator: ContactPhotoSelectorCoordinator
    let modelContext: ModelContext
    @Binding var faceDetectionViewModel: FaceDetectionViewModel?
    let onPhotoApplied: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: libraryBinding) {
                ContactPhotoLibraryPickerView(
                    contactsContext: modelContext,
                    faceDetectionViewModel: $faceDetectionViewModel,
                    onPick: { image, date in
                        coordinator.didSelectImage(image, date: date)
                    },
                    onCameraTapped: {
                        coordinator.chooseCamera()
                    },
                    onDismiss: {
                        coordinator.dismissPicker()
                    }
                )
            }
            .fullScreenCover(isPresented: cameraBinding) {
                CameraImagePicker(
                    onImagePicked: { image, date in
                        coordinator.didSelectImage(image, date: date)
                    },
                    onCancel: {
                        coordinator.dismissPicker()
                    }
                )
            }
            .fullScreenCover(item: cropBinding) { item in
                SimpleCropView(
                    image: item.image,
                    initialScale: item.useExistingCrop ? CGFloat(contact.cropScale) : 1.0,
                    initialOffset: item.useExistingCrop
                        ? CGSize(width: CGFloat(contact.cropOffsetX), height: CGFloat(contact.cropOffsetY))
                        : .zero
                ) { croppedImage, scale, offset in
                    coordinator.didFinishCrop(croppedImage: croppedImage, scale: scale, offset: offset)
                    if let cropped = croppedImage {
                        applyPhotoToContact(cropped, date: item.date, scale: scale, offset: offset)
                    }
                    onPhotoApplied()
                }
            }
    }

    private var libraryBinding: Binding<Bool> {
        Binding(
            get: { coordinator.phase == .presentingLibrary },
            set: { if !$0 { coordinator.dismissPicker() } }
        )
    }

    private var cameraBinding: Binding<Bool> {
        Binding(
            get: { coordinator.phase == .presentingCamera },
            set: { if !$0 { coordinator.dismissPicker() } }
        )
    }

    private var cropBinding: Binding<CropItem?> {
        Binding(
            get: {
                if case .presentingCrop(let image, let date) = coordinator.phase {
                    return CropItem(image: image, date: date, useExistingCrop: false)
                }
                return nil
            },
            set: { if $0 == nil { coordinator.didFinishCrop(croppedImage: nil, scale: 0, offset: .zero) } }
        )
    }

    private func applyPhotoToContact(_ image: UIImage, date: Date?, scale: CGFloat, offset: CGSize) {
        coordinator.willApply()
        contact.photo = jpegDataForStoredContactPhoto(image)
        ImageAccessibleBackground.updateContactPhotoGradient(contact, image: image)
        contact.cropScale = Float(scale)
        contact.cropOffsetX = Float(offset.width)
        contact.cropOffsetY = Float(offset.height)
        if let date = date {
            contact.timestamp = date
        }
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        } catch {
            print("❌ [ContactPhotoSelector] Save failed: \(error)")
        }
        coordinator.didComplete()
    }
}

/// Identifiable item for the crop fullScreenCover.
private struct CropItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let date: Date?
    let useExistingCrop: Bool
}
