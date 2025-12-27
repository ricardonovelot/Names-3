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
                        GroupSectionView(
                            group: group,
                            onHeaderTap: {
                                if !group.isLongAgo {
                                    selectedGroup = group
                                    tempGroupDate = group.date
                                }
                            }
                        )
                    }
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: contacts) { oldValue, newValue in
                    if let lastID = contacts.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
//            .safeAreaInset(edge: .top){
//                ZStack(alignment: .top) {
//                    SmoothLinearGradient(
//                        from: Color(red: 0.0, green: 0.0, blue: 0.04).opacity(0.62),
//                        to: Color(red: 0.0, green: 0.0, blue: 0.04).opacity(0.0),
//                        startPoint: UnitPoint(x: 0.5, y: 0.18),
//                        endPoint: .bottom,
//                        curve: .easeInOut
//                    )
//                    .ignoresSafeArea(.all)
//                    .frame(height: 100)
//                }
//                .frame(height: 70)
//            }
            
            .safeAreaInset(edge: .bottom) {
                VStack{
                    HStack(spacing: 6){
                       
                        
                        TextField("", text: $text, axis: .vertical)
                            .padding(.horizontal,32)
                            .padding(.vertical,8)
                            .liquidGlass(in: Capsule())
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        
                        Button{
                            showBulkAddFaces = true
                        } label:{
                            Image(systemName: "camera")
                                .fontWeight(.medium)
                                .padding(10)
                                .liquidGlass(in: Capsule())
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
//                    Text("Names")
//                        .font(.system(size: 32, weight: .heavy))
//                        .foregroundColor(.white)
//                        .padding(.leading)
//                    
//                    
//                    DatePicker(selection: $date, in: ...Date(), displayedComponents: .date){}
//                        .labelsHidden()
                    
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                        }) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showGroupPhotos = true
                        } label: {
                            Label("Group Photos", systemImage: "person.3.sequence")
                        }
                        Button {
                            showQuizView = true
                        } label: {
                            Label("Faces Quiz", systemImage: "questionmark.circle")
                        }
                        Button {
                            showRegexHelp = true
                        } label: {
                            Label("Instructions", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .fontWeight(.medium)
                            .liquidGlass(in: Capsule())
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



// MARK: - Extracted Views to reduce type-checking complexity

private struct GroupSectionView: View {
    let group: contactsGroup
    let onHeaderTap: () -> Void
    
    var body: some View {
        Section {
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
                onHeaderTap()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 10), count: 4), spacing: 10) {
                ForEach(group.contacts) { contact in
                    ContactTile(contact: contact)
                }
                ForEach(Array(group.parsedContacts.enumerated()), id: \.offset) { _, contact in
                    ParsedContactTile(contact: contact)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct ContactTile: View {
    let contact: Contact
    
    var body: some View {
        NavigationLink {
            ContactDetailsView(contact: contact)
        } label: {
            GeometryReader { proxy in
                let size = proxy.size
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
}

private struct ParsedContactTile: View {
    let contact: Contact
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
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
