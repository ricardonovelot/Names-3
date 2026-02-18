//
//  FaceRecognitionCoordinator.swift
//  Names 3
//
//  Coordinator for UI integration of face recognition features
//

import SwiftUI
import SwiftData
import Photos

/// Coordinator for managing face recognition UI interactions
@MainActor
final class FaceRecognitionCoordinator: ObservableObject {
    
    /// Contact UUIDs currently being analyzed (allows concurrent scans for different people).
    @Published var analyzingContactIDs: Set<UUID> = []
    /// True if any contact is being analyzed (for global progress UI).
    var isAnalyzing: Bool { !analyzingContactIDs.isEmpty }
    @Published var progress: Double = 0.0
    @Published var statusMessage = ""
    @Published var foundFacesCount = 0
    @Published var showingResults = false
    @Published var errorMessage: String?
    
    /// Progress per contact (contactUUID -> (processed, total)) for inline UI.
    @Published var progressByContact: [UUID: (Int, Int)] = [:]
    
    private let manualFaceService = ManualFaceRecognitionService.shared
    
    /// True if this contact is currently being analyzed.
    func isAnalyzing(contact: Contact) -> Bool {
        analyzingContactIDs.contains(contact.uuid)
    }
    
    // MARK: - Public Methods
    
    /// Start face recognition for a specific contact (multiple contacts can be analyzed concurrently).
    func startFaceRecognition(
        for contact: Contact,
        in modelContext: ModelContext
    ) {
        print("[FaceRecognition] startFaceRecognition contact=\(contact.displayName)")
        guard !isAnalyzing(contact: contact) else {
            print("[FaceRecognition] startFaceRecognition skipped (already analyzing this contact)")
            return
        }
        
        // Request Photos permission first
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard let self = self else { return }
            
            Task { @MainActor in
                switch status {
                case .authorized, .limited:
                    print("[FaceRecognition] Photos authorized/limited, starting performFaceRecognition")
                    self.performFaceRecognition(for: contact, in: modelContext)
                case .denied, .restricted:
                    print("[FaceRecognition] ❌ Photos denied or restricted")
                    self.errorMessage = "Photos access is required to find similar faces. Please enable it in Settings."
                case .notDetermined:
                    print("[FaceRecognition] Photos notDetermined")
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    /// Check how many faces are already recognized for a contact
    func getRecognizedFacesCount(for contact: Contact, in modelContext: ModelContext) -> Int {
        let searchUUID: UUID? = contact.uuid
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID == searchUUID }
        )
        
        do {
            let embeddings = try modelContext.fetch(descriptor)
            return embeddings.count
        } catch {
            print("Error fetching embeddings: \(error)")
            return 0
        }
    }
    
    /// Display item for the Detected Faces grid: either a laibrary photo (PHAsset) or a thumbnail-only image (e.g. from Name Faces).
    struct ContactFaceDisplayItem: Identifiable {
        let id: String
        let asset: PHAsset?
        let thumbnailData: Data?
    }
    
    /// Get all photos/thumbnails that contain this contact's face (library assets + name-faces-assigned thumbnails).
    func getDisplayItemsForContact(
        _ contact: Contact,
        in modelContext: ModelContext,
        completion: @escaping ([ContactFaceDisplayItem]) -> Void
    ) {
        fetchDisplayItems(for: contact, in: modelContext, suggestedOnly: false, completion: completion)
    }
    
    /// Get only suggested (unverified) photos for this contact — for review/confirm flow (Apple Photos–style).
    func getSuggestedDisplayItems(
        _ contact: Contact,
        in modelContext: ModelContext,
        completion: @escaping ([ContactFaceDisplayItem]) -> Void
    ) {
        fetchDisplayItems(for: contact, in: modelContext, suggestedOnly: true, completion: completion)
    }
    
    private func fetchDisplayItems(
        for contact: Contact,
        in modelContext: ModelContext,
        suggestedOnly: Bool,
        completion: @escaping ([ContactFaceDisplayItem]) -> Void
    ) {
        let searchUUID: UUID? = contact.uuid
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID == searchUUID },
            sortBy: [SortDescriptor(\.photoDate, order: .reverse)]
        )
        do {
            var embeddings = try modelContext.fetch(descriptor)
            if suggestedOnly {
                embeddings = embeddings.filter { !$0.isManuallyVerified }
            }
            let libraryIds = embeddings.map(\.assetIdentifier).filter { !$0.hasPrefix("name-faces-") }
            let assetIdsSet = Set(libraryIds)
            var assetById: [String: PHAsset] = [:]
            if !assetIdsSet.isEmpty {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: Array(assetIdsSet), options: nil)
                fetchResult.enumerateObjects { asset, _, _ in
                    assetById[asset.localIdentifier] = asset
                }
            }
            var items: [ContactFaceDisplayItem] = []
            for embed in embeddings {
                if embed.assetIdentifier.hasPrefix("name-faces-") {
                    if !embed.thumbnailData.isEmpty {
                        items.append(ContactFaceDisplayItem(id: embed.uuid.uuidString, asset: nil, thumbnailData: embed.thumbnailData))
                    }
                } else if let asset = assetById[embed.assetIdentifier] {
                    // Prefer face-crop thumbnail when available so the user sees which face is being asked about
                    items.append(ContactFaceDisplayItem(id: embed.assetIdentifier, asset: asset, thumbnailData: embed.thumbnailData.isEmpty ? nil : embed.thumbnailData))
                }
            }
            completion(items)
        } catch {
            print("Error fetching display items: \(error)")
            completion([])
        }
    }
    
    /// Confirm a suggested photo as this contact (marks as manually verified; used as reference for future recognition).
    func confirmSuggested(
        for contact: Contact,
        item: ContactFaceDisplayItem,
        in modelContext: ModelContext
    ) {
        let searchUUID: UUID? = contact.uuid
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID == searchUUID }
        )
        do {
            let embeddings = try modelContext.fetch(descriptor)
            let toUpdate: [FaceEmbedding]
            if item.asset != nil {
                toUpdate = embeddings.filter { $0.assetIdentifier == item.id }
            } else {
                // Name-faces: update this embed and any other with the same thumbnail (deduped in UI).
                if let thumb = item.thumbnailData, !thumb.isEmpty {
                    toUpdate = embeddings.filter { $0.uuid.uuidString == item.id || $0.thumbnailData == thumb }
                } else {
                    toUpdate = embeddings.filter { $0.uuid.uuidString == item.id }
                }
            }
            for embed in toUpdate {
                embed.isManuallyVerified = true
            }
            try modelContext.save()
        } catch {
            print("Error confirming suggested: \(error)")
        }
    }
    
    /// Reject a suggested photo (not this person); removes from this contact's faces.
    func rejectSuggested(
        for contact: Contact,
        item: ContactFaceDisplayItem,
        in modelContext: ModelContext
    ) {
        let searchUUID: UUID? = contact.uuid
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID == searchUUID }
        )
        do {
            let embeddings = try modelContext.fetch(descriptor)
            let toDelete: [FaceEmbedding]
            if item.asset != nil {
                toDelete = embeddings.filter { $0.assetIdentifier == item.id }
            } else {
                // Name-faces: delete this embed and any other with the same thumbnail (deduped in UI).
                if let thumb = item.thumbnailData, !thumb.isEmpty {
                    toDelete = embeddings.filter { $0.uuid.uuidString == item.id || $0.thumbnailData == thumb }
                } else {
                    toDelete = embeddings.filter { $0.uuid.uuidString == item.id }
                }
            }
            for embed in toDelete {
                modelContext.delete(embed)
            }
            try modelContext.save()
        } catch {
            print("Error rejecting suggested: \(error)")
        }
    }
    
    /// Count of suggested (unverified) faces for this contact.
    func getSuggestedCount(for contact: Contact, in modelContext: ModelContext) -> Int {
        let searchUUID: UUID? = contact.uuid
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID == searchUUID }
        )
        do {
            let embeddings = try modelContext.fetch(descriptor)
            return embeddings.filter { !$0.isManuallyVerified }.count
        } catch {
            return 0
        }
    }
    
    /// Total count of suggested (unverified) faces across all contacts (for badge/entry point).
    func getTotalSuggestedCount(in modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID != nil && !embed.isManuallyVerified }
        )
        do {
            let embeddings = try modelContext.fetch(descriptor)
            return embeddings.count
        } catch {
            return 0
        }
    }
    
    /// All suggested (unverified) faces grouped by contact, for the "Confirm detected faces" view.
    /// Uses a single embedding fetch, one contact fetch, and one PHAsset fetch to avoid N+1 and keep open time fast.
    func getSuggestedByAllContacts(
        in modelContext: ModelContext,
        completion: @escaping ([(Contact, [ContactFaceDisplayItem])]) -> Void
    ) {
        Task { @MainActor in
            let result = loadSuggestedByAllContactsOnMain(in: modelContext)
            completion(result)
        }
    }

    /// Single-query path: three fetches total so the confirm-detected-faces screen opens quickly.
    /// Only shows suggestions for (contact, asset) pairs that are not already verified on any device (synced via CloudKit).
    private func loadSuggestedByAllContactsOnMain(in modelContext: ModelContext) -> [(Contact, [ContactFaceDisplayItem])] {
        do {
            // 0) Fetch (contactUUID, assetIdentifier) pairs that are already verified — so we don't ask again on this device if user confirmed/rejected on another.
            let verifiedDescriptor = FetchDescriptor<FaceEmbedding>(
                predicate: #Predicate<FaceEmbedding> { embed in
                    embed.contactUUID != nil && embed.isManuallyVerified
                }
            )
            let verifiedEmbeddings = try modelContext.fetch(verifiedDescriptor)
            let verifiedKeySet: Set<String> = Set(verifiedEmbeddings.compactMap { e in
                guard let cu = e.contactUUID else { return nil }
                return "\(cu.uuidString):\(e.assetIdentifier)"
            })

            // 1) One fetch: all unverified embeddings
            let embedDescriptor = FetchDescriptor<FaceEmbedding>(
                predicate: #Predicate<FaceEmbedding> { embed in
                    embed.contactUUID != nil && !embed.isManuallyVerified
                },
                sortBy: [SortDescriptor(\.photoDate, order: .reverse)]
            )
            let embeddings = try modelContext.fetch(embedDescriptor)
            // Exclude unverified embeddings whose (contact, asset) is already verified (e.g. confirmed on phone, synced to desktop).
            let embeddingsNotAlreadyVerified = embeddings.filter { embed in
                guard let cu = embed.contactUUID else { return false }
                return !verifiedKeySet.contains("\(cu.uuidString):\(embed.assetIdentifier)")
            }
            guard !embeddingsNotAlreadyVerified.isEmpty else { return [] }

            let grouped = Dictionary(grouping: embeddingsNotAlreadyVerified) { $0.contactUUID! }
            let contactUUIDs = Set(grouped.keys)

            // 2) One fetch: all contacts (we'll filter in memory to avoid predicate limits)
            let contactDescriptor = FetchDescriptor<Contact>(sortBy: [SortDescriptor(\.name)])
            let allContacts = try modelContext.fetch(contactDescriptor)
            let contactsByUUID = Dictionary(uniqueKeysWithValues: allContacts.filter { contactUUIDs.contains($0.uuid) }.map { ($0.uuid, $0) })

            // 3) One PH fetch: all library asset identifiers
            let libraryIds = embeddingsNotAlreadyVerified.map(\.assetIdentifier).filter { !$0.hasPrefix("name-faces-") }
            let assetIdsSet = Set(libraryIds)
            var assetById: [String: PHAsset] = [:]
            if !assetIdsSet.isEmpty {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: Array(assetIdsSet), options: nil)
                fetchResult.enumerateObjects { asset, _, _ in
                    assetById[asset.localIdentifier] = asset
                }
            }

            // 4) Build [(Contact, [ContactFaceDisplayItem])] — one item per (contact, photo/face) to avoid asking the same question repeatedly.
            var result: [(Contact, [ContactFaceDisplayItem])] = []
            for (contactUUID, embeds) in grouped {
                guard let contact = contactsByUUID[contactUUID] else { continue }
                var items: [ContactFaceDisplayItem] = []
                var seenDisplayKey: Set<String> = []
                for embed in embeds {
                    // One row per (contact, photo): library by assetIdentifier; name-faces by thumbnail so same face isn’t asked repeatedly.
                    let displayKey: String
                    if embed.assetIdentifier.hasPrefix("name-faces-") {
                        displayKey = embed.thumbnailData.isEmpty ? embed.uuid.uuidString : "nf-\(embed.thumbnailData.hashValue)"
                    } else {
                        displayKey = embed.assetIdentifier
                    }
                    guard !seenDisplayKey.contains(displayKey) else { continue }
                    seenDisplayKey.insert(displayKey)
                    if embed.assetIdentifier.hasPrefix("name-faces-") {
                        if !embed.thumbnailData.isEmpty {
                            items.append(ContactFaceDisplayItem(id: embed.uuid.uuidString, asset: nil, thumbnailData: embed.thumbnailData))
                        }
                    } else if let asset = assetById[embed.assetIdentifier] {
                        let thumb = embed.thumbnailData.isEmpty ? nil : embed.thumbnailData
                        items.append(ContactFaceDisplayItem(id: embed.assetIdentifier, asset: asset, thumbnailData: thumb))
                    }
                }
                if !items.isEmpty {
                    result.append((contact, items))
                }
            }
            result.sort { $0.0.displayName.localizedStandardCompare($1.0.displayName) == .orderedAscending }
            return result
        } catch {
            return []
        }
    }
    
    /// Queue of contact UUIDs to process when user taps "Find more faces"; we run one at a time to avoid main-thread lag.
    private var batchQueue: [UUID] = []

    /// Start "Find Similar Faces" for all contacts that have a photo (finds more faces to review). Processes one contact at a time to keep the UI responsive.
    func startFaceRecognitionForAllContactsWithPhotos(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Contact>(sortBy: [SortDescriptor(\.name)])
        do {
            let contacts = try modelContext.fetch(descriptor)
            let withPhoto = contacts.filter { !$0.photo.isEmpty }.map(\.uuid)
            guard !withPhoto.isEmpty else { return }
            batchQueue = withPhoto
            startNextInBatch(in: modelContext)
        } catch {
            print("[FaceRecognition] startFaceRecognitionForAllContactsWithPhotos failed: \(error)")
        }
    }

    /// Start the next contact in the batch queue (one at a time so the main thread isn't flooded).
    private func startNextInBatch(in modelContext: ModelContext) {
        guard !batchQueue.isEmpty else { return }
        let uuid = batchQueue.removeFirst()
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { c in c.uuid == uuid }
        )
        guard let contact = try? modelContext.fetch(descriptor).first else {
            startNextInBatch(in: modelContext)
            return
        }
        let container = modelContext.container
        performFaceRecognition(
            for: contact,
            in: modelContext,
            container: container,
            whenBatchDone: { [weak self] in
                self?.startNextInBatch(in: modelContext)
            }
        )
    }

    /// Get all photos that contain this contact's face (library assets only; for backward compatibility).
    func getPhotosForContact(
        _ contact: Contact,
        in modelContext: ModelContext,
        completion: @escaping ([PHAsset]) -> Void
    ) {
        getDisplayItemsForContact(contact, in: modelContext) { items in
            completion(items.compactMap(\.asset))
        }
    }
    
    /// Delete all face recognition data for a contact
    func deleteRecognizedFaces(for contact: Contact, in modelContext: ModelContext) {
        let searchUUID: UUID? = contact.uuid
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID == searchUUID }
        )
        
        do {
            let embeddings = try modelContext.fetch(descriptor)
            for embedding in embeddings {
                modelContext.delete(embedding)
            }
            try modelContext.save()
        } catch {
            print("Error deleting embeddings: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func performFaceRecognition(
        for contact: Contact,
        in modelContext: ModelContext,
        container: ModelContainer? = nil,
        whenBatchDone: (() -> Void)? = nil
    ) {
        let contactUUID = contact.uuid
        analyzingContactIDs.insert(contactUUID)
        progressByContact[contactUUID] = (0, 1)
        progress = 0.0
        foundFacesCount = 0
        statusMessage = "Analyzing photos..."
        errorMessage = nil
        
        // Always pass the app container so results are written to the synced store; when nil,
        // the service would create a separate store and results would not sync (P0 fix).
        let appContainer = container ?? modelContext.container
        manualFaceService.findSimilarFaces(
            for: contact,
            in: modelContext,
            appContainer: appContainer
        ) { [weak self] processed, total in
            guard let self = self else { return }
            Task { @MainActor in
                self.progressByContact[contactUUID] = (processed, total)
                self.progress = Double(processed) / Double(max(total, 1))
                self.statusMessage = "Processed \(processed) of \(total) photos..."
            }
        } completion: { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                self.analyzingContactIDs.remove(contactUUID)
                self.progressByContact.removeValue(forKey: contactUUID)
                
                switch result {
                case .success(let count):
                    print("[FaceRecognition] performFaceRecognition success: \(count) matching faces")
                    self.foundFacesCount = count
                    self.statusMessage = "Found \(count) matching faces!"
                    self.showingResults = false
                case .failure(let error):
                    print("[FaceRecognition] performFaceRecognition failure: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "Analysis failed"
                }
                whenBatchDone?()
            }
        }
    }
}

