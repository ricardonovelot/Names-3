//
//  ConfirmDetectedFacesView.swift
//  Names 3
//
//  View to confirm or reject detected faces from any contact (under Name Faces).
//

import SwiftUI
import SwiftData
import Photos

/// Presents all suggested (unverified) detected faces across contacts for confirm/reject (Apple Photos–style).
struct ConfirmDetectedFacesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = FaceRecognitionCoordinator()

    @State private var suggestedByContact: [(Contact, [FaceRecognitionCoordinator.ContactFaceDisplayItem])] = []
    @State private var isLoading = true

    private var totalSuggestedCount: Int {
        suggestedByContact.reduce(0) { $0 + $1.1.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading suggested faces…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if suggestedByContact.isEmpty {
                    ContentUnavailableView {
                        Label("No Suggested Faces", systemImage: "person.crop.rectangle.badge.checkmark")
                    } description: {
                        Text("When the app finds faces that might match a contact, they’ll appear here for you to confirm or reject.")
                    }
                } else {
                    List {
                        ForEach(suggestedByContact, id: \.0.uuid) { contact, items in
                            Section {
                                ForEach(items) { item in
                                    ConfirmDetectedFaceRow(
                                        contact: contact,
                                        item: item,
                                        coordinator: coordinator,
                                        modelContext: modelContext,
                                        onConfirm: { removeItem(contact: contact, item: item) },
                                        onReject: { removeItem(contact: contact, item: item) }
                                    )
                                }
                            } header: {
                                Text(contact.displayName)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Confirm Detected Faces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if totalSuggestedCount > 0 {
                        Text("\(totalSuggestedCount) to review")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSuggested()
            }
        }
    }

    private func loadSuggested() {
        isLoading = true
        coordinator.getSuggestedByAllContacts(in: modelContext) { result in
            suggestedByContact = result
            isLoading = false
        }
    }

    private func removeItem(contact: Contact, item: FaceRecognitionCoordinator.ContactFaceDisplayItem) {
        guard let sectionIndex = suggestedByContact.firstIndex(where: { $0.0.uuid == contact.uuid }) else { return }
        var updated = suggestedByContact
        updated[sectionIndex].1.removeAll { $0.id == item.id }
        if updated[sectionIndex].1.isEmpty {
            updated.remove(at: sectionIndex)
        }
        suggestedByContact = updated
    }
}

/// Single row: thumbnail, "Is this [name]?", Confirm / Not this person.
private struct ConfirmDetectedFaceRow: View {
    let contact: Contact
    let item: FaceRecognitionCoordinator.ContactFaceDisplayItem
    @ObservedObject var coordinator: FaceRecognitionCoordinator
    let modelContext: ModelContext
    let onConfirm: () -> Void
    let onReject: () -> Void
    @State private var image: UIImage?
    private let imageManager = PHCachingImageManager()

    var body: some View {
        HStack(spacing: 16) {
            thumbnailView
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text("Is this \(contact.displayName)?")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 12) {
                    Button("Yes") {
                        coordinator.confirmSuggested(for: contact, item: item, in: modelContext)
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("No") {
                        coordinator.rejectSuggested(for: contact, item: item, in: modelContext)
                        onReject()
                    }
                    .buttonStyle(.bordered)
                    Button("I don't know") {
                        coordinator.rejectSuggested(for: contact, item: item, in: modelContext)
                        onReject()
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .onAppear { loadThumbnail() }
    }

    /// Prefer face-crop thumbnail when available so the user sees which specific face is being asked about.
    @ViewBuilder
    private var thumbnailView: some View {
        if let data = item.thumbnailData, !data.isEmpty, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let asset = item.asset {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(UIColor.tertiarySystemFill))
                }
            }
        } else {
            Rectangle()
                .fill(Color(UIColor.tertiarySystemFill))
        }
    }

    private func loadThumbnail() {
        // Only load full asset when we don't have a face-crop thumbnail (e.g. legacy embeddings)
        guard item.thumbnailData == nil || item.thumbnailData?.isEmpty == true,
              let asset = item.asset else { return }
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 144, height: 144),
            contentMode: .aspectFill,
            options: nil
        ) { img, _ in
            image = img
        }
    }
}
