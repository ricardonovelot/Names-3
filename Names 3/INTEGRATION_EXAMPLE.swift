//
//  INTEGRATION_EXAMPLE.swift
//  Names 3
//
//  Example integration of face recognition into existing UI
//  This file shows how to add face recognition to your app
//

import SwiftUI
import SwiftData
import Photos

// MARK: - Example 1: Simple Button Integration

/*
 Add a face recognition button to any contact view
 */

struct ContactDetailViewExample: View {
    let contact: Contact
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Existing contact info
                contactInfoSection
                
                // Add face recognition button
                FaceRecognitionButton(contact: contact)
                    .padding()
            }
        }
        .navigationTitle(contact.displayName)
    }
    
    private var contactInfoSection: some View {
        VStack {
            if !contact.photo.isEmpty,
               let uiImage = UIImage(data: contact.photo) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
            }
            
            Text(contact.displayName)
                .font(.title)
        }
    }
}

// MARK: - Example 2: Toolbar Integration

/*
 Add face recognition as a toolbar item
 */

struct ContactDetailWithToolbarExample: View {
    let contact: Contact
    
    var body: some View {
        ScrollView {
            // Your existing UI
            Text("Contact Details")
        }
        .navigationTitle(contact.displayName)
        .faceRecognition(for: contact)  // Adds toolbar button automatically
    }
}

// MARK: - Example 3: Custom Implementation with Progress

/*
 Full custom implementation with progress tracking
 */

struct CustomFaceRecognitionView: View {
    let contact: Contact
    @Environment(\.modelContext) private var modelContext
    @StateObject private var coordinator = FaceRecognitionCoordinator()
    
    var body: some View {
        VStack(spacing: 20) {
            // Contact photo
            if !contact.photo.isEmpty,
               let uiImage = UIImage(data: contact.photo) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
            }
            
            // Recognition stats
            recognitionStatsSection
            
            // Action buttons
            actionButtonsSection
            
            // Progress indicator
            if coordinator.isAnalyzing {
                ProgressView(value: coordinator.progress) {
                    Text(coordinator.statusMessage)
                }
                .padding()
            }
            
            // Error alert
            if let error = coordinator.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
        }
        .padding()
    }
    
    private var recognitionStatsSection: some View {
        VStack(spacing: 8) {
            let count = coordinator.getRecognizedFacesCount(for: contact, in: modelContext)
            
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text("\(count) photos recognized")
                    .font(.headline)
            }
            
            if count > 0 {
                Button("View Photos") {
                    // Load and display photos
                    coordinator.getPhotosForContact(contact, in: modelContext) { assets in
                        // Handle assets
                        print("Found \(assets.count) photos")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Start recognition
            Button {
                coordinator.startFaceRecognition(for: contact, in: modelContext)
            } label: {
                HStack {
                    Image(systemName: "face.smiling")
                    Text("Find Similar Faces")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(coordinator.isAnalyzing)
            
            // Delete recognized faces
            let hasRecognizedFaces = coordinator.getRecognizedFacesCount(for: contact, in: modelContext) > 0
            if hasRecognizedFaces {
                Button(role: .destructive) {
                    coordinator.deleteRecognizedFaces(for: contact, in: modelContext)
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Remove Face Data")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Example 4: Batch Recognition for Multiple Contacts

/*
 Recognize faces for multiple contacts at once
 */

struct BatchFaceRecognitionView: View {
    let contacts: [Contact]
    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex = 0
    @State private var totalFound = 0
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Batch Face Recognition")
                .font(.title)
            
            if isProcessing {
                ProgressView(value: Double(currentIndex), total: Double(contacts.count)) {
                    Text("Processing \(currentIndex) of \(contacts.count)")
                }
                .padding()
            } else {
                VStack {
                    Text("Found \(totalFound) total faces")
                        .font(.headline)
                    
                    Button("Start Batch Recognition") {
                        startBatchRecognition()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
    
    private func startBatchRecognition() {
        isProcessing = true
        currentIndex = 0
        totalFound = 0
        
        processNextContact()
    }
    
    private func processNextContact() {
        guard currentIndex < contacts.count else {
            isProcessing = false
            return
        }
        
        let contact = contacts[currentIndex]
        let coordinator = FaceRecognitionCoordinator()
        
        coordinator.startFaceRecognition(for: contact, in: modelContext)
        
        // Monitor completion (simplified)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if !coordinator.isAnalyzing {
                totalFound += coordinator.foundFacesCount
                currentIndex += 1
                processNextContact()
            }
        }
    }
}

// MARK: - Example 5: Photo Gallery with Face Recognition

/*
 Show all photos where a contact appears
 */

struct ContactPhotoGalleryView: View {
    let contact: Contact
    @Environment(\.modelContext) private var modelContext
    @StateObject private var coordinator = FaceRecognitionCoordinator()
    @State private var photos: [PHAsset] = []
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading photos...")
                    .padding()
            } else if photos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No photos found")
                        .font(.headline)
                    
                    Text("Use face recognition to find photos of \(contact.displayName)")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    FaceRecognitionButton(contact: contact)
                }
                .padding()
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100, maximum: 150))
                ], spacing: 8) {
                    ForEach(photos, id: \.localIdentifier) { asset in
                        PhotoThumbnailView(asset: asset)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Photos of \(contact.displayName)")
        .onAppear {
            loadPhotos()
        }
        .refreshable {
            loadPhotos()
        }
    }
    
    private func loadPhotos() {
        isLoading = true
        coordinator.getPhotosForContact(contact, in: modelContext) { assets in
            photos = assets
            isLoading = false
        }
    }
}

// MARK: - Example 6: Settings Integration

/*
 Add face recognition settings to app settings
 */

struct FaceRecognitionSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var totalEmbeddings = 0
    @State private var totalClusters = 0
    @State private var isProcessing = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Total Faces Recognized")
                    Spacer()
                    Text("\(totalEmbeddings)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Face Clusters")
                    Spacer()
                    Text("\(totalClusters)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Statistics")
            }
            
            Section {
                Button("Analyze All Contacts") {
                    analyzeAllContacts()
                }
                .disabled(isProcessing)
            } header: {
                Text("Actions")
            }
            
            Section {
                Button(role: .destructive) {
                    deleteAllFaceData()
                } label: {
                    Text("Delete All Face Data")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Face recognition data is stored locally and synced via iCloud. All processing happens on your device.")
            }
        }
        .navigationTitle("Face Recognition")
        .onAppear {
            loadStats()
        }
    }
    
    private func loadStats() {
        do {
            let embeddingDescriptor = FetchDescriptor<FaceEmbedding>()
            let embeddings = try modelContext.fetch(embeddingDescriptor)
            totalEmbeddings = embeddings.count
            
            let clusterDescriptor = FetchDescriptor<FaceCluster>()
            let clusters = try modelContext.fetch(clusterDescriptor)
            totalClusters = clusters.count
        } catch {
            print("Error loading stats: \(error)")
        }
    }
    
    private func analyzeAllContacts() {
        // Implementation for analyzing all contacts
        isProcessing = true
        
        // Get all contacts and process them
        // Similar to batch recognition example
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isProcessing = false
            loadStats()
        }
    }
    
    private func deleteAllFaceData() {
        do {
            let descriptor = FetchDescriptor<FaceEmbedding>()
            let embeddings = try modelContext.fetch(descriptor)
            for embedding in embeddings {
                modelContext.delete(embedding)
            }
            try modelContext.save()
            loadStats()
        } catch {
            print("Error deleting face data: \(error)")
        }
    }
}