// MARK: - SwiftUI Views

/// Button to trigger face recognition for a contact
struct FaceRecognitionButton: View {
    let contact: Contact
    @Environment(\.modelContext) private var modelContext
    @StateObject private var coordinator = FaceRecognitionCoordinator()
    
    var body: some View {
        Button {
            coordinator.startFaceRecognition(for: contact, in: modelContext)
        } label: {
            HStack {
                Image(systemName: "face.smiling")
                Text("Find Similar Faces")
                
                let count = coordinator.getRecognizedFacesCount(for: contact, in: modelContext)
                if count > 0 {
                    Text("(\(count))")
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(coordinator.isAnalyzing(contact: contact))
        .sheet(isPresented: $coordinator.showingResults) {
            FaceRecognitionResultsView(
                contact: contact,
                foundCount: coordinator.foundFacesCount,
                coordinator: coordinator
            )
        }
        .alert("Error", isPresented: .constant(coordinator.errorMessage != nil)) {
            Button("OK") {
                coordinator.errorMessage = nil
            }
        } message: {
            if let error = coordinator.errorMessage {
                Text(error)
            }
        }
        .overlay {
            if coordinator.isAnalyzing(contact: contact) {
                FaceRecognitionProgressView(
                    progress: coordinator.progress,
                    message: coordinator.statusMessage
                )
            }
        }
    }
}

/// Progress view shown during face recognition
struct FaceRecognitionProgressView: View {
    let progress: Double
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 200)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

/// Results view showing found faces
struct FaceRecognitionResultsView: View {
    let contact: Contact
    let foundCount: Int
    @ObservedObject var coordinator: FaceRecognitionCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var photos: [PHAsset] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Success message
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Found \(foundCount) Matching Faces")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("The app will now remember \(contact.displayName) in these photos")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if !photos.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100))
                        ], spacing: 8) {
                            ForEach(photos.prefix(20), id: \.localIdentifier) { asset in
                                PhotoThumbnailView(asset: asset)
                            }
                        }
                        .padding()
                    }
                    
                    if photos.count > 20 {
                        Text("+ \(photos.count - 20) more photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Face Recognition Complete")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                coordinator.getPhotosForContact(contact, in: modelContext) { assets in
                    self.photos = assets
                }
            }
        }
    }
}

/// Thumbnail view for a photo asset
struct PhotoThumbnailView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    private let imageManager = PHCachingImageManager()
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            self.image = image
        }
    }
}

// MARK: - View Modifier for Easy Integration

extension View {
    /// Add face recognition capability to any view
    func faceRecognition(for contact: Contact) -> some View {
        self.modifier(FaceRecognitionModifier(contact: contact))
    }
}

struct FaceRecognitionModifier: ViewModifier {
    let contact: Contact
    @StateObject private var coordinator = FaceRecognitionCoordinator()
    
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    FaceRecognitionButton(contact: contact)
                }
            }
    }
}
