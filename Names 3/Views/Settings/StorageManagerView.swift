//
//  StorageManagerView.swift
//  Names 3
//
//  High-quality storage manager: app usage, device space, and useful actions.
//

import SwiftUI
import SwiftData

struct StorageManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var breakdown: StorageBreakdown?
    @State private var isLoading = true
    @State private var shrinkResult: (Int, Int)?
    @State private var showShrinkConfirmation = false
    @State private var isShrinking = false
    @State private var cacheCleared = false
    
    var body: some View {
        List {
            appSection
            deviceSection
            actionsSection
        }
        .navigationTitle(String(localized: "storage.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .refreshable {
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.storageDidChange)) { _ in
            Task { await refresh() }
        }
        .confirmationDialog(String(localized: "storage.shrink.dialog.title"), isPresented: $showShrinkConfirmation) {
            Button(String(localized: "storage.actions.shrink"), role: .none) {
                runShrink()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(localized: "storage.shrink.dialog.message"))
        }
    }
    
    private var deviceSection: some View {
        Section {
            if let b = breakdown {
                HStack {
                    Label(String(localized: "storage.device.free"), systemImage: "externaldrive")
                    Spacer()
                    Text(b.deviceFreeFormatted)
                        .foregroundStyle(b.isLowOnDevice ? .red : .secondary)
                        .fontWeight(b.isLowOnDevice ? .semibold : .regular)
                }
                if b.deviceTotal > 0 {
                    HStack {
                        Label(String(localized: "storage.device.total"), systemImage: "internaldrive")
                        Spacer()
                        Text(b.deviceTotalFormatted)
                            .foregroundStyle(.secondary)
                    }
                }
                if b.isLowOnDevice {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(String(localized: "storage.device.lowWarning"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if isLoading {
                HStack {
                    ProgressView()
                    Text("Calculating…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(LocalizedStringKey("storage.device.header"))
        }
    }
    
    private var appSection: some View {
        Section {
            if let b = breakdown {
                HStack {
                    Label(String(localized: "storage.app.total"), systemImage: "app.badge")
                    Spacer()
                    Text(b.appTotalFormatted)
                        .foregroundStyle(.secondary)
                }
                if b.peopleTotal > 0 {
                    NavigationLink {
                        StorageManagerPeopleView()
                    } label: {
                        HStack {
                            Label(String(localized: "storage.app.people"), systemImage: "person.2.fill")
                            Spacer()
                            Text(formatBytes(b.peopleTotal))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if b.facesTotal > 0 {
                    NavigationLink {
                        StorageManagerFacesView()
                    } label: {
                        HStack {
                            Label(String(localized: "storage.app.faces"), systemImage: "face.smiling")
                            Spacer()
                            Text(formatBytes(b.facesTotal))
                                .foregroundStyle(.secondary)
                            if b.faceCount > 0 {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                Text(String(format: String(localized: "storage.app.faces.count"), b.faceCount))
                                    .foregroundStyle(.tertiary)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                if b.otherDataTotal > 0 {
                    NavigationLink {
                        StorageManagerOtherDataView(
                            otherMetadataSize: b.otherMetadataSize,
                            otherBreakdown: b.otherBreakdown
                        )
                    } label: {
                        HStack {
                            Label(String(localized: "storage.app.otherData"), systemImage: "doc.text")
                            Spacer()
                            Text(formatBytes(b.otherDataTotal))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if b.batchStore > 0 {
                    HStack {
                        Label(String(localized: "storage.app.batchData"), systemImage: "square.stack.3d.up")
                        Spacer()
                        Text(formatBytes(b.batchStore))
                            .foregroundStyle(.secondary)
                    }
                }
                if b.caches > 0 {
                    HStack {
                        Label(String(localized: "storage.app.caches"), systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text(formatBytes(b.caches))
                            .foregroundStyle(.secondary)
                    }
                }
                if b.documents > 0 {
                    HStack {
                        Label(String(localized: "storage.app.documents"), systemImage: "doc.fill")
                        Spacer()
                        Text(formatBytes(b.documents))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(LocalizedStringKey("storage.app.header"))
        } footer: {
            Text(LocalizedStringKey("storage.app.footer"))
        }
    }
    
    private var actionsSection: some View {
        Section {
            Button {
                showShrinkConfirmation = true
            } label: {
                HStack {
                    Label(String(localized: "storage.actions.shrink"), systemImage: "arrow.down.right.and.arrow.up.left")
                    Spacer()
                    if isShrinking {
                        ProgressView()
                    } else if let (c, e) = shrinkResult, c + e > 0 {
                        Text("Saved \(c + e) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isShrinking)
            
            Button {
                StorageManagerService.shared.clearImageCache()
                cacheCleared = true
                Task { await refresh() }
            } label: {
                HStack {
                    Label(String(localized: "storage.actions.clearCache"), systemImage: "photo.on.rectangle.angled")
                    Spacer()
                    if cacheCleared {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(String(localized: "storage.actions.openSettings"), systemImage: "gear")
            }
        } header: {
            Text(LocalizedStringKey("storage.actions.header"))
        } footer: {
            Text(LocalizedStringKey("storage.actions.footer"))
        }
    }
    
    private func refresh() async {
        isLoading = true
        breakdown = await StorageManagerService.shared.computeBreakdown(modelContext: modelContext)
        isLoading = false
    }
    
    private func runShrink() {
        isShrinking = true
        shrinkResult = nil
        let (c, e) = StorageManagerService.shared.runStorageShrink(modelContext: modelContext)
        shrinkResult = (c, e)
        isShrinking = false
        Task { await refresh() }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
}

#Preview {
    NavigationStack {
        StorageManagerView()
            .modelContainer(for: [Contact.self, FaceEmbedding.self, Note.self, QuickNote.self, Tag.self], inMemory: true)
    }
}
