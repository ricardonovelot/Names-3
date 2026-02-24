//
//  ContactPhotoLibraryPickerView.swift
//  Names 3
//
//  Photo grid for contact photo selection: newest first, Take Photo as first item.
//  Reuses PhotoGridView with contact-specific configuration.
//

import SwiftUI
import SwiftData
import Photos
import UIKit

/// Photo picker for contact photo selection. Shows grid with newest photos first and Take Photo as first cell.
struct ContactPhotoLibraryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DeletedPhoto.deletedDate, order: .reverse) private var deletedPhotos: [DeletedPhoto]

    let contactsContext: ModelContext
    @Binding var faceDetectionViewModel: FaceDetectionViewModel?
    let onPick: (UIImage, Date) -> Void
    let onCameraTapped: () -> Void
    let onDismiss: () -> Void

    @StateObject private var viewModel: PhotosPickerViewModel

    private let imageManager = PHCachingImageManager()

    init(
        contactsContext: ModelContext,
        faceDetectionViewModel: Binding<FaceDetectionViewModel?>,
        onPick: @escaping (UIImage, Date) -> Void,
        onCameraTapped: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.contactsContext = contactsContext
        self._faceDetectionViewModel = faceDetectionViewModel
        self.onPick = onPick
        self.onCameraTapped = onCameraTapped
        self.onDismiss = onDismiss
        self._viewModel = StateObject(wrappedValue: PhotosPickerViewModel(scope: .all, initialScrollDate: nil))
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Choose Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onDismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }
                .onAppear {
                    viewModel.startObservingChanges()
                    viewModel.suppressReload(false)
                    viewModel.requestAuthorizationIfNeeded()
                }
                .onDisappear {
                    viewModel.stopObservingChanges()
                }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            switch viewModel.state {
            case .idle:
                ProgressView("Preparing…")
            case .requestingAuthorization:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Requesting access…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .loading:
                if viewModel.assets.isEmpty {
                    loadingView
                } else {
                    photosGridView
                }
            case .loaded:
                if viewModel.assets.isEmpty {
                    emptyStateView
                } else {
                    photosGridView
                }
            case .empty:
                emptyStateView
            case .error(let error):
                errorView(message: error)
            }
        }
    }

    private var photosGridView: some View {
        let deletedIDs = Set(deletedPhotos.map(\.assetLocalIdentifier))
        let filteredAssets = viewModel.assets.filter { !deletedIDs.contains($0.localIdentifier) }
        return PhotoGridView(
            assets: filteredAssets,
            imageManager: imageManager,
            contactsContext: contactsContext,
            initialScrollDate: nil,
            sortNewestFirst: true,
            showCameraCell: UIImagePickerController.isSourceTypeAvailable(.camera),
            onCameraTapped: onCameraTapped,
            directSelectionMode: true,
            onPhotoTapped: { image, date, _ in
                onPick(image, date ?? Date())
                // Do NOT call onDismiss() — coordinator transitions to presentingCrop;
                // the sheet dismisses automatically when phase != presentingLibrary.
            },
            onAppearAtIndex: { _ in },
            onDetailVisibilityChanged: { _ in },
            faceDetectionViewModelBinding: $faceDetectionViewModel
        )
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading photos…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyStateView: some View {
        Group {
            if viewModel.authorizationStatus == .limited {
                VStack(spacing: 12) {
                    ContentUnavailableView {
                        Label("No photos available", systemImage: "photo")
                    } description: {
                        Text("Your Photos access is limited. Add photos to the app's selection.")
                    }
                    Button {
                        presentLimitedLibraryPicker()
                    } label: {
                        Label("Manage Selection", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView {
                    Label("No photos found", systemImage: "photo")
                } description: {
                    Text("Try a different date or check your Photos library.")
                }
            }
        }
    }

    private func errorView(message: PhotosPickerError) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task {
                    await viewModel.loadAssets()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootViewController = window.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
    }
}
