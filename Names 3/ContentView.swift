//
//  ContentView.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import SwiftUI
import SwiftData
import PhotosUI
import Vision
import SmoothGradient

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Query private var contacts: [Contact]
    @State private var parsedContacts: [Contact] = []
    
    @State private var selectedItem: PhotosPickerItem?
    
    @State private var isAtBottom = false
    private let dragThreshold: CGFloat = 100
    @FocusState private var fieldIsFocused: Bool
    
    @State private var text = ""
    @State private var date = Date()

    @State private var showPhotosPicker = false
    @State private var showQuizView = false
    @State private var showRegexHelp = false
    @State private var showReviewNotes = false
    @State private var showBulkAddFaces = false
    @State private var showGroupPhotos = false
    
    @State private var name = ""
    @State private var hashtag = ""
    
    @State private var filterString = ""
    @State private var suggestedContacts: [Contact] = []
    
    @State private var showGroupDatePicker = false
    @State private var selectedGroup: contactsGroup?
    @State private var tempGroupDate = Date()

    @State private var showPhotosDayPicker = false
    @State private var pickedImageForBatch: UIImage?
    @State private var photosPickerDay = Date()
    @State private var groupForDateEdit: contactsGroup?
    @State private var isLoading = false

    // Group contacts by the day of their timestamp, with a special "Met long ago" group at the top
    var groups: [contactsGroup] {
        let calendar = Calendar.current
        
        let longAgoContacts = contacts.filter { $0.isMetLongAgo }
        let regularContacts = contacts.filter { !$0.isMetLongAgo }
        
        let longAgoParsed = parsedContacts.filter { $0.isMetLongAgo }
        let regularParsed = parsedContacts.filter { !$0.isMetLongAgo }
        
        let groupedRegularContacts = Dictionary(grouping: regularContacts) { contact in
            calendar.startOfDay(for: contact.timestamp)
        }
        let groupedRegularParsed = Dictionary(grouping: regularParsed) { parsedContact in
            calendar.startOfDay(for: parsedContact.timestamp)
        }
        
        let allDates = Set(groupedRegularContacts.keys).union(groupedRegularParsed.keys)
        
        var result: [contactsGroup] = []
        
        if !longAgoContacts.isEmpty || !longAgoParsed.isEmpty {
            let longAgoGroup = contactsGroup(
                date: .distantPast,
                contacts: longAgoContacts.sorted { $0.timestamp < $1.timestamp },
                parsedContacts: longAgoParsed.sorted { $0.timestamp < $1.timestamp },
                isLongAgo: true
            )
            result.append(longAgoGroup)
        }
        
        let datedGroups = allDates.map { date in
            let sortedContacts = (groupedRegularContacts[date] ?? []).sorted { $0.timestamp < $1.timestamp }
            let sortedParsedContacts = (groupedRegularParsed[date] ?? []).sorted { $0.timestamp < $1.timestamp }
            return contactsGroup(
                date: date,
                contacts: sortedContacts,
                parsedContacts: sortedParsedContacts,
                isLongAgo: false
            )
        }
        .sorted { $0.date < $1.date }
        
        result.append(contentsOf: datedGroups)
        return result
    }
    
    var dynamicBackground: Color {
        if fieldIsFocused {
            return colorScheme == .light ? .clear : .clear
        } else {
            return colorScheme == .light ? .clear : .clear
        }
    }
    
    var gridSpacing = 10.0
    
    var columns = [
        GridItem(.flexible(), spacing: 10.0),
        GridItem(.flexible(), spacing: 10.0),
        GridItem(.flexible(), spacing: 10.0),
        GridItem(.flexible(), spacing: 10.0)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false){
                    ForEach(groups) { group in
                        Section{
                            VStack(alignment: .leading){
                                HStack{
                                    Text(group.title)
                                        .font(.title)
                                        .bold()
                                    Spacer()
                                }
                                .padding(.leading)
                                .padding(.trailing, 14)
                                Text(group.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                            .padding(.bottom, 4)
                            .contentShape(Rectangle())
                                                                  .onTapGesture {
                                                                      if !group.isLongAgo {
                                                                          selectedGroup = group
                                                                          tempGroupDate = group.date
                                                                      }
                                                                  }

                            
                            LazyVGrid(columns: Array(repeating: GridItem(spacing: 10), count: 4), spacing: 10) {
                                ForEach(group.contacts) { contact in
                                    NavigationLink {
                                        ContactDetailsView(contact: contact)
                                    } label: {
                                        GeometryReader {
                                            let size = $0.size
                                            ZStack{
                                                Image(uiImage: UIImage(data: contact.photo) ?? UIImage())
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: size.width, height: size.height)
                                                    .clipped()
                                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                                
                                                if !contact.photo.isEmpty {
                                                    LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.0), .black.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                                                }
                                                
                                                VStack {
                                                    Spacer()
                                                    Text(contact.name ?? "")
                                                        .font(.footnote)
                                                        .bold()
                                                        .foregroundColor( contact.photo.isEmpty ? Color(uiColor: .label).opacity(0.8) : Color(uiColor: .white).opacity(0.8)
                                                        )
                                                        .padding(.bottom, 6)
                                                        .padding(.horizontal, 6)
                                                        .multilineTextAlignment(.center)
                                                        .lineSpacing(-2)
                                                }
                                            }
                                        }
                                        .frame(height: 88)
                                        .contentShape(.rect)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .scrollTransition { content, phase in
                                            content
                                                .opacity(phase.isIdentity ? 1 : 0.3)
                                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                        }
                                    }
                                }
                                ForEach(Array(group.parsedContacts.enumerated()), id: \.offset) { _, contact in
                                    GeometryReader {
                                        let size = $0.size
                                        ZStack{
                                            Image(uiImage: UIImage(data: contact.photo) ?? UIImage())
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: size.width, height: size.height)
                                                .clipped()
                                                .background(Color(uiColor: .black).opacity(0.05))
                                            
                                            VStack {
                                                Spacer()
                                                Text(contact.name ?? "")
                                                    .font(.footnote)
                                                    .bold()
                                                    .foregroundColor(UIImage(data: contact.photo) != UIImage() ? Color(uiColor: .label).opacity(0.8) : Color(uiColor: .white).opacity(0.8)
                                                    )
                                                    .padding(.bottom, 6)
                                                    .padding(.horizontal, 6)
                                                    .multilineTextAlignment(.center)
                                                    .lineSpacing(-2)
                                            }
                                        }
                                    }
                                    
                                    .frame(height: 88)
                                    .contentShape(.rect)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    
                                }
                                
                                
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: contacts) { oldValue, newValue in
                    proxy.scrollTo(contacts.last?.id)
                }
            }
            .safeAreaInset(edge: .top){
                ZStack(alignment: .top) {
                    SmoothLinearGradient(
                        from: Color(red: 0.0, green: 0.0, blue: 0.04).opacity(0.62),
                        to: Color(red: 0.0, green: 0.0, blue: 0.04).opacity(0.0),
                        startPoint: UnitPoint(x: 0.5, y: 0.18),
                        endPoint: .bottom,
                        curve: .easeInOut
                    )
                    .ignoresSafeArea(.all)
                    .frame(height: 100)
                }
                .frame(height: 70)
            }
            
            .safeAreaInset(edge: .bottom) {
                VStack{
                    HStack(spacing: 4){
                        Button{
                            showQuizView = true
                        } label:{
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.white)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(10)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(
                                            colors:
                                                [.black.opacity(0.1),
                                                 .black.opacity(0.2)
                                                ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing))
                                .background(.thickMaterial)
                                .clipShape(Circle())
                        }
                        
                        Button{
                            showReviewNotes = true
                        } label:{
                            Image(systemName: "note.text")
                                .foregroundStyle(.white)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(10)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(
                                            colors:
                                                [.black.opacity(0.1),
                                                 .black.opacity(0.2)
                                                ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing))
                                .background(.thickMaterial)
                                .clipShape(Circle())
                        }
                        
                        TextField("", text: $text, axis: .vertical)
                            .padding(.horizontal,16)
                            .padding(.vertical,8)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onChange(of: text){ oldValue, newValue in
                                if let last = newValue.last, last == "\n" {
                                    text.removeLast()
                                    saveContacts(modelContext: modelContext)
                                } else {
                                    parseContacts()
                                }
                            }
                            .focused($fieldIsFocused)
                            .submitLabel(.send)
                        
                        Button {
                            showRegexHelp = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.white)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(10)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(
                                            colors:
                                                [.black.opacity(0.1),
                                                 .black.opacity(0.2)
                                                ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing))
                                .background(.thickMaterial)
                                .clipShape(Circle())
                        }

                    }
                    
                    ScrollView(.horizontal){
                        HStack{
                            ForEach(suggestedContacts){ contact in
                                Text(contact.name!)
                            }
                        }
                    }
                    .frame(height: 20)
                }
                .padding(.bottom, 8)
                .padding(.horizontal)
                .background(dynamicBackground)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if isLoading {
                    LoadingOverlay(message: "Loading…")
                }
            }
            
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Names")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.leading)
                    
                    
                    DatePicker(selection: $date, in: ...Date(), displayedComponents: .date){}
                        .labelsHidden()
                    
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                        }) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showBulkAddFaces = true
                        } label: {
                            Label("Bulk add faces", systemImage: "person.crop.square.badge.plus")
                        }
                        Button {
                            showGroupPhotos = true
                        } label: {
                            Label("Group Photos", systemImage: "person.3.sequence")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            
                    }
                }
            }
            .toolbarBackground(.hidden)
            
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
            .sheet(isPresented: $showQuizView) {
                QuizView(contacts: contacts)
            }
            .sheet(isPresented: $showRegexHelp) {
                RegexShortcutsView()
            }
            .sheet(isPresented: $showReviewNotes) {
                ReviewNotesView(contacts: contacts)
            }
            .sheet(isPresented: $showBulkAddFaces) {
                // Contacts save in the existing CloudKit store; batches use a dedicated CloudKit store
                BulkAddFacesView(contactsContext: modelContext)
                    .modelContainer(BatchModelContainer.shared)
            }
            .sheet(isPresented: $showGroupPhotos) {
                GroupPhotosListView(contactsContext: modelContext)
                    .modelContainer(BatchModelContainer.shared)
            }
            // Group actions bottom sheet
            .sheet(item: $selectedGroup) { group in
                GroupActionsSheet(
                    date: group.date,
                    onImport: {
                        let day = group.date
                        selectedGroup = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            photosPickerDay = day
                            showPhotosDayPicker = true
                        }
                    },
                    onEditDate: {
                        groupForDateEdit = group
                        selectedGroup = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            tempGroupDate = group.date
                            showGroupDatePicker = true
                        }
                    }
                )
                .presentationDetents([.height(220), .medium])
                .presentationDragIndicator(.visible)
            }
            // Day-filtered photos picker
            // Use a host that overlays a spinner until content is ready to render
            .sheet(isPresented: $showPhotosDayPicker) {
                PhotosDayPickerHost(day: photosPickerDay) { image in
                    pickedImageForBatch = image
                    showPhotosDayPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showBulkAddFacesWithSeed(image: image, date: photosPickerDay)
                    }
                }
            }
            .sheet(isPresented: $showGroupDatePicker) {
                NavigationStack {
                    VStack {
                        DatePicker("New Date", selection: $tempGroupDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(GraphicalDatePickerStyle())
                            .padding()
                        Spacer()
                    }
                    .navigationTitle("Change Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showGroupDatePicker = false
                                groupForDateEdit = nil
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Apply") {
                                applyGroupDateChange()
                            }
                        }
                    }
                }
            }
        }
        
    }


    private func parseContacts() {
        let input = text
        let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var detectedDate: Date? = nil
        var cleanedInput = input

        if let matches = dateDetector?.matches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
            for match in matches {
                if match.resultType == .date, let date = match.date {
                    detectedDate = adjustToPast(date)
                    if let range = Range(match.range, in: input) {
                        cleanedInput.removeSubrange(range)
                    }
                    break
                }
            }
        }

        let fallbackDate = Date()
        let finalDate = detectedDate ?? fallbackDate

        let nameEntries = cleanedInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var contacts: [Contact] = []
        var globalTags: [Tag] = []
        var globalTagKeys = Set<String>()

        let allWords = cleanedInput.split(separator: " ").map { String($0) }
        for word in allWords {
            if word.starts(with: "#") {
                let raw = String(word.dropFirst())
                let trimmed = raw.trimmingCharacters(in: .punctuationCharacters)
                let key = Tag.normalizedKey(trimmed)
                if !trimmed.isEmpty && !globalTagKeys.contains(key) {
                    if let tag = Tag.fetchOrCreate(named: trimmed, in: modelContext) {
                        globalTags.append(tag)
                        globalTagKeys.insert(key)
                    }
                }
            }
        }
        
        for entry in nameEntries {
            if entry.starts(with: "#") {
                continue
            }

            var nameComponents: [String] = []
            var notes: [Note] = []
            var summary: String? = nil

            if entry.contains("::") {
                let parts = entry.split(separator: "::", maxSplits: 1)
                if parts.count == 2 {
                    nameComponents = parts[0].split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
                    summary = String(parts[1].trimmingCharacters(in: .whitespaces))
                } else {
                    nameComponents = parts[0].split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
                }
            } else {
                nameComponents = entry.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            }
            
            var name = nameComponents.joined(separator: " ")
            
            if !name.isEmpty {
                
                filterString = name
                filterContacts()

                if let notePart = nameComponents.last, notePart.contains(":") {
                    let nameAndNote = notePart.split(separator: ":", maxSplits: 1)
                    if nameAndNote.count == 2 {
                        name = nameAndNote[0].trimmingCharacters(in: .whitespaces)
                        let noteContent = nameAndNote[1].trimmingCharacters(in: .whitespaces)
                        if !noteContent.isEmpty {
                            let note = Note(content: noteContent, creationDate: finalDate)
                            notes.append(note)
                        }
                    } else {
                        name = nameAndNote[0].trimmingCharacters(in: .whitespaces)
                    }
                }
                
                if name.hasSuffix(":") {
                    name = String(name.dropLast())
                }
                
                let contact = Contact(name: name, timestamp: finalDate, notes: notes, tags: globalTags, photo: Data())
                contact.summary = summary
                contacts.append(contact)
            }
        }
        parsedContacts = contacts
    }
    
    private func filterContacts() {
        if filterString.isEmpty {
            suggestedContacts = contacts
        } else {
            suggestedContacts = contacts.filter { contact in
                if let name = contact.name {
                    return name.starts(with: filterString)
                }
                return false
            }
        }
    }

    private func adjustToPast(_ date: Date) -> Date {
        let today = Date()
        let calendar = Calendar.current

        if date > today {
            let adjustedDate = calendar.date(byAdding: .year, value: -1, to: date)
            return adjustedDate ?? date
        }

        return date
    }
    
    func saveContacts(modelContext: ModelContext) {
        isLoading = true
        defer { isLoading = false }

        for contact in parsedContacts {
            modelContext.insert(contact)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
        
        text = ""
        parsedContacts = []
    }

    private func addItem() {
        withAnimation {
            let newContact = Contact(timestamp: Date(), notes: [], photo: Data())
            modelContext.insert(newContact)
        }
    }
    
    private func applyGroupDateChange() {
        if let group = groupForDateEdit {
            updateGroupDate(for: group, newDate: tempGroupDate)
        }
        showGroupDatePicker = false
        groupForDateEdit = nil
    }
    
    private func updateGroupDate(for group: contactsGroup, newDate: Date) {
        for c in group.contacts {
            c.isMetLongAgo = false
            c.timestamp = combine(date: newDate, withTimeFrom: c.timestamp)
        }
        for c in group.parsedContacts {
            c.isMetLongAgo = false
            c.timestamp = combine(date: newDate, withTimeFrom: c.timestamp)
        }
    }
    
    private func combine(date: Date, withTimeFrom timeSource: Date) -> Date {
        let cal = Calendar.current
        let dateComps = cal.dateComponents([.year, .month, .day], from: date)
        let timeComps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: timeSource)
        var merged = DateComponents()
        merged.year = dateComps.year
        merged.month = dateComps.month
        merged.day = dateComps.day
        merged.hour = timeComps.hour
        merged.minute = timeComps.minute
        merged.second = timeComps.second
        merged.nanosecond = timeComps.nanosecond
        return cal.date(from: merged) ?? date
    }
}

