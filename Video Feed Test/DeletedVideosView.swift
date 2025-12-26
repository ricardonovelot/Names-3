import SwiftUI
import Photos
import UIKit
import Combine

@MainActor
final class DeletedVideosViewModel: ObservableObject {
    @Published var ids: [String] = []
    @Published var assets: [PHAsset] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        reload()
        NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func reload() {
        let snapshot = Array(DeletedVideosStore.snapshot())
        ids = snapshot.sorted()
        fetchAssets()
    }

    private func fetchAssets() {
        isLoading = true
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var list: [PHAsset] = []
        result.enumerateObjects { a, _, _ in list.append(a) }
        assets = list.sorted { lhs, rhs in
            let ld = lhs.creationDate ?? .distantPast
            let rd = rhs.creationDate ?? .distantPast
            if ld != rd { return ld > rd }
            return lhs.localIdentifier > rhs.localIdentifier
        }
        isLoading = false
    }

    func restore(_ asset: PHAsset) {
        Task { await DeletedVideosStore.shared.unhide(id: asset.localIdentifier) }
    }

    func restoreAll() {
        Task { await DeletedVideosStore.shared.unhideAll() }
    }

    func deletePermanently(_ asset: PHAsset) {
        Task {
            do {
                try await DeletedVideosStore.shared.purge(ids: [asset.localIdentifier])
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteAllPermanently() {
        Task {
            do {
                try await DeletedVideosStore.shared.purge(ids: ids)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct DeletedVideosView: View {
    @StateObject private var model = DeletedVideosViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAllConfirm = false

    var body: some View {
        List {
            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if model.assets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No deleted videos")
                        .font(.headline)
                    Text("Videos you hide will appear here. You can restore them or delete them permanently.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                ForEach(model.assets, id: \.localIdentifier) { asset in
                    DeletedRow(asset: asset)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.deletePermanently(asset)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                model.restore(asset)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                }
            }
        }
        .navigationTitle("Deleted videos")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Restore All") {
                    model.restoreAll()
                }
                .disabled(model.assets.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete All") {
                    showingDeleteAllConfirm = true
                }
                .disabled(model.assets.isEmpty)
            }
        }
        .alert("Delete all permanently?", isPresented: $showingDeleteAllConfirm) {
            Button("Delete All", role: .destructive) {
                model.deleteAllPermanently()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the videos from your Photos library and cannot be undone.")
        }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { _ in model.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct DeletedRow: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.gray.opacity(0.18)
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if asset.mediaType == .video {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(dateString(asset.creationDate))
                    .font(.headline)
                if asset.mediaType == .video {
                    Text(durationString(asset.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(asset.localIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .onAppear { loadThumb() }
        .onDisappear { cancelThumb() }
    }

    private func loadThumb() {
        cancelThumb()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestImage(for: asset,
                                                          targetSize: CGSize(width: 160, height: 160),
                                                          contentMode: .aspectFill,
                                                          options: options) { img, _ in
            if let img { self.image = img }
        }
    }

    private func cancelThumb() {
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }

    private func dateString(_ d: Date?) -> String {
        guard let d else { return "Unknown date" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: d)
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}