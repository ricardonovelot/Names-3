import SwiftUI
import SwiftData
import UIKit
import TipKit
import Photos

struct ContactDetailsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var contact: Contact
    var isCreationFlow: Bool = false
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil

    @State var viewState = CGSize.zero

    @State private var showPhotosPicker = false
    @State private var showDatePicker = false
    @State private var showTagPicker = false
    @State private var showCropView = false
    
    @State private var pendingPhotoImage: UIImage?
    @State private var pendingPhotoDate: Date?
    @State private var faceDetectionViewModel: FaceDetectionViewModel?

    @Query private var notes: [Note]

    @State private var noteText = ""
    @State private var stateNotes : [Note] = []
    @State private var CustomBackButtonAnimationValue = 40.0

    var image: UIImage { UIImage(data: contact.photo) ?? UIImage() }
    
    @State private var noteBeingEdited: Note?
    @State private var showNoteDatePicker = false

    @StateObject private var faceRecognitionCoordinator = FaceRecognitionCoordinator()
    @State private var showPhotoFacesSheet = false

    /// Accessible colors derived from contact photo for content-below-image gradient (nil when no photo or not yet computed).
    @State private var derivedBackgroundColors: (base: Color, end: Color)?

    /// Scroll view, toolbar, and overlay. Wrapped in GlassEffectContainer on iOS 26 when contact has photo so glass coordinates and stays transparent.
    /// Header height (photo) so the content gradient can keep the same color through this range and avoid a seam.
    private static let headerHeight: CGFloat = 400

    /// Fixed full-screen background so scrolling never reveals a different color. Gradient is in screen space, not scroll content.
    @ViewBuilder
    private func fixedBackgroundView(screenHeight: CGFloat) -> some View {
        if contact.photoGradientColors != nil || derivedBackgroundColors != nil {
            fixedGradientView(screenHeight: screenHeight)
        } else {
            Color(UIColor.systemGroupedBackground)
        }
    }

    private func fixedGradientView(screenHeight: CGFloat) -> some View {
        let (base, end): (Color, Color) = {
            if let stored = contact.photoGradientColors { return (stored.start, stored.end) }
            if let colors = derivedBackgroundColors { return (colors.base, colors.end) }
            let c = Color(UIColor.systemGroupedBackground)
            return (c, c)
        }()
        let headerFraction = screenHeight > 0 ? min(1, Self.headerHeight / screenHeight) : 0
        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: base, location: 0),
                .init(color: base, location: headerFraction),
                .init(color: end, location: 1)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func contactDetailsScrollContent(screenHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            fixedBackgroundView(screenHeight: screenHeight)
                .ignoresSafeArea(edges: .all)

            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                    notesSection
                        .padding(.top, 8)
                }
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .padding(.top, image != UIImage() ? 0 : 8)
            .ignoresSafeArea(image != UIImage() ? .all : [])

        }
        .onAppear {
            TipManager.shared.donateContactViewed()
        }
        .task(id: contact.photo.count) {
            await updateDerivedBackgroundIfNeeded()
        }
        .toolbar {
            
                ToolbarItem(placement: .topBarTrailing) {
                    optionsMenuButton
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    backButtonLabel(showChevron: true)
                }
            
        }
        .navigationBarBackButtonHidden(true)
    }

    var body: some View {
        GeometryReader { g in
            contactDetailsScrollContent(screenHeight: g.size.height)
                .modifier(GlassContainerWhenPhotoModifier(hasPhoto: image != UIImage()))
        }
        .toolbarBackground(.hidden)
        .sheet(isPresented: $showPhotosPicker) {
            PhotosDayPickerView(
                scope: .all,
                contactsContext: modelContext,
                presentationMode: .directSelection,
                faceDetectionViewModel: $faceDetectionViewModel,
                onPick: { selectedImage, selectedDate in
                    pendingPhotoImage = selectedImage
                    pendingPhotoDate = selectedDate
                    showCropView = true
                }
            )
        }
        .sheet(isPresented: $showDatePicker) {
            CustomDatePicker(contact: contact)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerView(mode: .contactToggle(contact: contact))
        }
        .sheet(isPresented: $showNoteDatePicker) {
            NavigationView {
                VStack {
                    DatePicker(
                        "Select Date",
                        selection: Binding(
                            get: { noteBeingEdited?.creationDate ?? Date() },
                            set: { newValue in
                                if let note = noteBeingEdited {
                                    note.creationDate = newValue
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("Save failed: \(error)")
                                    }
                                }
                            }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .padding()

                    Spacer()

                    Button("Done") {
                        showNoteDatePicker = false
                    }
                    .padding()
                }
                .navigationBarTitle("Edit Note Date", displayMode: .inline)
            }
        }
        .fullScreenCover(isPresented: $showCropView){
            if let image = UIImage(data: contact.photo) {
                SimpleCropView(
                    image: image,
                    initialScale: CGFloat(contact.cropScale),
                    initialOffset: CGSize(width: CGFloat(contact.cropOffsetX), height: CGFloat(contact.cropOffsetY))
                ) { croppedImage, scale, offset in
                    updateCroppingParameters(croppedImage: croppedImage, scale: scale, offset: offset)
                }
            }
        }
        .sheet(isPresented: $faceRecognitionCoordinator.showingResults) {
            FaceRecognitionResultsView(
                contact: contact,
                foundCount: faceRecognitionCoordinator.foundFacesCount,
                coordinator: faceRecognitionCoordinator
            )
        }
        .sheet(isPresented: $showPhotoFacesSheet) {
            ContactPhotoFacesSheet(
                contact: contact,
                coordinator: faceRecognitionCoordinator,
                onDismiss: { showPhotoFacesSheet = false }
            )
        }
        .alert("Error", isPresented: .constant(faceRecognitionCoordinator.errorMessage != nil)) {
            Button("OK") {
                faceRecognitionCoordinator.errorMessage = nil
            }
        } message: {
            if let error = faceRecognitionCoordinator.errorMessage {
                Text(error)
            }
        }
    }
    
    @ViewBuilder
    private var optionsMenuButton: some View {
        Menu {
            Button {
            } label: {
                Text("Duplicate")
            }
            Button {
                contact.isArchived = true
                contact.archivedDate = Date()
                do {
                    try modelContext.save()
                } catch {
                    print("Save failed: \(error)")
                }
                dismiss()
            } label: {
                Text("Delete")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }
    
    @ViewBuilder
    private func backButtonLabel(showChevron: Bool) -> some View {
        Button {
            onBack?()
            dismiss()
        } label: {
            HStack(spacing: 6) {
                if showChevron {
                    Image(systemName: "chevron.backward")
                }
                Text("Back")
                    .fontWeight(.regular)
            }
            .padding(.trailing, 8)
            .padding(.leading, CustomBackButtonAnimationValue)
            .onAppear {
                withAnimation {
                    CustomBackButtonAnimationValue = 0
                }
            }
        }
    }
    
    // MARK: - Background

    /// Compute gradient on the fly for legacy contacts without stored gradient; persist so next time we use stored.
    private func updateDerivedBackgroundIfNeeded() async {
        let img = image
        guard img != UIImage(), !contact.photo.isEmpty else {
            await MainActor.run { derivedBackgroundColors = nil }
            return
        }
        if contact.hasPhotoGradient {
            await MainActor.run { derivedBackgroundColors = nil }
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            ImageAccessibleBackground.accessibleColors(from: img)
        }.value
        await MainActor.run {
            if let (base, end) = result {
                derivedBackgroundColors = (Color(base), Color(end))
                ImageAccessibleBackground.updateContactPhotoGradient(contact, image: img)
                try? modelContext.save()
            } else {
                derivedBackgroundColors = nil
            }
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            if image != UIImage() {
                photoHeader
            }
            
            VStack(spacing: 0) {
                headerControls
                summaryField
            }
        }
    }
    
    /// Photo-derived color used for the gradient that starts over the bottom of the photo (Apple Maps style). Nil when no gradient.
    private var photoGradientStartColor: Color? {
        contact.photoGradientColors?.start ?? derivedBackgroundColors?.base
    }

    @ViewBuilder
    private var photoHeader: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .overlay {
                    if let startColor = photoGradientStartColor {
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: startColor.opacity(0.0), location: 0.4),
                                .init(color: startColor.opacity(0.5), location: 0.7),
                                .init(color: startColor, location: 0.85)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black.opacity(0.0),
                                .black.opacity(0.2),
                                .black.opacity(0.8)
                            ]),
                            startPoint: .init(x: 0.5, y: 0.05),
                            endPoint: .bottom
                        )
                    }
                }
        }
        .contentShape(.rect)
        .frame(height: 400)
        .clipped()
        .onTapGesture {
            showPhotoFacesSheet = true
        }
    }
    
    @ViewBuilder
    private var headerControls: some View {
        HStack(alignment: .top, spacing: 12) {
            TextField(
                "Name",
                text: $contact.name ?? "",
                prompt: Text("Name")
                    .foregroundColor(image != UIImage() ? Color(.white.opacity(0.7)) : Color(uiColor: .placeholderText)),
                axis: .vertical
            )
            .font(.system(size: 36, weight: .bold))
            .lineLimit(4)
            .foregroundColor(image != UIImage() ? .white : .primary)
            
            if image == UIImage() {
                Button {
                    showPhotosPicker = true
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .foregroundColor(.blue)
                        .liquidGlass(in: Circle(), stroke: true, style: .clear)
                }
            }
            
            VStack(alignment: .trailing, spacing: 4){
                Button {
                    showTagPicker = true
                } label: {
                    if !(contact.tags?.isEmpty ?? true) {
                        Text((contact.tags ?? []).compactMap { $0.name }.sorted().joined(separator: ", "))
                            .foregroundColor(image != UIImage() ? .white : Color(.secondaryLabel))
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 44)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), stroke: true, style: .clear)
                    } else {
                        Image(systemName: "person.2")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .foregroundColor(image != UIImage() ? .purple.mix(with: .white, by: 0.3) : .purple)
                            .liquidGlass(in: Circle(), stroke: true, style: .clear)
                    }
                }
                
                dateDisplay
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var summaryField: some View {
        TextField(
            "",
            text: $contact.summary ?? "",
            prompt: Text("Main Note")
                .foregroundColor(image != UIImage() ? Color(uiColor: .lightText).opacity(0.8) : Color(uiColor:.placeholderText)),
            axis: .vertical
        )
        .lineLimit(2...)
        .padding(16)
        .foregroundStyle(image != UIImage() ? Color(uiColor: .lightText) : Color.primary)
        .textFieldStyle(.plain)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), stroke: true, style: .clear)
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    @ViewBuilder
    private var dateDisplay: some View {
        HStack {
            Spacer()
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .medium))
                    Text(formatMetDate(contact.timestamp, isLongAgo: contact.isMetLongAgo))
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(image != UIImage() ? .white.opacity(0.9) : Color(UIColor.secondaryLabel))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlass(in: Capsule(), stroke: true, style: .clear)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    // MARK: - Notes Section

    private var usesDerivedBackground: Bool { contact.photoGradientColors != nil || derivedBackgroundColors != nil }

    @ViewBuilder
    private var notesSection: some View {
        let activeNotes = (contact.notes ?? []).filter { $0.isArchived == false }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        VStack(alignment: .leading, spacing: 12) {
            addNoteButton
            
            ForEach(activeNotes, id: \.uuid) { note in
                noteCard(note)
            }
        }
        .padding(.bottom, 40)
        .animation(.default, value: activeNotes.map(\.uuid))
    }
    
    @ViewBuilder
    private var addNoteButton: some View {
        Button {
            let newNote = Note(content: "", creationDate: Date())
            if contact.notes == nil { contact.notes = [] }
            contact.notes?.append(newNote)
            withAnimation {
                do {
                    try modelContext.save()
                } catch {
                    print("Save failed: \(error)")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                Text("Add Note")
                    .font(.body.weight(.medium))
                Spacer()
            }
            .foregroundStyle(usesDerivedBackground ? Color.white.opacity(0.95) : .blue)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true, style: .clear)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "Note Content",
                text: Binding(
                    get: { note.content ?? "" },
                    set: { newValue in
                        note.content = newValue
                        do {
                            try modelContext.save()
                        } catch {
                            print("Save failed: \(error)")
                        }
                    }
                ),
                axis: .vertical
            )
            .font(.body)
            .lineLimit(2...)
            
            HStack {
                Button {
                    showNoteDatePickerFor(note: note)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                        Text(note.creationDate, style: .date)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Menu {
                    Button {
                        showNoteDatePickerFor(note: note)
                    } label: {
                        Label("Edit Date", systemImage: "calendar")
                    }
                    
                    Button(role: .destructive) {
                        withAnimation {
                            note.isArchived = true
                            note.archivedDate = Date()
                            do {
                                try modelContext.save()
                            } catch {
                                print("Save failed: \(error)")
                            }
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true, style: .clear)
        .padding(.horizontal)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Helper Methods

    func updateCroppingParameters(croppedImage: UIImage?, scale: CGFloat, offset: CGSize) {
        if let croppedImage = croppedImage {
            contact.photo = jpegDataForStoredContactPhoto(croppedImage)
            ImageAccessibleBackground.updateContactPhotoGradient(contact, image: croppedImage)
        }
        contact.cropScale = Float(scale)
        contact.cropOffsetX = Float(offset.width)
        contact.cropOffsetY = Float(offset.height)
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
    }

    private func showNoteDatePickerFor(note: Note) {
        noteBeingEdited = note
        showNoteDatePicker = true
    }
    
    private func formatMetDate(_ date: Date, isLongAgo: Bool) -> String {
        if isLongAgo {
            return "Met long ago"
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Met today"
        }
        
        if calendar.isDateInYesterday(date) {
            return "Met yesterday"
        }
        
        let components = calendar.dateComponents([.day], from: date, to: now)
        
        if let days = components.day, days > 0 {
            if days <= 7 {
                return "Met \(days) days ago"
            } else if days <= 14 {
                let weeks = days / 7
                return weeks == 1 ? "Met 1 week ago" : "Met \(weeks) weeks ago"
            }
        }
        
        return "Met \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Glass container when over photo (iOS 26+)
// Wrapping in GlassEffectContainer lets glass elements coordinate and render transparently instead of opaque/white.
private struct GlassContainerWhenPhotoModifier: ViewModifier {
    let hasPhoto: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), hasPhoto {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Face Recognition Supporting Views

/// Sheet presented when tapping the contact photo: detected faces count, "Find Similar Faces", and grid.
private struct ContactPhotoFacesSheet: View {
    let contact: Contact
    @ObservedObject var coordinator: FaceRecognitionCoordinator
    let onDismiss: () -> Void
    @Environment(\.modelContext) private var modelContext

    @State private var showDetectedGrid = false
    @State private var displayItemsForGrid: [FaceRecognitionCoordinator.ContactFaceDisplayItem] = []
    @State private var showDeleteConfirmation = false
    @State private var showSuggestedMatches = false
    @State private var suggestedItems: [FaceRecognitionCoordinator.ContactFaceDisplayItem] = []
    @State private var suggestedCount = 0

    private var recognizedCount: Int {
        coordinator.getRecognizedFacesCount(for: contact, in: modelContext)
    }

    private func refreshSuggestedCount() {
        suggestedCount = coordinator.getSuggestedCount(for: contact, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        coordinator.startFaceRecognition(for: contact, in: modelContext)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Find Similar Faces")
                                    .font(.body.weight(.medium))
                                Text("Scan your photo library for this person")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if coordinator.isAnalyzing(contact: contact) {
                                ProgressView()
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(coordinator.isAnalyzing(contact: contact))
                }

                if suggestedCount > 0 {
                    Section(header: Text("Suggested for you")) {
                        Button {
                            coordinator.getSuggestedDisplayItems(contact, in: modelContext) { items in
                                suggestedItems = items
                                showSuggestedMatches = true
                            }
                        } label: {
                            HStack {
                                Label("Review \(suggestedCount) suggested photo\(suggestedCount == 1 ? "" : "s")", systemImage: "person.crop.rectangle.badge.plus")
                                Spacer()
                                Text("Confirm or reject")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("Detected Faces")) {
                    if recognizedCount > 0 {
                        Button {
                            coordinator.getDisplayItemsForContact(contact, in: modelContext) { items in
                                displayItemsForGrid = items
                                showDetectedGrid = true
                            }
                        } label: {
                            HStack {
                                Label("\(recognizedCount) photo\(recognizedCount == 1 ? "" : "s") with \(contact.displayName)", systemImage: "photo.on.rectangle.angled")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete all recognized photos", systemImage: "trash")
                        }
                    } else {
                        Text("No photos yet. Tap \"Find Similar Faces\" to discover photos of \(contact.displayName) in your library.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Faces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .sheet(isPresented: $showDetectedGrid) {
                ContactDetectedFacesSheet(
                    contact: contact,
                    displayItems: displayItemsForGrid,
                    onDismiss: { showDetectedGrid = false }
                )
            }
            .sheet(isPresented: $showSuggestedMatches) {
                SuggestedMatchesView(
                    contact: contact,
                    items: suggestedItems,
                    coordinator: coordinator,
                    onDismiss: {
                        showSuggestedMatches = false
                        refreshSuggestedCount()
                    }
                )
                .environment(\.modelContext, modelContext)
            }
            .confirmationDialog("Delete Recognized Photos", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete all recognized photos", role: .destructive) {
                    coordinator.deleteRecognizedFaces(for: contact, in: modelContext)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes all face recognition data for \(contact.displayName). You can run \"Find Similar Faces\" again later.")
            }
            .onAppear {
                refreshSuggestedCount()
                // Apple-style: trigger scan when user enters Faces view, if no photos yet and contact has a photo
                if recognizedCount == 0,
                   !coordinator.isAnalyzing(contact: contact),
                   !contact.photo.isEmpty {
                    coordinator.startFaceRecognition(for: contact, in: modelContext)
                }
            }
        }
    }
}

/// Apple Photos–style view to review and confirm or reject suggested face matches.
private struct SuggestedMatchesView: View {
    let contact: Contact
    @State private var remainingItems: [FaceRecognitionCoordinator.ContactFaceDisplayItem]
    @ObservedObject var coordinator: FaceRecognitionCoordinator
    let onDismiss: () -> Void
    @Environment(\.modelContext) private var modelContext
    private let imageManager = PHCachingImageManager()

    init(
        contact: Contact,
        items: [FaceRecognitionCoordinator.ContactFaceDisplayItem],
        coordinator: FaceRecognitionCoordinator,
        onDismiss: @escaping () -> Void
    ) {
        self.contact = contact
        _remainingItems = State(initialValue: items)
        self.coordinator = coordinator
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            Group {
                if remainingItems.isEmpty {
                    ContentUnavailableView(
                        "All reviewed",
                        systemImage: "checkmark.circle",
                        description: Text("You've reviewed all suggested photos for \(contact.displayName).")
                    )
                } else {
                    List {
                        ForEach(remainingItems) { item in
                            SuggestedMatchRow(
                                item: item,
                                contact: contact,
                                coordinator: coordinator,
                                modelContext: modelContext,
                                onConfirm: { removeItem(item) },
                                onReject: { removeItem(item) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Suggested for \(contact.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }

    private func removeItem(_ item: FaceRecognitionCoordinator.ContactFaceDisplayItem) {
        remainingItems.removeAll { $0.id == item.id }
    }
}

/// Single row in SuggestedMatchesView: thumbnail + Confirm / Not this person.
private struct SuggestedMatchRow: View {
    let item: FaceRecognitionCoordinator.ContactFaceDisplayItem
    let contact: Contact
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
                    Button("Yes, it's them") {
                        coordinator.confirmSuggested(for: contact, item: item, in: modelContext)
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not this person") {
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

/// Sheet showing all photos where this contact's face was detected (library photos + name-faces-assigned thumbnails).
private struct ContactDetectedFacesSheet: View {
    let contact: Contact
    let displayItems: [FaceRecognitionCoordinator.ContactFaceDisplayItem]
    let onDismiss: () -> Void
    private let imageManager = PHCachingImageManager()

    var body: some View {
        NavigationStack {
            Group {
                if displayItems.isEmpty {
                    ContentUnavailableView(
                        "No Photos Yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Run \"Find Similar Faces\" to discover photos of \(contact.displayName) in your library.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)
                        ], spacing: 8) {
                            ForEach(displayItems) { item in
                                if let asset = item.asset {
                                    DetectedFaceThumbnail(asset: asset)
                                } else if let data = item.thumbnailData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(minWidth: 100, minHeight: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Photos of \(contact.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

/// Thumbnail for a single photo in the detected-faces grid
private struct DetectedFaceThumbnail: View {
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
                Rectangle()
                    .fill(Color(UIColor.tertiarySystemFill))
            }
        }
        .frame(minWidth: 100, minHeight: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            image = img
        }
    }
}