struct ContactFormView: View {
    @Bindable var contact: Contact
    
    var body: some View {
        Form{
            Section{
                TextField("Name", text: $contact.name ?? "")
            }
        }
    }
}


struct ContactDetailsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var contact: Contact
    
    @State var viewState = CGSize.zero
    
    @State private var showPhotosPicker = false
    
    @State private var selectedItem: PhotosPickerItem?
    
    @State private var showDatePicker = false
    @State private var showTagPicker = false
    @State private var showCropView = false
    @State private var isLoading = false
    
    @Query private var notes: [Note]
    
    @State private var noteText = ""
    @State private var stateNotes : [Note] = []
    @State private var CustomBackButtonAnimationValue = 40.0
    
    var image: UIImage { UIImage(data: contact.photo) ?? UIImage() }
    
    var body: some View {
            GeometryReader { g in
                ScrollView{
                    ZStack(alignment: .bottom){
                        if image != UIImage() {
                            GeometryReader {
                                let size = $0.size
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size.width, height: size.height)
                                    .overlay {
                                        LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.2), .black.opacity(0.8)]), startPoint: .init(x: 0.5, y: 0.05), endPoint: .bottom)
                                    }
                            }
                            .contentShape(.rect)
                            .frame(height: 400)
                            .clipped()
                        }
                        
                        VStack{
                            HStack{
                                TextField(
                                    "Name",
                                    text: $contact.name ?? "",
                                    prompt: Text("Name")
                                        .foregroundColor(image != UIImage() ? Color(.white.opacity(0.7)) : Color(uiColor: .placeholderText) ),
                                    axis: .vertical
                                )
                                .font(.system(size: 36, weight: .bold))
                                .lineLimit(4)
                                .foregroundColor(image != UIImage() ? .white : .primary )
                                
                                Image(systemName: "camera")
                                    .font(.system(size: 18))
                                    .padding(12)
                                    .foregroundColor(image != UIImage() ? .blue.mix(with: .white, by: 0.3) : .blue)
                                    .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.blue.opacity(0.08))))
                                    .background(image != UIImage() ? .black.opacity(0.2) : .clear)
                                    .clipShape(Circle())
                                    .onTapGesture { showPhotosPicker = true }
                                    .padding(.leading, 4)
                                
                                Group{
                                    if !(contact.tags?.isEmpty ?? true) {
                                        Text((contact.tags ?? []).compactMap { $0.name }.sorted().joined(separator: ", "))
                                            .foregroundColor(image != UIImage() ? .white : Color(.secondaryLabel) )
                                            .font(.system(size: 15, weight: .medium))
                                            .padding(.vertical, 7)
                                            .padding(.bottom, 1)
                                            .padding(.horizontal, 13)
                                            .background(image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.6)) : AnyShapeStyle(Color(.quaternarySystemFill )))
                                            .cornerRadius(8)
                                        
                                    } else {
                                        Image(systemName: "person.2")
                                            .font(.system(size: 18))
                                            .padding(12)
                                            .foregroundColor(image != UIImage() ? .purple.mix(with: .white, by: 0.3) : .purple)
                                            .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.purple.opacity(0.08))))
                                            .clipShape(Circle())
                                            .padding(.leading, 4)
                                    }
                                }
                                .onTapGesture { showTagPicker = true }
                            }
                            .padding(.horizontal)
                            
                            TextField(
                                "",
                                text: $contact.summary ?? "",
                                prompt: Text("Main Note")
                                    .foregroundColor(image != UIImage() ? Color(uiColor: .lightText).opacity(0.8) : Color(uiColor:.placeholderText)),
                                axis: .vertical
                            )
                            .lineLimit(2...)
                            .padding(10)
                            .foregroundStyle(image != UIImage() ? Color(uiColor: .lightText) : Color.primary)
                            .background(
                                BlurView(style: .regular)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            
                            
                            .padding(.horizontal).padding(.top, 12)
                            .onTapGesture {
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        viewState = value.translation
                                    }
                            )
                            
                            HStack{
                                Spacer()
                                Text(contact.timestamp, style: .date)
                                    .foregroundColor(image != UIImage() ? .white : Color(UIColor.secondaryLabel))
                                    .font(.system(size: 15))
                                    .frame(alignment: .trailing)
                                    .padding(.top, 4)
                                    .padding(.trailing)
                                    .padding(.trailing, 4)
                                    .onTapGesture {
                                        showDatePicker = true
                                    }
                                    .padding(.bottom)
                                    .onAppear{
                                    }
                            }
                        }
                    }
                    
                    HStack{
                        Text("Notes")
                            .font(.body.smallCaps())
                            .fontWeight(.light)
                            .foregroundStyle(.secondary)
                            .padding(.leading)
                        Spacer()
                    }
                    Button(action: {
                        let newNote = Note(content: "Test", creationDate: Date())
                        if contact.notes == nil { contact.notes = [] }
                        contact.notes?.append(newNote)
                        do {
                            try modelContext.save()
                        } catch {
                            print("Save failed: \(error)")
                        }
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Note")
                            Spacer()
                        }
                        .padding(.horizontal).padding(.vertical, 14)
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    List{
                        let array = contact.notes ?? []
                        ForEach(array, id: \.self) { note in
                            Section{
                                VStack {
                                    TextField("Note Content", text: Binding(
                                        get: { note.content },
                                        set: { note.content = $0 }
                                    ), axis: .vertical)
                                        .lineLimit(2...)
                                    HStack {
                                        Spacer()
                                        Text(note.creationDate, style: .date)
                                            .font(.caption)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                    } label: {
                                        Label("Edit Date", systemImage: "calendar")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
                .padding(.top, image != UIImage() ? 0 : 8 )
                .ignoresSafeArea(image != UIImage() ? .all : [])
                .background(Color(UIColor.systemGroupedBackground))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                            } label: {
                                Text("Duplicate")
                            }
                            Button {
                                modelContext.delete(contact)
                                dismiss()
                            } label: {
                                Text("Delete")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
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
                .navigationBarBackButtonHidden(true)
            }
            .toolbarBackground(.hidden)
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
            .sheet(isPresented: $showDatePicker) {
                CustomDatePicker(contact: contact)
            }
            .sheet(isPresented: $showTagPicker) {
                CustomTagPicker(contact: contact)
            }
            .fullScreenCover(isPresented: $showCropView){
                if let image = UIImage(data: contact.photo) {
                    CropView(
                        image: image,
                        initialScale: CGFloat(contact.cropScale),
                        initialOffset: CGSize(width: CGFloat(contact.cropOffsetX), height: CGFloat(contact.cropOffsetY))
                    ) { croppedImage, scale, offset in
                        updateCroppingParameters(croppedImage: croppedImage, scale: scale, offset: offset)
                    }
                }
            }
            .overlay {
                if isLoading {
                    LoadingOverlay(message: "Processing photo…")
                }
            }
            .onChange(of: selectedItem) {
                isLoading = true
                Task {
                    if let loaded = try? await selectedItem?.loadTransferable(type: Data.self) {
                        contact.photo = loaded
                        showCropView = true
                        do {
                            try modelContext.save()
                        } catch {
                            print("Save failed: \(error)")
                        }
                    } else {
                        print("Failed")
                    }
                    isLoading = false
                }
            }
    }
    
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
}

struct CustomDatePicker: View {
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var date = Date()
    @State private var bool: Bool = false
    
    var body: some View {
        
        VStack{
            GroupBox{
                Toggle("Met long ago", isOn: $contact.isMetLongAgo)
                    .onChange(of: contact.isMetLongAgo) { old, new in
                        if true {
                        } else {
                        }
                    }
                    Divider()
                    DatePicker("Exact Date", selection: $contact.timestamp,in: ...Date(),displayedComponents: .date)
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .disabled(contact.isMetLongAgo)
                
            }
            .backgroundStyle(Color(UIColor.systemBackground))
            .padding()
            Spacer()
        }
        .containerRelativeFrame([.horizontal, .vertical])
        .background(Color(UIColor.systemGroupedBackground))
    }
}

struct CustomTagPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tags: [Tag]
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    
    var body: some View{
        NavigationView{
            List{
                
                if !searchText.isEmpty {
                    Section{
                        Button{
                            if let tag = Tag.fetchOrCreate(named: searchText, in: modelContext) {
                                if !(contact.tags?.contains(where: { $0.normalizedKey == tag.normalizedKey }) ?? false) {
                                    if contact.tags == nil { contact.tags = [] }
                                    contact.tags?.append(tag)
                                }
                            }
                        } label: {
                            Group{
                                HStack{
                                    Text("Add \(searchText)")
                                    Image(systemName: "plus.circle.fill")
                                }
                            }
                        }
                    }
                }
                
                Section{
                    let uniqueTags: [Tag] = {
                        var map: [String: Tag] = [:]
                        for tag in tags {
                            let key = tag.normalizedKey
                            if map[key] == nil { map[key] = tag }
                        }
                        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    }()
                    
                    ForEach(uniqueTags, id: \.self) { tag in
                        HStack{
                            Text(tag.name)
                            Spacer()
                            if contact.tags?.contains(where: { $0.normalizedKey == tag.normalizedKey }) == true {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let existingIndex = contact.tags?.firstIndex(where: { $0.normalizedKey == tag.normalizedKey }) {
                                contact.tags?.remove(at: existingIndex)
                            } else {
                                if contact.tags == nil { contact.tags = [] }
                                contact.tags?.append(tag)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groups & Places")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement:.navigationBarDrawer(displayMode: .always))
            .contentMargins(.top, 8)
        }
    }
}

func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}

#Preview("List") {
        ContentView().modelContainer(for: [Contact.self, Note.self, Tag.self], inMemory: true)
}

#Preview("Contact Detail") {
    ModelContainerPreview(ModelContainer.sample) {
        NavigationStack{
            ContactDetailsView(contact:.ross)
        }
    }
}

private func downscaleJPEG(data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
    guard let image = UIImage(data: data) else { return data }
    let width = image.size.width
    let height = image.size.height
    let maxSide = max(width, height)
    guard maxSide > maxDimension else {
        return image.jpegData(compressionQuality: quality) ?? data
    }
    let scale = maxDimension / maxSide
    let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    return scaled.jpegData(compressionQuality: quality) ?? data
}

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    init(style: UIBlurEffect.Style) {
        self.style = style
    }
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: style)
        let blurView = UIVisualEffectView(effect: blurEffect)
        return blurView
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}

private struct GroupActionsSheet: View {
    let date: Date
    let onImport: () -> Void
    let onEditDate: () -> Void
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date, style: .date)
                            .font(.title3.weight(.semibold))
                        Text(relativeString(for: date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        isBusy = true
                        onImport()
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Import photos for this day")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isBusy = true
                        onEditDate()
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                            Text("Edit date")
                            Spacer()
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)
                }
                .padding()

                if isBusy {
                    // Non-blocking spinner overlay while the next sheet is prepared/presented
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .navigationTitle("Group")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func relativeString(for date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// Lightweight host that overlays a spinner during the initial render of PhotosDayPickerView
private struct PhotosDayPickerHost: View {
    let day: Date
    let onPick: (UIImage) -> Void
    @State private var showSpinner = true

    var body: some View {
        ZStack {
            PhotosDayPickerView(day: day) { image in
                onPick(image)
            }

            if showSpinner {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading photos…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        // Give SwiftUI one frame to build the sheet’s view hierarchy before hiding the spinner
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                showSpinner = false
            }
        }
    }
}

private extension ContentView {
    func showBulkAddFacesWithSeed(image: UIImage, date: Date, completion: (() -> Void)? = nil) {
        let root = UIHostingController(
            rootView: BulkAddFacesView(contactsContext: modelContext, initialImage: image, initialDate: date)
                .modelContainer(BatchModelContainer.shared)
        )
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let rootVC = window.rootViewController {
            root.modalPresentationStyle = .formSheet
            rootVC.present(root, animated: true) {
                completion?()
            }
        } else {
            completion?()
        }
    }
}

private struct LoadingOverlay: View {
    var message: String? = nil
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                if let message {
                    Text(message)
                        .foregroundColor(.white)
                        .font(.footnote)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .transition(.opacity)
    }
}
