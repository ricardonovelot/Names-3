import SwiftUI
import Photos
import UIKit
import SwiftData

@MainActor
struct PhotosDayPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DeletedPhoto.deletedDate, order: .reverse) private var deletedPhotos: [DeletedPhoto]
    let scope: PhotosPickerScope
    let initialScrollDate: Date?
    let contactsContext: ModelContext
    let onPick: (UIImage, Date) -> Void
    let attemptQuickAssign: ((UIImage, Date?) async -> Bool)?
    @Binding var faceDetectionViewModel: FaceDetectionViewModel?
    
    let presentationMode: PhotoPickerPresentationMode
    let onDismiss: (() -> Void)?

    @StateObject private var viewModel: PhotosPickerViewModel
    @State private var isPresentingDetail = false
    @State private var selectedImageForDetail: UIImage?
    @State private var selectedDateForDetail: Date?
    @State private var selectedAssetIdentifier: String?
    
    private let imageManager = PHCachingImageManager()
    
    // MARK: - Initialization
    
    init(
        scope: PhotosPickerScope,
        contactsContext: ModelContext,
        initialScrollDate: Date? = nil,
        presentationMode: PhotoPickerPresentationMode = .detailView,
        faceDetectionViewModel: Binding<FaceDetectionViewModel?>,
        onPick: @escaping (UIImage, Date) -> Void,
        attemptQuickAssign: ((UIImage, Date?) async -> Bool)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.scope = scope
        self.contactsContext = contactsContext
        self.initialScrollDate = initialScrollDate
        self.presentationMode = presentationMode
        self._faceDetectionViewModel = faceDetectionViewModel
        self.onPick = onPick
        self.attemptQuickAssign = attemptQuickAssign
        self.onDismiss = onDismiss
        self._viewModel = StateObject(wrappedValue: PhotosPickerViewModel(scope: scope, initialScrollDate: initialScrollDate))
        
        if let scrollDate = initialScrollDate {
            print("🔵 [PhotosDayPickerView] Initialized with scroll date: \(scrollDate)")
        } else {
            print("🔵 [PhotosDayPickerView] Initialized without scroll date")
        }
        print("🔵 [PhotosDayPickerView] Presentation mode: \(presentationMode)")
        print("🔵 [PhotosDayPickerView] Instance created")
    }
    
    // MARK: - Body
    
    var body: some View {
        mainContent
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    backButton
                }
            }
            .navigationDestination(item: navigationDestinationBinding) { destination in
                destinationView(for: destination)
            }
            .onAppear {
                print("🔵 [PhotosDayPickerView] onAppear - start observing + unsuppress")
                viewModel.startObservingChanges()
                viewModel.suppressReload(false)
                viewModel.requestAuthorizationIfNeeded()
            }
            .onDisappear {
                print("🔵 [PhotosDayPickerView] onDisappear - stop observing")
                viewModel.stopObservingChanges()
            }
            .onChange(of: isPresentingDetail) { oldValue, newValue in
                print("🔵 [PhotosDayPickerView] onDetailVisibilityChanged called - visible: \(newValue), current isPresentingDetail: \(isPresentingDetail)")
                viewModel.suppressReload(newValue)
            }
    }
    
    // MARK: - View Components
    
    private var mainContent: some View {
        ZStack {
            switch viewModel.state {
            case .idle:
                ProgressView("Preparing...")
            case .requestingAuthorization:
                requestingAuthorizationView
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
    
    private var backButton: some View {
        Button {
            NotificationCenter.default.post(name: .quickInputCameraDidDismiss, object: nil)
            
            if let dismissHandler = onDismiss {
                dismissHandler()
            } else {
                dismiss()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text("Back")
                    .font(.body)
            }
        }
    }
    
    private var navigationDestinationBinding: Binding<PhotoDetailDestination?> {
        Binding(
            get: {
                selectedImageForDetail != nil
                    ? PhotoDetailDestination(image: selectedImageForDetail!, date: selectedDateForDetail, assetIdentifier: selectedAssetIdentifier)
                    : nil
            },
            set: { newValue in
                if newValue == nil {
                    selectedImageForDetail = nil
                    selectedDateForDetail = nil
                    selectedAssetIdentifier = nil
                    isPresentingDetail = false
                    viewModel.suppressReload(false)
                }
            }
        )
    }
    
    @ViewBuilder
    private func destinationView(for destination: PhotoDetailDestination) -> some View {
        if presentationMode == .detailView {
            PhotoDetailViewWrapper(
                image: destination.image,
                date: destination.date,
                assetIdentifier: destination.assetIdentifier,
                contactsContext: contactsContext,
                faceDetectionViewModelBinding: $faceDetectionViewModel,
                onComplete: { finalImage, finalDate in
                    onPick(finalImage, finalDate)
                    selectedImageForDetail = nil
                    selectedDateForDetail = nil
                    isPresentingDetail = false
                    if let dismissHandler = onDismiss {
                        dismissHandler()
                    } else {
                        dismiss()
                    }
                },
                onDismiss: {
                    selectedImageForDetail = nil
                    selectedDateForDetail = nil
                    isPresentingDetail = false
                }
            )
        }
    }
    
    // MARK: - State Views
    
    private var photosGridView: some View {
        let deletedIDs = Set(deletedPhotos.map(\.assetLocalIdentifier))
        let filteredAssets = viewModel.assets.filter { !deletedIDs.contains($0.localIdentifier) }
        return ZStack {
            PhotoGridView(
                assets: filteredAssets,
                imageManager: imageManager,
                contactsContext: contactsContext,
                initialScrollDate: initialScrollDate,
                onPhotoTapped: { image, date, assetId in handlePhotoTapped(image: image, date: date, assetIdentifier: assetId) },
                onAppearAtIndex: { index in
                    if index < filteredAssets.count {
                        viewModel.handlePagination(for: filteredAssets[index])
                    }
                },
                onDetailVisibilityChanged: { visible in
                    print("🔵 [PhotosDayPickerView] onDetailVisibilityChanged called - visible: \(visible), current isPresentingDetail: \(isPresentingDetail)")
                    viewModel.suppressReload(visible)
                },
                faceDetectionViewModelBinding: $faceDetectionViewModel
            )
            .background(Color(UIColor.systemGroupedBackground))
            .allowsHitTesting(!isPresentingDetail)
        }
    }
    
    private func handlePhotoTapped(image: UIImage, date: Date?, assetIdentifier: String?) {
        print("✅ [PhotosDayPicker] Photo tapped callback received")
        print("✅ [PhotosDayPicker] Presentation mode: \(presentationMode)")
        
        switch presentationMode {
        case .directSelection:
            print("✅ [PhotosDayPicker] Direct selection mode - calling onPick and dismissing")
            onPick(image, date ?? Date())
            dismiss()
            
        case .detailView:
            if let attempt = attemptQuickAssign {
                Task {
                    let handled = try await attempt(image, date)
                    await MainActor.run {
                        if handled {
                            print("✅ [PhotosDayPicker] Quick-assign handled. Dismissing.")
                            dismiss()
                        } else {
                            selectedImageForDetail = image
                            selectedAssetIdentifier = assetIdentifier
                            selectedDateForDetail = date
                            isPresentingDetail = true
                        }
                    }
                }
            } else {
                selectedImageForDetail = image
                selectedDateForDetail = date
                selectedAssetIdentifier = assetIdentifier
                isPresentingDetail = true
            }
        }
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
                limitedAccessEmptyView
            } else {
                ContentUnavailableView {
                    Label("No photos found", systemImage: "photo")
                } description: {
                    Text("Try a different date or check your Photos library.")
                }
            }
        }
    }
    
    private var limitedAccessEmptyView: some View {
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
    }
    
    private var deniedView: some View {
        ContentUnavailableView {
            Label("Photos Access Needed", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Enable Photos access in Settings to import photos.")
        } actions: {
            Button("Open Settings") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var restrictedView: some View {
        ContentUnavailableView {
            Label("Photos Access Restricted", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Photos access is restricted on this device.")
        }
    }
    
    private var requestingAuthorizationView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Requesting access…")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
    
    // MARK: - Helpers
    
    private var navigationTitle: String {
        switch scope {
        case .day(let date):
            return titleFormatter.string(from: date)
        case .all:
            return "All Photos"
        }
    }
    
    private let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return formatter
    }()
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func presentLimitedLibraryPicker() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let rootViewController = window.rootViewController {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
        }
    }
}

// Navigation destination identifier
private struct PhotoDetailDestination: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let date: Date?
    let assetIdentifier: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoDetailDestination, rhs: PhotoDetailDestination) -> Bool {
        lhs.id == rhs.id
    }
}