// MARK: - Example 7: Automatic Recognition on Contact Creation

/*
 Automatically trigger face recognition when a new contact is created
 */

struct CreateContactWithAutoRecognition: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var photoData: Data?
    @State private var shouldRecognizeFaces = true
    
    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                
                // Photo picker
                if let photoData = photoData,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                }
            }
            
            Section {
                Toggle("Recognize faces automatically", isOn: $shouldRecognizeFaces)
            } footer: {
                Text("Find all photos with this person in your library")
            }
            
            Section {
                Button("Save") {
                    saveContact()
                }
                .disabled(name.isEmpty || photoData == nil)
            }
        }
        .navigationTitle("New Contact")
    }
    
    private func saveContact() {
        let contact = Contact(
            name: name,
            photo: photoData ?? Data()
        )
        
        modelContext.insert(contact)
        
        do {
            try modelContext.save()
            
            // Trigger face recognition if enabled
            if shouldRecognizeFaces {
                let coordinator = FaceRecognitionCoordinator()
                coordinator.startFaceRecognition(for: contact, in: modelContext)
            }
            
            dismiss()
        } catch {
            print("Error saving contact: \(error)")
        }
    }
}

/*
 
 USAGE INSTRUCTIONS:
 
 1. Choose the example that fits your UI pattern
 2. Copy the relevant code to your view
 3. Import required frameworks (already in project)
 4. Test with a contact that has a clear face photo
 5. Grant Photos permission when prompted
 6. Wait for background analysis to complete
 
 NOTES:
 - Face recognition works best with clear, frontal faces
 - Background tasks are scheduled automatically
 - Results are synced via CloudKit
 - All processing is on-device (privacy-focused)
 
 */
