import SwiftUI
import SwiftData
import UIKit
import TipKit

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

    var body: some View {
        GeometryReader { g in
            ScrollView{
                VStack(spacing: 0) {
                    headerSection
                    
                    notesSection
                        .padding(.top, 20)
                }
            }
            .padding(.top, image != UIImage() ? 0 : 8 )
            .ignoresSafeArea(image != UIImage() ? .all : [])
            .background(Color(UIColor.systemGroupedBackground))
            .scrollIndicators(.hidden)
            .onAppear {
                // Donate event when user views contact details
                TipManager.shared.donateContactViewed()
            }
            .toolbar {
                if isCreationFlow {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            onCancel?() ?? dismiss()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            do {
                                try modelContext.save()
                            } catch {
                                print("Save failed: \(error)")
                            }
                            onSave?()
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
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
                                .padding(8)
                                .liquidGlass(in: Capsule())
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            onBack?()
                            dismiss()
                        } label: {
                            HStack {
                                HStack{
                                    Image(systemName: image != UIImage() ? "" : "chevron.backward")
                                    Text("Back")
                                        .fontWeight(image != UIImage() ? .medium : .regular)
                                }
                                .padding(.trailing, 8)
                            }
                            .padding(.leading, CustomBackButtonAnimationValue)
                            .onAppear{
                                withAnimation {
                                    CustomBackButtonAnimationValue = 0
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
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
                dateDisplay
            }
        }
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
        .contentShape(.rect)
        .frame(height: 400)
        .clipped()
        .onTapGesture {
            showPhotosPicker = true
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
            
            Button {
                showPhotosPicker = true
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .foregroundColor(image != UIImage() ? .blue.mix(with: .white, by: 0.3) : .blue)
                    .liquidGlass(in: Circle(), stroke: true)
            }
            
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
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), stroke: true)
                } else {
                    Image(systemName: "person.2")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .foregroundColor(image != UIImage() ? .purple.mix(with: .white, by: 0.3) : .purple)
                        .liquidGlass(in: Circle(), stroke: true)
                }
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
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), stroke: true)
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
                .liquidGlass(in: Capsule(), stroke: true)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
    
    // MARK: - Notes Section
    
    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notes")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal)
            
            addNoteButton
            
            let activeNotes = (contact.notes ?? []).filter { $0.isArchived == false }
            ForEach(activeNotes, id: \.self) { note in
                noteCard(note)
            }
        }
        .padding(.bottom, 40)
    }
    
    @ViewBuilder
    private var addNoteButton: some View {
        Button {
            let newNote = Note(content: "", creationDate: Date())
            if contact.notes == nil { contact.notes = [] }
            contact.notes?.append(newNote)
            do {
                try modelContext.save()
            } catch {
                print("Save failed: \(error)")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                Text("Add Note")
                    .font(.body.weight(.medium))
                Spacer()
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true)
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
                        note.isArchived = true
                        note.archivedDate = Date()
                        do {
                            try modelContext.save()
                        } catch {
                            print("Save failed: \(error)")
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
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true)
        .padding(.horizontal)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Helper Methods

    func updateCroppingParameters(croppedImage: UIImage?, scale: CGFloat, offset: CGSize) {
        if let croppedImage = croppedImage {
            contact.photo = croppedImage.jpegData(compressionQuality: 1.0) ?? Data()
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