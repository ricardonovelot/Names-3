import SwiftUI
import Photos
import UIKit
import SwiftData

@MainActor
struct PhotosDayPickerContentView: View {
    let scope: PhotosPickerScope
    let initialScrollDate: Date?
    let contactsContext: ModelContext
    let onPick: (UIImage, Date) -> Void
    let attemptQuickAssign: ((UIImage, Date?) async -> Bool)?
    
    let presentationMode: PhotoPickerPresentationMode
    let showNavigationBar: Bool

    @StateObject private var viewModel: PhotosPickerViewModel
    @State private var isPresentingDetail = false
    @State private var selectedImageForDetail: UIImage?
    @State private var selectedDateForDetail: Date?
    @State private var faceDetectionViewModel: FaceDetectionViewModel? = nil
    @State private var navigationDestination: PhotoDetailDestination?
    
    private let imageManager = PHCachingImageManager()
    
    init(
        scope: PhotosPickerScope,
        contactsContext: ModelContext,
        initialScrollDate: Date? = nil,
        presentationMode: PhotoPickerPresentationMode = .detailView,
        showNavigationBar: Bool = true,
        onPick: @escaping (UIImage, Date) -> Void,
        attemptQuickAssign: ((UIImage, Date?) async -> Bool)? = nil
    ) {
        self.scope = scope
        self.contactsContext = contactsContext
        self.initialScrollDate = initialScrollDate
        self.presentationMode = presentationMode
        self.showNavigationBar = showNavigationBar
        self.onPick = onPick
        self.attemptQuickAssign = attemptQuickAssign
        self._viewModel = StateObject(wrappedValue: PhotosPickerViewModel(scope: scope, initialScrollDate: initialScrollDate))
        
        if let scrollDate = initialScrollDate {
            print("🔵 [PhotosDayPickerContentView] Initialized with scroll date: \(scrollDate)")
        } else {
            print("🔵 [PhotosDayPickerContentView] Initialized without scroll date")
        }
        print("🔵 [PhotosDayPickerContentView] Presentation mode: \(presentationMode)")
    }
    
    var body: some View {
        print("🔵 [PhotosDayPickerContentView] body evaluated - isPresentingDetail: \(isPresentingDetail), state: \(viewModel.state)")
        
        return ZStack {
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
        .background(Color(UIColor.systemGroupedBackground))
        .navigationDestination(item: $navigationDestination) { destination in
            if presentationMode == .detailView {
                PhotoDetailViewWrapper(
                    image: destination.image,
                    date: destination.date,
                    contactsContext: contactsContext,
                    faceDetectionViewModelBinding: $faceDetectionViewModel,
                    onComplete: { finalImage, finalDate in
                        onPick(finalImage, finalDate)
                        navigationDestination = nil
                        selectedImageForDetail = nil
                        selectedDateForDetail = nil
                        isPresentingDetail = false
                    },
                    onDismiss: {
                        navigationDestination = nil
                        selectedImageForDetail = nil
                        selectedDateForDetail = nil
                        isPresentingDetail = false
                    }
                )
            }
        }
        .onAppear {
            print("🔵 [PhotosDayPickerContentView] onAppear - start observing + unsuppress")
            viewModel.startObservingChanges()
            viewModel.suppressReload(false)
            viewModel.requestAuthorizationIfNeeded()
        }
        .onDisappear {
            print("🔵 [PhotosDayPickerContentView] onDisappear - stop observing")
            viewModel.stopObservingChanges()
        }
        .onChange(of: navigationDestination) { oldValue, newValue in
            if newValue == nil {
                viewModel.suppressReload(false)
            }
        }
        .onChange(of: isPresentingDetail) { oldValue, newValue in
            print("🔵 [PhotosDayPickerContentView] isPresentingDetail changed from \(oldValue) to \(newValue)")
            viewModel.suppressReload(newValue)
        }
    }
    
    private var photosGridView: some View {
        let _ = print("🔵 [PhotosDayPickerContentView] photosGridView body - assets count: \(viewModel.assets.count), isEmpty: \(viewModel.assets.isEmpty)")
        
        return ZStack {
            PhotoGridView(
                assets: viewModel.assets,
                imageManager: imageManager,
                contactsContext: contactsContext,
                initialScrollDate: initialScrollDate,
                onPhotoTapped: { image, date in
                    print("✅ [PhotosDayPicker] Photo tapped callback received")
                    print("✅ [PhotosDayPicker] Presentation mode: \(presentationMode)")
                    
                    switch presentationMode {
                    case .directSelection:
                        print("✅ [PhotosDayPicker] Direct selection mode - calling onPick")
                        onPick(image, date ?? Date())
                        
                    case .detailView:
                        if let attempt = attemptQuickAssign {
                            Task {
                                do {
                                    let handled = try await attempt(image, date)
                                    await MainActor.run {
                                        if handled {
                                            print("✅ [PhotosDayPicker] Quick-assign handled.")
                                        } else {
                                            selectedImageForDetail = image
                                            selectedDateForDetail = date
                                            navigationDestination = PhotoDetailDestination(image: image, date: date)
                                            isPresentingDetail = true
                                        }
                                    }
                                } catch {
                                    print("❌ [PhotosDayPicker] Quick-assign error: \(error)")
                                    await MainActor.run {
                                        selectedImageForDetail = image
                                        selectedDateForDetail = date
                                        navigationDestination = PhotoDetailDestination(image: image, date: date)
                                        isPresentingDetail = true
                                    }
                                }
                            }
                        } else {
                            selectedImageForDetail = image
                            selectedDateForDetail = date
                            navigationDestination = PhotoDetailDestination(image: image, date: date)
                            isPresentingDetail = true
                        }
                    }
                },
                onAppearAtIndex: { index in
                    guard index >= 0, index < viewModel.assets.count else { return }
                    viewModel.handlePagination(for: viewModel.assets[index])
                },
                onDetailVisibilityChanged: { visible in
                    print("🔵 [PhotosDayPickerContentView] onDetailVisibilityChanged called - visible: \(visible), current isPresentingDetail: \(isPresentingDetail)")
                    viewModel.suppressReload(visible)
                },
                faceDetectionViewModelBinding: $faceDetectionViewModel
            )
            .background(Color(UIColor.systemGroupedBackground))
            .allowsHitTesting(!isPresentingDetail)
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
    
    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootViewController = window.rootViewController else {
            print("❌ [PhotosDayPickerContentView] Cannot present limited library picker - no window")
            return
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
    }
}

private struct PhotoDetailDestination: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let date: Date?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoDetailDestination, rhs: PhotoDetailDestination) -> Bool {
        lhs.id == rhs.id
    }
}