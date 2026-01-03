import SwiftUI
import Photos
import UIKit

struct PhotosDayPickerView: View {
    let scope: PhotosPickerScope
    let onPick: (UIImage, Date?) -> Void
    
    @StateObject private var viewModel: PhotosPickerViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let imageManager = PHCachingImageManager()
    
    // MARK: - Initialization
    
    init(scope: PhotosPickerScope, onPick: @escaping (UIImage, Date?) -> Void) {
        self.scope = scope
        self.onPick = onPick
        self._viewModel = StateObject(wrappedValue: PhotosPickerViewModel(scope: scope))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                }
                .task {
                    viewModel.requestAuthorizationIfNeeded()
                }
                .task(id: scope) {
                    viewModel.reloadForScope(scope)
                }
                .onAppear {
                    viewModel.startObservingChanges()
                }
                .onDisappear {
                    viewModel.stopObservingChanges()
                }
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.authorizationStatus {
        case .authorized, .limited:
            authorizedContentView
        case .denied:
            deniedView
        case .restricted:
            restrictedView
        case .notDetermined:
            requestingAuthorizationView
        @unknown default:
            authorizedContentView
        }
    }
    
    @ViewBuilder
    private var authorizedContentView: some View {
        switch viewModel.state {
        case .idle:
            Color.clear
        case .requestingAuthorization:
            requestingAuthorizationView
        case .loading:
            loadingView
        case .loaded:
            photosGridView
        case .empty:
            emptyView
        case .error(let error):
            errorView(error)
        }
    }
    
    // MARK: - State Views
    
    private var photosGridView: some View {
        PhotoGridView(
            assets: viewModel.assets,
            imageManager: imageManager,
            onPick: { image, date in
                onPick(image, date)
            },
            onAppearAtIndex: { index in
                if index < viewModel.assets.count {
                    viewModel.handlePagination(for: viewModel.assets[index])
                }
            }
        )
        .background(Color(UIColor.systemGroupedBackground))
        .overlay {
            if viewModel.assets.isEmpty {
                emptyView
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
    
    private var emptyView: some View {
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
    
    private func errorView(_ error: PhotosPickerError) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
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