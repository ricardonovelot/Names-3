import SwiftUI
import Photos
import UIKit
import SwiftData

@MainActor
struct PhotosDayPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let scope: PhotosPickerScope
    let initialScrollDate: Date?
    let contactsContext: ModelContext
    let onPick: (UIImage, Date) -> Void
    let attemptQuickAssign: ((UIImage, Date?) async -> Bool)?

    @StateObject private var viewModel: PhotosPickerViewModel
    @State private var isPresentingDetail = false
    @State private var selectedImageForDetail: UIImage?
    @State private var selectedDateForDetail: Date?
    
    private let imageManager = PHCachingImageManager()
    
    // MARK: - Initialization
    
    init(scope: PhotosPickerScope, contactsContext: ModelContext, initialScrollDate: Date? = nil, onPick: @escaping (UIImage, Date) -> Void, attemptQuickAssign: ((UIImage, Date?) async -> Bool)? = nil) {
        self.scope = scope
        self.contactsContext = contactsContext
        self.initialScrollDate = initialScrollDate
        self.onPick = onPick
        self.attemptQuickAssign = attemptQuickAssign
        self._viewModel = StateObject(wrappedValue: PhotosPickerViewModel(scope: scope, initialScrollDate: initialScrollDate))
        
        if let scrollDate = initialScrollDate {
            print("🔵 [PhotosDayPickerView] Initialized with scroll date: \(scrollDate)")
        } else {
            print("🔵 [PhotosDayPickerView] Initialized without scroll date")
        }
        print("🔵 [PhotosDayPickerView] Instance created")
    }
    
    // MARK: - Body
    
    var body: some View {
        print("🔵 [PhotosDayPickerView] body evaluated - isPresentingDetail: \(isPresentingDetail), state: \(viewModel.state)")
        
        return NavigationStack {
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: Binding(
                get: { selectedImageForDetail != nil ? PhotoDetailDestination(image: selectedImageForDetail!, date: selectedDateForDetail) : nil },
                set: { newValue in
                    if newValue == nil {
                        selectedImageForDetail = nil
                        selectedDateForDetail = nil
                        isPresentingDetail = false
                        viewModel.suppressReload(false)
                    }
                }
            )) { destination in
                PhotoDetailViewWrapper(
                    image: destination.image,
                    date: destination.date,
                    contactsContext: contactsContext,
                    onComplete: { finalImage, finalDate in
                        onPick(finalImage, finalDate)
                        selectedImageForDetail = nil
                        selectedDateForDetail = nil
                        isPresentingDetail = false
                        dismiss()
                    },
                    onDismiss: {
                        selectedImageForDetail = nil
                        selectedDateForDetail = nil
                        isPresentingDetail = false
                    }
                )
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
    }
    
    // MARK: - State Views
    
    private var photosGridView: some View {
        let _ = print("🔵 [PhotosDayPickerView] photosGridView body - assets count: \(viewModel.assets.count), isEmpty: \(viewModel.assets.isEmpty)")
        
        return ZStack {
            PhotoGridView(
                assets: viewModel.assets,
                imageManager: imageManager,
                contactsContext: contactsContext,
                initialScrollDate: initialScrollDate,
                onPhotoTapped: { image, date in
                    print("✅ [PhotosDayPicker] Photo tapped callback received")
                    if let attempt = attemptQuickAssign {
                        Task {
                            let handled = try await attempt(image, date)
                            await MainActor.run {
                                if handled {
                                    print("✅ [PhotosDayPicker] Quick-assign handled. Skipping detail.")
                                    viewModel.suppressReload(false)
                                } else {
                                    selectedImageForDetail = image
                                    selectedDateForDetail = date
                                    isPresentingDetail = true
                                }
                            }
                        }
                    } else {
                        selectedImageForDetail = image
                        selectedDateForDetail = date
                        isPresentingDetail = true
                    }
                },
                onAppearAtIndex: { index in
                    if index < viewModel.assets.count {
                        viewModel.handlePagination(for: viewModel.assets[index])
                    }
                },
                onDetailVisibilityChanged: { visible in
                    print("🔵 [PhotosDayPickerView] onDetailVisibilityChanged called - visible: \(visible), current isPresentingDetail: \(isPresentingDetail)")
                    viewModel.suppressReload(visible)
                }
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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoDetailDestination, rhs: PhotoDetailDestination) -> Bool {
        lhs.id == rhs.id
    }
}