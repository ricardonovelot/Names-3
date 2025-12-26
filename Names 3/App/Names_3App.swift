diff --git a/Names 3/ContentView.swift b/Names 3/ContentView.swift
deleted file mode 100644
index eb30987..0000000
--- a/Names 3/ContentView.swift	
+++ /dev/null
@@ -1,1297 +0,0 @@
-//
-//  ContentView.swift
-//  Names 3
-//
-//  Created by Ricardo on 14/10/24.
-//
-
-import SwiftUI
-import SwiftData
-import PhotosUI
-import Vision
-import SmoothGradient
-
-struct ContentView: View {
-    @Environment(\.modelContext) private var modelContext
-    @Environment(\.colorScheme) private var colorScheme
-    
-    @Query private var contacts: [Contact]
-    @State private var parsedContacts: [Contact] = []
-    
-    @State private var selectedItem: PhotosPickerItem?
-    
-    @State private var isAtBottom = false
-    private let dragThreshold: CGFloat = 100
-    @FocusState private var fieldIsFocused: Bool
-    
-    @State private var text = ""
-    @State private var date = Date()
-
-    @State private var showPhotosPicker = false
-    @State private var showQuizView = false
-    @State private var showRegexHelp = false
-    @State private var showReviewNotes = false
-    @State private var showBulkAddFaces = false
-    @State private var showGroupPhotos = false
-    
-    @State private var name = ""
-    @State private var hashtag = ""
-    
-    @State private var filterString = ""
-    @State private var suggestedContacts: [Contact] = []
-    
-    @State private var showGroupDatePicker = false
-    @State private var selectedGroup: contactsGroup?
-    @State private var tempGroupDate = Date()
-
-    @State private var showPhotosDayPicker = false
-    @State private var pickedImageForBatch: UIImage?
-    @State private var photosPickerDay = Date()
-    @State private var groupForDateEdit: contactsGroup?
-    @State private var isLoading = false
-
-    // Group contacts by the day of their timestamp, with a special "Met long ago" group at the top
-    var groups: [contactsGroup] {
-        let calendar = Calendar.current
-        
-        let longAgoContacts = contacts.filter { $0.isMetLongAgo }
-        let regularContacts = contacts.filter { !$0.isMetLongAgo }
-        
-        let longAgoParsed = parsedContacts.filter { $0.isMetLongAgo }
-        let regularParsed = parsedContacts.filter { !$0.isMetLongAgo }
-        
-        let groupedRegularContacts = Dictionary(grouping: regularContacts) { contact in
-            calendar.startOfDay(for: contact.timestamp)
-        }
-        let groupedRegularParsed = Dictionary(grouping: regularParsed) { parsedContact in
-            calendar.startOfDay(for: parsedContact.timestamp)
-        }
-        
-        let allDates = Set(groupedRegularContacts.keys).union(groupedRegularParsed.keys)
-        
-        var result: [contactsGroup] = []
-        
-        if !longAgoContacts.isEmpty || !longAgoParsed.isEmpty {
-            let longAgoGroup = contactsGroup(
-                date: .distantPast,
-                contacts: longAgoContacts.sorted { $0.timestamp < $1.timestamp },
-                parsedContacts: longAgoParsed.sorted { $0.timestamp < $1.timestamp },
-                isLongAgo: true
-            )
-            result.append(longAgoGroup)
-        }
-        
-        let datedGroups = allDates.map { date in
-            let sortedContacts = (groupedRegularContacts[date] ?? []).sorted { $0.timestamp < $1.timestamp }
-            let sortedParsedContacts = (groupedRegularParsed[date] ?? []).sorted { $0.timestamp < $1.timestamp }
-            return contactsGroup(
-                date: date,
-                contacts: sortedContacts,
-                parsedContacts: sortedParsedContacts,
-                isLongAgo: false
-            )
-        }
-        .sorted { $0.date < $1.date }
-        
-        result.append(contentsOf: datedGroups)
-        return result
-    }
-    
-    var dynamicBackground: Color {
-        if fieldIsFocused {
-            return colorScheme == .light ? .clear : .clear
-        } else {
-            return colorScheme == .light ? .clear : .clear
-        }
-    }
-    
-    var gridSpacing = 10.0
-    
-    var columns = [
-        GridItem(.flexible(), spacing: 10.0),
-        GridItem(.flexible(), spacing: 10.0),
-        GridItem(.flexible(), spacing: 10.0),
-        GridItem(.flexible(), spacing: 10.0)
-    ]
-    
-    var body: some View {
-        NavigationStack {
-            ScrollViewReader { proxy in
-                ScrollView(showsIndicators: false){
-                    ForEach(groups) { group in
-                        Section{
-                            VStack(alignment: .leading){
-                                HStack{
-                                    Text(group.title)
-                                        .font(.title)
-                                        .bold()
-                                    Spacer()
-                                }
-                                .padding(.leading)
-                                .padding(.trailing, 14)
-                                Text(group.subtitle)
-                                    .font(.subheadline)
-                                    .foregroundColor(.secondary)
-                                    .padding(.horizontal)
-                            }
-                            .padding(.bottom, 4)
-                            .contentShape(Rectangle())
-                                                                  .onTapGesture {
-                                                                      if !group.isLongAgo {
-                                                                          selectedGroup = group
-                                                                          tempGroupDate = group.date
-                                                                      }
-                                                                  }
-
-                            
-                            LazyVGrid(columns: Array(repeating: GridItem(spacing: 10), count: 4), spacing: 10) {
-                                ForEach(group.contacts) { contact in
-                                    NavigationLink {
-                                        ContactDetailsView(contact: contact)
-                                    } label: {
-                                        GeometryReader {
-                                            let size = $0.size
-                                            ZStack{
-                                                Image(uiImage: UIImage(data: contact.photo) ?? UIImage())
-                                                    .resizable()
-                                                    .aspectRatio(contentMode: .fill)
-                                                    .frame(width: size.width, height: size.height)
-                                                    .clipped()
-                                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
-                                                
-                                                if !contact.photo.isEmpty {
-                                                    LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.0), .black.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
-                                                }
-                                                
-                                                VStack {
-                                                    Spacer()
-                                                    Text(contact.name ?? "")
-                                                        .font(.footnote)
-                                                        .bold()
-                                                        .foregroundColor( contact.photo.isEmpty ? Color(uiColor: .label).opacity(0.8) : Color(uiColor: .white).opacity(0.8)
-                                                        )
-                                                        .padding(.bottom, 6)
-                                                        .padding(.horizontal, 6)
-                                                        .multilineTextAlignment(.center)
-                                                        .lineSpacing(-2)
-                                                }
-                                            }
-                                        }
-                                        .frame(height: 88)
-                                        .contentShape(.rect)
-                                        .clipShape(RoundedRectangle(cornerRadius: 10))
-                                        .scrollTransition { content, phase in
-                                            content
-                                                .opacity(phase.isIdentity ? 1 : 0.3)
-                                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
-                                        }
-                                    }
-                                }
-                                ForEach(Array(group.parsedContacts.enumerated()), id: \.offset) { _, contact in
-                                    GeometryReader {
-                                        let size = $0.size
-                                        ZStack{
-                                            Image(uiImage: UIImage(data: contact.photo) ?? UIImage())
-                                                .resizable()
-                                                .aspectRatio(contentMode: .fill)
-                                                .frame(width: size.width, height: size.height)
-                                                .clipped()
-                                                .background(Color(uiColor: .black).opacity(0.05))
-                                            
-                                            VStack {
-                                                Spacer()
-                                                Text(contact.name ?? "")
-                                                    .font(.footnote)
-                                                    .bold()
-                                                    .foregroundColor(UIImage(data: contact.photo) != UIImage() ? Color(uiColor: .label).opacity(0.8) : Color(uiColor: .white).opacity(0.8)
-                                                    )
-                                                    .padding(.bottom, 6)
-                                                    .padding(.horizontal, 6)
-                                                    .multilineTextAlignment(.center)
-                                                    .lineSpacing(-2)
-                                            }
-                                        }
-                                    }
-                                    
-                                    .frame(height: 88)
-                                    .contentShape(.rect)
-                                    .clipShape(RoundedRectangle(cornerRadius: 10))
-                                    
-                                }
-                                
-                                
-                            }
-                            .padding(.horizontal)
-                        }
-                    }
-                }
-                .defaultScrollAnchor(.bottom)
-                .scrollDismissesKeyboard(.interactively)
-                .onChange(of: contacts) { oldValue, newValue in
-                    proxy.scrollTo(contacts.last?.id)
-                }
-            }
-            .safeAreaInset(edge: .top){
-                ZStack(alignment: .top) {
-                    SmoothLinearGradient(
-                        from: Color(red: 0.0, green: 0.0, blue: 0.04).opacity(0.62),
-                        to: Color(red: 0.0, green: 0.0, blue: 0.04).opacity(0.0),
-                        startPoint: UnitPoint(x: 0.5, y: 0.18),
-                        endPoint: .bottom,
-                        curve: .easeInOut
-                    )
-                    .ignoresSafeArea(.all)
-                    .frame(height: 100)
-                }
-                .frame(height: 70)
-            }
-            
-            .safeAreaInset(edge: .bottom) {
-                VStack{
-                    HStack(spacing: 4){
-                        Button{
-                            showQuizView = true
-                        } label:{
-                            Image(systemName: "questionmark.circle")
-                                .foregroundStyle(.white)
-                                .font(.subheadline)
-                                .fontWeight(.medium)
-                                .padding(10)
-                                .background(
-                                    LinearGradient(
-                                        gradient: Gradient(
-                                            colors:
-                                                [.black.opacity(0.1),
-                                                 .black.opacity(0.2)
-                                                ]),
-                                        startPoint: .topLeading,
-                                        endPoint: .bottomTrailing))
-                                .background(.thickMaterial)
-                                .clipShape(Circle())
-                        }
-                        
-                        Button{
-                            showReviewNotes = true
-                        } label:{
-                            Image(systemName: "note.text")
-                                .foregroundStyle(.white)
-                                .font(.subheadline)
-                                .fontWeight(.medium)
-                                .padding(10)
-                                .background(
-                                    LinearGradient(
-                                        gradient: Gradient(
-                                            colors:
-                                                [.black.opacity(0.1),
-                                                 .black.opacity(0.2)
-                                                ]),
-                                        startPoint: .topLeading,
-                                        endPoint: .bottomTrailing))
-                                .background(.thickMaterial)
-                                .clipShape(Circle())
-                        }
-                        
-                        TextField("", text: $text, axis: .vertical)
-                            .padding(.horizontal,16)
-                            .padding(.vertical,8)
-                            .background(Color(uiColor: .secondarySystemGroupedBackground))
-                            .clipShape(RoundedRectangle(cornerRadius: 10))
-                            .onChange(of: text){ oldValue, newValue in
-                                if let last = newValue.last, last == "\n" {
-                                    text.removeLast()
-                                    saveContacts(modelContext: modelContext)
-                                } else {
-                                    parseContacts()
-                                }
-                            }
-                            .focused($fieldIsFocused)
-                            .submitLabel(.send)
-                        
-                        Button {
-                            showRegexHelp = true
-                        } label: {
-                            Image(systemName: "info.circle")
-                                .foregroundStyle(.white)
-                                .font(.subheadline)
-                                .fontWeight(.medium)
-                                .padding(10)
-                                .background(
-                                    LinearGradient(
-                                        gradient: Gradient(
-                                            colors:
-                                                [.black.opacity(0.1),
-                                                 .black.opacity(0.2)
-                                                ]),
-                                        startPoint: .topLeading,
-                                        endPoint: .bottomTrailing))
-                                .background(.thickMaterial)
-                                .clipShape(Circle())
-                        }
-
-                    }
-                    
-                    ScrollView(.horizontal){
-                        HStack{
-                            ForEach(suggestedContacts){ contact in
-                                Text(contact.name!)
-                            }
-                        }
-                    }
-                    .frame(height: 20)
-                }
-                .padding(.bottom, 8)
-                .padding(.horizontal)
-                .background(dynamicBackground)
-            }
-            .background(Color(uiColor: .systemGroupedBackground))
-            .overlay {
-                if isLoading {
-                    LoadingOverlay(message: "Loading…")
-                }
-            }
-            
-            .toolbar {
-                ToolbarItem(placement: .topBarLeading) {
-                    Text("Names")
-                        .font(.system(size: 32, weight: .heavy))
-                        .foregroundColor(.white)
-                        .padding(.leading)
-                    
-                    
-                    DatePicker(selection: $date, in: ...Date(), displayedComponents: .date){}
-                        .labelsHidden()
-                    
-                }
-                ToolbarItemGroup(placement: .navigationBarTrailing) {
-                    Menu {
-                        Button(action: {
-                        }) {
-                            Label("Export CSV", systemImage: "square.and.arrow.up")
-                        }
-                        Button {
-                            showBulkAddFaces = true
-                        } label: {
-                            Label("Bulk add faces", systemImage: "person.crop.square.badge.plus")
-                        }
-                        Button {
-                            showGroupPhotos = true
-                        } label: {
-                            Label("Group Photos", systemImage: "person.3.sequence")
-                        }
-                    } label: {
-                        Image(systemName: "ellipsis.circle")
-                            
-                    }
-                }
-            }
-            .toolbarBackground(.hidden)
-            
-            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
-            .sheet(isPresented: $showQuizView) {
-                QuizView(contacts: contacts)
-            }
-            .sheet(isPresented: $showRegexHelp) {
-                RegexShortcutsView()
-            }
-            .sheet(isPresented: $showReviewNotes) {
-                ReviewNotesView(contacts: contacts)
-            }
-            .sheet(isPresented: $showBulkAddFaces) {
-                // Contacts save in the existing CloudKit store; batches use a dedicated CloudKit store
-                BulkAddFacesView(contactsContext: modelContext)
-                    .modelContainer(BatchModelContainer.shared)
-            }
-            .sheet(isPresented: $showGroupPhotos) {
-                GroupPhotosListView(contactsContext: modelContext)
-                    .modelContainer(BatchModelContainer.shared)
-            }
-            // Group actions bottom sheet
-            .sheet(item: $selectedGroup) { group in
-                GroupActionsSheet(
-                    date: group.date,
-                    onImport: {
-                        let day = group.date
-                        selectedGroup = nil
-                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
-                            photosPickerDay = day
-                            showPhotosDayPicker = true
-                        }
-                    },
-                    onEditDate: {
-                        groupForDateEdit = group
-                        selectedGroup = nil
-                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
-                            tempGroupDate = group.date
-                            showGroupDatePicker = true
-                        }
-                    }
-                )
-                .presentationDetents([.height(220), .medium])
-                .presentationDragIndicator(.visible)
-            }
-            // Day-filtered photos picker
-            // Use a host that overlays a spinner until content is ready to render
-            .sheet(isPresented: $showPhotosDayPicker) {
-                PhotosDayPickerHost(day: photosPickerDay) { image in
-                    pickedImageForBatch = image
-                    showPhotosDayPicker = false
-                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
-                        showBulkAddFacesWithSeed(image: image, date: photosPickerDay)
-                    }
-                }
-            }
-            .sheet(isPresented: $showGroupDatePicker) {
-                NavigationStack {
-                    VStack {
-                        DatePicker("New Date", selection: $tempGroupDate, in: ...Date(), displayedComponents: .date)
-                            .datePickerStyle(GraphicalDatePickerStyle())
-                            .padding()
-                        Spacer()
-                    }
-                    .navigationTitle("Change Date")
-                    .navigationBarTitleDisplayMode(.inline)
-                    .toolbar {
-                        ToolbarItem(placement: .topBarLeading) {
-                            Button("Cancel") {
-                                showGroupDatePicker = false
-                                groupForDateEdit = nil
-                            }
-                        }
-                        ToolbarItem(placement: .topBarTrailing) {
-                            Button("Apply") {
-                                applyGroupDateChange()
-                            }
-                        }
-                    }
-                }
-            }
-        }
-        
-    }
-
-
-    private func parseContacts() {
-        let input = text
-        let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
-        var detectedDate: Date? = nil
-        var cleanedInput = input
-
-        if let matches = dateDetector?.matches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
-            for match in matches {
-                if match.resultType == .date, let date = match.date {
-                    detectedDate = adjustToPast(date)
-                    if let range = Range(match.range, in: input) {
-                        cleanedInput.removeSubrange(range)
-                    }
-                    break
-                }
-            }
-        }
-
-        let fallbackDate = Date()
-        let finalDate = detectedDate ?? fallbackDate
-
-        let nameEntries = cleanedInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
-        
-        var contacts: [Contact] = []
-        var globalTags: [Tag] = []
-        var globalTagKeys = Set<String>()
-
-        let allWords = cleanedInput.split(separator: " ").map { String($0) }
-        for word in allWords {
-            if word.starts(with: "#") {
-                let raw = String(word.dropFirst())
-                let trimmed = raw.trimmingCharacters(in: .punctuationCharacters)
-                let key = Tag.normalizedKey(trimmed)
-                if !trimmed.isEmpty && !globalTagKeys.contains(key) {
-                    if let tag = Tag.fetchOrCreate(named: trimmed, in: modelContext) {
-                        globalTags.append(tag)
-                        globalTagKeys.insert(key)
-                    }
-                }
-            }
-        }
-        
-        for entry in nameEntries {
-            if entry.starts(with: "#") {
-                continue
-            }
-
-            var nameComponents: [String] = []
-            var notes: [Note] = []
-            var summary: String? = nil
-
-            if entry.contains("::") {
-                let parts = entry.split(separator: "::", maxSplits: 1)
-                if parts.count == 2 {
-                    nameComponents = parts[0].split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
-                    summary = String(parts[1].trimmingCharacters(in: .whitespaces))
-                } else {
-                    nameComponents = parts[0].split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
-                }
-            } else {
-                nameComponents = entry.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
-            }
-            
-            var name = nameComponents.joined(separator: " ")
-            
-            if !name.isEmpty {
-                
-                filterString = name
-                filterContacts()
-
-                if let notePart = nameComponents.last, notePart.contains(":") {
-                    let nameAndNote = notePart.split(separator: ":", maxSplits: 1)
-                    if nameAndNote.count == 2 {
-                        name = nameAndNote[0].trimmingCharacters(in: .whitespaces)
-                        let noteContent = nameAndNote[1].trimmingCharacters(in: .whitespaces)
-                        if !noteContent.isEmpty {
-                            let note = Note(content: noteContent, creationDate: finalDate)
-                            notes.append(note)
-                        }
-                    } else {
-                        name = nameAndNote[0].trimmingCharacters(in: .whitespaces)
-                    }
-                }
-                
-                if name.hasSuffix(":") {
-                    name = String(name.dropLast())
-                }
-                
-                let contact = Contact(name: name, timestamp: finalDate, notes: notes, tags: globalTags, photo: Data())
-                contact.summary = summary
-                contacts.append(contact)
-            }
-        }
-        parsedContacts = contacts
-    }
-    
-    private func filterContacts() {
-        if filterString.isEmpty {
-            suggestedContacts = contacts
-        } else {
-            suggestedContacts = contacts.filter { contact in
-                if let name = contact.name {
-                    return name.starts(with: filterString)
-                }
-                return false
-            }
-        }
-    }
-
-    private func adjustToPast(_ date: Date) -> Date {
-        let today = Date()
-        let calendar = Calendar.current
-
-        if date > today {
-            let adjustedDate = calendar.date(byAdding: .year, value: -1, to: date)
-            return adjustedDate ?? date
-        }
-
-        return date
-    }
-    
-    func saveContacts(modelContext: ModelContext) {
-        isLoading = true
-        defer { isLoading = false }
-
-        for contact in parsedContacts {
-            modelContext.insert(contact)
-        }
-        
-        do {
-            try modelContext.save()
-        } catch {
-            print("Save failed: \(error)")
-        }
-        
-        text = ""
-        parsedContacts = []
-    }
-
-    private func addItem() {
-        withAnimation {
-            let newContact = Contact(timestamp: Date(), notes: [], photo: Data())
-            modelContext.insert(newContact)
-        }
-    }
-    
-    private func applyGroupDateChange() {
-        if let group = groupForDateEdit {
-            updateGroupDate(for: group, newDate: tempGroupDate)
-        }
-        showGroupDatePicker = false
-        groupForDateEdit = nil
-    }
-    
-    private func updateGroupDate(for group: contactsGroup, newDate: Date) {
-        for c in group.contacts {
-            c.isMetLongAgo = false
-            c.timestamp = combine(date: newDate, withTimeFrom: c.timestamp)
-        }
-        for c in group.parsedContacts {
-            c.isMetLongAgo = false
-            c.timestamp = combine(date: newDate, withTimeFrom: c.timestamp)
-        }
-    }
-    
-    private func combine(date: Date, withTimeFrom timeSource: Date) -> Date {
-        let cal = Calendar.current
-        let dateComps = cal.dateComponents([.year, .month, .day], from: date)
-        let timeComps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: timeSource)
-        var merged = DateComponents()
-        merged.year = dateComps.year
-        merged.month = dateComps.month
-        merged.day = dateComps.day
-        merged.hour = timeComps.hour
-        merged.minute = timeComps.minute
-        merged.second = timeComps.second
-        merged.nanosecond = timeComps.nanosecond
-        return cal.date(from: merged) ?? date
-    }
-}
-
-struct ContactFormView: View {
-    @Bindable var contact: Contact
-    
-    var body: some View {
-        Form{
-            Section{
-                TextField("Name", text: $contact.name ?? "")
-            }
-        }
-    }
-}
-
-
-struct ContactDetailsView: View {
-    @Environment(\.modelContext) private var modelContext
-    @Environment(\.dismiss) private var dismiss
-    
-    @Bindable var contact: Contact
-    
-    @State var viewState = CGSize.zero
-    
-    @State private var showPhotosPicker = false
-    
-    @State private var selectedItem: PhotosPickerItem?
-    
-    @State private var showDatePicker = false
-    @State private var showTagPicker = false
-    @State private var showCropView = false
-    @State private var isLoading = false
-    
-    @Query private var notes: [Note]
-    
-    @State private var noteText = ""
-    @State private var stateNotes : [Note] = []
-    @State private var CustomBackButtonAnimationValue = 40.0
-    
-    var image: UIImage { UIImage(data: contact.photo) ?? UIImage() }
-    
-    var body: some View {
-            GeometryReader { g in
-                ScrollView{
-                    ZStack(alignment: .bottom){
-                        if image != UIImage() {
-                            GeometryReader {
-                                let size = $0.size
-                                Image(uiImage: image)
-                                    .resizable()
-                                    .aspectRatio(contentMode: .fill)
-                                    .frame(width: size.width, height: size.height)
-                                    .overlay {
-                                        LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.2), .black.opacity(0.8)]), startPoint: .init(x: 0.5, y: 0.05), endPoint: .bottom)
-                                    }
-                            }
-                            .contentShape(.rect)
-                            .frame(height: 400)
-                            .clipped()
-                        }
-                        
-                        VStack{
-                            HStack{
-                                TextField(
-                                    "Name",
-                                    text: $contact.name ?? "",
-                                    prompt: Text("Name")
-                                        .foregroundColor(image != UIImage() ? Color(.white.opacity(0.7)) : Color(uiColor: .placeholderText) ),
-                                    axis: .vertical
-                                )
-                                .font(.system(size: 36, weight: .bold))
-                                .lineLimit(4)
-                                .foregroundColor(image != UIImage() ? .white : .primary )
-                                
-                                Image(systemName: "camera")
-                                    .font(.system(size: 18))
-                                    .padding(12)
-                                    .foregroundColor(image != UIImage() ? .blue.mix(with: .white, by: 0.3) : .blue)
-                                    .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.blue.opacity(0.08))))
-                                    .background(image != UIImage() ? .black.opacity(0.2) : .clear)
-                                    .clipShape(Circle())
-                                    .onTapGesture { showPhotosPicker = true }
-                                    .padding(.leading, 4)
-                                
-                                Group{
-                                    if !(contact.tags?.isEmpty ?? true) {
-                                        Text((contact.tags ?? []).compactMap { $0.name }.sorted().joined(separator: ", "))
-                                            .foregroundColor(image != UIImage() ? .white : Color(.secondaryLabel) )
-                                            .font(.system(size: 15, weight: .medium))
-                                            .padding(.vertical, 7)
-                                            .padding(.bottom, 1)
-                                            .padding(.horizontal, 13)
-                                            .background(image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.6)) : AnyShapeStyle(Color(.quaternarySystemFill )))
-                                            .cornerRadius(8)
-                                        
-                                    } else {
-                                        Image(systemName: "person.2")
-                                            .font(.system(size: 18))
-                                            .padding(12)
-                                            .foregroundColor(image != UIImage() ? .purple.mix(with: .white, by: 0.3) : .purple)
-                                            .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.purple.opacity(0.08))))
-                                            .clipShape(Circle())
-                                            .padding(.leading, 4)
-                                    }
-                                }
-                                .onTapGesture { showTagPicker = true }
-                            }
-                            .padding(.horizontal)
-                            
-                            TextField(
-                                "",
-                                text: $contact.summary ?? "",
-                                prompt: Text("Main Note")
-                                    .foregroundColor(image != UIImage() ? Color(uiColor: .lightText).opacity(0.8) : Color(uiColor:.placeholderText)),
-                                axis: .vertical
-                            )
-                            .lineLimit(2...)
-                            .padding(10)
-                            .foregroundStyle(image != UIImage() ? Color(uiColor: .lightText) : Color.primary)
-                            .background(
-                                BlurView(style: .regular)
-                            )
-                            .clipShape(RoundedRectangle(cornerRadius: 12))
-                            
-                            
-                            
-                            .padding(.horizontal).padding(.top, 12)
-                            .onTapGesture {
-                            }
-                            .gesture(
-                                DragGesture()
-                                    .onChanged { value in
-                                        viewState = value.translation
-                                    }
-                            )
-                            
-                            HStack{
-                                Spacer()
-                                Text(contact.timestamp, style: .date)
-                                    .foregroundColor(image != UIImage() ? .white : Color(UIColor.secondaryLabel))
-                                    .font(.system(size: 15))
-                                    .frame(alignment: .trailing)
-                                    .padding(.top, 4)
-                                    .padding(.trailing)
-                                    .padding(.trailing, 4)
-                                    .onTapGesture {
-                                        showDatePicker = true
-                                    }
-                                    .padding(.bottom)
-                                    .onAppear{
-                                    }
-                            }
-                        }
-                    }
-                    
-                    HStack{
-                        Text("Notes")
-                            .font(.body.smallCaps())
-                            .fontWeight(.light)
-                            .foregroundStyle(.secondary)
-                            .padding(.leading)
-                        Spacer()
-                    }
-                    Button(action: {
-                        let newNote = Note(content: "Test", creationDate: Date())
-                        if contact.notes == nil { contact.notes = [] }
-                        contact.notes?.append(newNote)
-                        do {
-                            try modelContext.save()
-                        } catch {
-                            print("Save failed: \(error)")
-                        }
-                    }) {
-                        HStack {
-                            Image(systemName: "plus.circle.fill")
-                            Text("Add Note")
-                            Spacer()
-                        }
-                        .padding(.horizontal).padding(.vertical, 14)
-                        .background(Color(uiColor: .tertiarySystemBackground))
-                        .clipShape(RoundedRectangle(cornerRadius: 12))
-                        .padding(.horizontal)
-                        .foregroundStyle(.blue)
-                    }
-                    .buttonStyle(PlainButtonStyle())
-                    
-                    List{
-                        let array = contact.notes ?? []
-                        ForEach(array, id: \.self) { note in
-                            Section{
-                                VStack {
-                                    TextField("Note Content", text: Binding(
-                                        get: { note.content },
-                                        set: { note.content = $0 }
-                                    ), axis: .vertical)
-                                        .lineLimit(2...)
-                                    HStack {
-                                        Spacer()
-                                        Text(note.creationDate, style: .date)
-                                            .font(.caption)
-                                    }
-                                }
-                                .swipeActions(edge: .trailing) {
-                                    Button(role: .destructive) {
-                                        modelContext.delete(note)
-                                    } label: {
-                                        Label("Delete", systemImage: "trash")
-                                    }
-                                }
-                                .swipeActions(edge: .leading) {
-                                    Button {
-                                    } label: {
-                                        Label("Edit Date", systemImage: "calendar")
-                                    }
-                                    .tint(.blue)
-                                }
-                            }
-                        }
-                    }
-                    .frame(width: g.size.width, height: g.size.height)
-                }
-                .padding(.top, image != UIImage() ? 0 : 8 )
-                .ignoresSafeArea(image != UIImage() ? .all : [])
-                .background(Color(UIColor.systemGroupedBackground))
-                .toolbar {
-                    ToolbarItem(placement: .topBarTrailing) {
-                        Menu {
-                            Button {
-                            } label: {
-                                Text("Duplicate")
-                            }
-                            Button {
-                                modelContext.delete(contact)
-                                dismiss()
-                            } label: {
-                                Text("Delete")
-                            }
-                        } label: {
-                            Image(systemName: "ellipsis.circle")
-                        }
-                    }
-                    ToolbarItem(placement: .navigationBarLeading) {
-                        Button {
-                            dismiss()
-                        } label: {
-                            HStack {
-                                HStack{
-                                    Image(systemName: image != UIImage() ? "" : "chevron.backward")
-                                    Text("Back")
-                                        .fontWeight(image != UIImage() ? .medium : .regular)
-                                }
-                                .padding(.trailing, 8)
-                            }
-                            .padding(.leading, CustomBackButtonAnimationValue)
-                            .onAppear{
-                                withAnimation {
-                                    CustomBackButtonAnimationValue = 0
-                                }
-                            }
-                        }
-                    }
-                }
-                .navigationBarBackButtonHidden(true)
-            }
-            .toolbarBackground(.hidden)
-            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
-            .sheet(isPresented: $showDatePicker) {
-                CustomDatePicker(contact: contact)
-            }
-            .sheet(isPresented: $showTagPicker) {
-                CustomTagPicker(contact: contact)
-            }
-            .fullScreenCover(isPresented: $showCropView){
-                if let image = UIImage(data: contact.photo) {
-                    CropView(
-                        image: image,
-                        initialScale: CGFloat(contact.cropScale),
-                        initialOffset: CGSize(width: CGFloat(contact.cropOffsetX), height: CGFloat(contact.cropOffsetY))
-                    ) { croppedImage, scale, offset in
-                        updateCroppingParameters(croppedImage: croppedImage, scale: scale, offset: offset)
-                    }
-                }
-            }
-            .overlay {
-                if isLoading {
-                    LoadingOverlay(message: "Processing photo…")
-                }
-            }
-            .onChange(of: selectedItem) {
-                isLoading = true
-                Task {
-                    if let loaded = try? await selectedItem?.loadTransferable(type: Data.self) {
-                        contact.photo = loaded
-                        showCropView = true
-                        do {
-                            try modelContext.save()
-                        } catch {
-                            print("Save failed: \(error)")
-                        }
-                    } else {
-                        print("Failed")
-                    }
-                    isLoading = false
-                }
-            }
-    }
-    
-    func updateCroppingParameters(croppedImage: UIImage?, scale: CGFloat, offset: CGSize) {
-        if let croppedImage = croppedImage {
-            contact.photo = croppedImage.jpegData(compressionQuality: 1.0) ?? Data()
-        }
-        contact.cropScale = Float(scale)
-        contact.cropOffsetX = Float(offset.width)
-        contact.cropOffsetY = Float(offset.height)
-        do {
-            try modelContext.save()
-        } catch {
-            print("Save failed: \(error)")
-        }
-    }
-}
-
-struct CustomDatePicker: View {
-    @Bindable var contact: Contact
-    @Environment(\.dismiss) private var dismiss
-    @Environment(\.modelContext) private var modelContext
-    
-    @State private var date = Date()
-    @State private var bool: Bool = false
-    
-    var body: some View {
-        
-        VStack{
-            GroupBox{
-                Toggle("Met long ago", isOn: $contact.isMetLongAgo)
-                    .onChange(of: contact.isMetLongAgo) { old, new in
-                        if true {
-                        } else {
-                        }
-                    }
-                    Divider()
-                    DatePicker("Exact Date", selection: $contact.timestamp,in: ...Date(),displayedComponents: .date)
-                        .datePickerStyle(GraphicalDatePickerStyle())
-                        .disabled(contact.isMetLongAgo)
-                
-            }
-            .backgroundStyle(Color(UIColor.systemBackground))
-            .padding()
-            Spacer()
-        }
-        .containerRelativeFrame([.horizontal, .vertical])
-        .background(Color(UIColor.systemGroupedBackground))
-    }
-}
-
-struct CustomTagPicker: View {
-    @Environment(\.modelContext) private var modelContext
-    @Query private var tags: [Tag]
-    @Bindable var contact: Contact
-    @Environment(\.dismiss) private var dismiss
-    @State private var searchText: String = ""
-    
-    var body: some View{
-        NavigationView{
-            List{
-                
-                if !searchText.isEmpty {
-                    Section{
-                        Button{
-                            if let tag = Tag.fetchOrCreate(named: searchText, in: modelContext) {
-                                if !(contact.tags?.contains(where: { $0.normalizedKey == tag.normalizedKey }) ?? false) {
-                                    if contact.tags == nil { contact.tags = [] }
-                                    contact.tags?.append(tag)
-                                }
-                            }
-                        } label: {
-                            Group{
-                                HStack{
-                                    Text("Add \(searchText)")
-                                    Image(systemName: "plus.circle.fill")
-                                }
-                            }
-                        }
-                    }
-                }
-                
-                Section{
-                    let uniqueTags: [Tag] = {
-                        var map: [String: Tag] = [:]
-                        for tag in tags {
-                            let key = tag.normalizedKey
-                            if map[key] == nil { map[key] = tag }
-                        }
-                        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
-                    }()
-                    
-                    ForEach(uniqueTags, id: \.self) { tag in
-                        HStack{
-                            Text(tag.name)
-                            Spacer()
-                            if contact.tags?.contains(where: { $0.normalizedKey == tag.normalizedKey }) == true {
-                                Image(systemName: "checkmark")
-                                    .foregroundColor(.accentColor)
-                            }
-                        }
-                        .contentShape(Rectangle())
-                        .onTapGesture {
-                            if let existingIndex = contact.tags?.firstIndex(where: { $0.normalizedKey == tag.normalizedKey }) {
-                                contact.tags?.remove(at: existingIndex)
-                            } else {
-                                if contact.tags == nil { contact.tags = [] }
-                                contact.tags?.append(tag)
-                            }
-                        }
-                    }
-                }
-            }
-            .navigationTitle("Groups & Places")
-            .navigationBarTitleDisplayMode(.inline)
-            .searchable(text: $searchText, placement:.navigationBarDrawer(displayMode: .always))
-            .contentMargins(.top, 8)
-        }
-    }
-}
-
-func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
-    Binding(
-        get: { lhs.wrappedValue ?? rhs },
-        set: { lhs.wrappedValue = $0 }
-    )
-}
-
-#Preview("List") {
-        ContentView().modelContainer(for: [Contact.self, Note.self, Tag.self], inMemory: true)
-}
-
-#Preview("Contact Detail") {
-    ModelContainerPreview(ModelContainer.sample) {
-        NavigationStack{
-            ContactDetailsView(contact:.ross)
-        }
-    }
-}
-
-private func downscaleJPEG(data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
-    guard let image = UIImage(data: data) else { return data }
-    let width = image.size.width
-    let height = image.size.height
-    let maxSide = max(width, height)
-    guard maxSide > maxDimension else {
-        return image.jpegData(compressionQuality: quality) ?? data
-    }
-    let scale = maxDimension / maxSide
-    let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))
-    let format = UIGraphicsImageRendererFormat.default()
-    format.scale = 1
-    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
-    let scaled = renderer.image { _ in
-        image.draw(in: CGRect(origin: .zero, size: newSize))
-    }
-    return scaled.jpegData(compressionQuality: quality) ?? data
-}
-
-struct BlurView: UIViewRepresentable {
-    let style: UIBlurEffect.Style
-    
-    init(style: UIBlurEffect.Style) {
-        self.style = style
-    }
-    
-    func makeUIView(context: Context) -> UIVisualEffectView {
-        let blurEffect = UIBlurEffect(style: style)
-        let blurView = UIVisualEffectView(effect: blurEffect)
-        return blurView
-    }
-    
-    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
-}
-
-extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
-    override open func viewDidLoad() {
-        super.viewDidLoad()
-        interactivePopGestureRecognizer?.delegate = self
-    }
-
-    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
-        return viewControllers.count > 1
-    }
-}
-
-private struct GroupActionsSheet: View {
-    let date: Date
-    let onImport: () -> Void
-    let onEditDate: () -> Void
-    @State private var isBusy = false
-
-    var body: some View {
-        NavigationStack {
-            ZStack {
-                VStack(spacing: 16) {
-                    VStack(alignment: .leading, spacing: 4) {
-                        Text(date, style: .date)
-                            .font(.title3.weight(.semibold))
-                        Text(relativeString(for: date))
-                            .font(.subheadline)
-                            .foregroundStyle(.secondary)
-                    }
-                    .frame(maxWidth: .infinity, alignment: .leading)
-
-                    Button {
-                        isBusy = true
-                        onImport()
-                    } label: {
-                        HStack {
-                            Image(systemName: "photo.on.rectangle.angled")
-                            Text("Import photos for this day")
-                                .fontWeight(.semibold)
-                            Spacer()
-                        }
-                        .padding()
-                        .background(Color(UIColor.secondarySystemGroupedBackground))
-                        .clipShape(RoundedRectangle(cornerRadius: 12))
-                    }
-                    .buttonStyle(.plain)
-
-                    Button {
-                        isBusy = true
-                        onEditDate()
-                    } label: {
-                        HStack {
-                            Image(systemName: "calendar.badge.clock")
-                            Text("Edit date")
-                            Spacer()
-                        }
-                        .padding()
-                        .background(Color(UIColor.secondarySystemGroupedBackground))
-                        .clipShape(RoundedRectangle(cornerRadius: 12))
-                    }
-                    .buttonStyle(.plain)
-
-                    Spacer(minLength: 8)
-                }
-                .padding()
-
-                if isBusy {
-                    // Non-blocking spinner overlay while the next sheet is prepared/presented
-                    VStack(spacing: 10) {
-                        ProgressView()
-                        Text("Loading…")
-                            .font(.footnote)
-                            .foregroundStyle(.secondary)
-                    }
-                    .padding(14)
-                    .background(.ultraThinMaterial)
-                    .clipShape(RoundedRectangle(cornerRadius: 12))
-                    .allowsHitTesting(false)
-                    .transition(.opacity)
-                }
-            }
-            .navigationTitle("Group")
-            .navigationBarTitleDisplayMode(.inline)
-        }
-    }
-
-    private func relativeString(for date: Date) -> String {
-        let f = RelativeDateTimeFormatter()
-        f.unitsStyle = .full
-        return f.localizedString(for: date, relativeTo: Date())
-    }
-}
-
-// Lightweight host that overlays a spinner during the initial render of PhotosDayPickerView
-private struct PhotosDayPickerHost: View {
-    let day: Date
-    let onPick: (UIImage) -> Void
-    @State private var showSpinner = true
-
-    var body: some View {
-        ZStack {
-            PhotosDayPickerView(day: day) { image in
-                onPick(image)
-            }
-
-            if showSpinner {
-                VStack(spacing: 10) {
-                    ProgressView()
-                    Text("Loading photos…")
-                        .font(.footnote)
-                        .foregroundStyle(.secondary)
-                }
-                .padding(14)
-                .background(.ultraThinMaterial)
-                .clipShape(RoundedRectangle(cornerRadius: 12))
-                .allowsHitTesting(false)
-                .transition(.opacity)
-            }
-        }
-        // Give SwiftUI one frame to build the sheet’s view hierarchy before hiding the spinner
-        .task {
-            try? await Task.sleep(nanoseconds: 300_000_000)
-            withAnimation(.easeInOut(duration: 0.2)) {
-                showSpinner = false
-            }
-        }
-    }
-}
-
-private extension ContentView {
-    func showBulkAddFacesWithSeed(image: UIImage, date: Date, completion: (() -> Void)? = nil) {
-        let root = UIHostingController(
-            rootView: BulkAddFacesView(contactsContext: modelContext, initialImage: image, initialDate: date)
-                .modelContainer(BatchModelContainer.shared)
-        )
-        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
-           let window = scene.windows.first,
-           let rootVC = window.rootViewController {
-            root.modalPresentationStyle = .formSheet
-            rootVC.present(root, animated: true) {
-                completion?()
-            }
-        } else {
-            completion?()
-        }
-    }
-}
-
-private struct LoadingOverlay: View {
-    var message: String? = nil
-    var body: some View {
-        ZStack {
-            Color.black.opacity(0.25).ignoresSafeArea()
-            VStack(spacing: 12) {
-                ProgressView()
-                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
-                if let message {
-                    Text(message)
-                        .foregroundColor(.white)
-                        .font(.footnote)
-                }
-            }
-            .padding(16)
-            .background(.ultraThinMaterial)
-            .clipShape(RoundedRectangle(cornerRadius: 12))
-        }
-        .transition(.opacity)
-    }
-}
diff --git a/Names 3/Extensions/SwiftUI/Binding+Default.swift b/Names 3/Extensions/SwiftUI/Binding+Default.swift
new file mode 100644
index 0000000..38e9d37
--- /dev/null
+++ b/Names 3/Extensions/SwiftUI/Binding+Default.swift	
@@ -0,0 +1,10 @@
+import SwiftUI
+
+infix operator ?? : NilCoalescingPrecedence
+
+func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
+    Binding(
+        get: { lhs.wrappedValue ?? rhs },
+        set: { lhs.wrappedValue = $0 }
+    )
+}
\ No newline at end of file
diff --git a/Names 3/Extensions/UIKit/UINavigationController+InteractivePop.swift b/Names 3/Extensions/UIKit/UINavigationController+InteractivePop.swift
new file mode 100644
index 0000000..d24e6e5
--- /dev/null
+++ b/Names 3/Extensions/UIKit/UINavigationController+InteractivePop.swift	
@@ -0,0 +1,12 @@
+import UIKit
+
+extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
+    override open func viewDidLoad() {
+        super.viewDidLoad()
+        interactivePopGestureRecognizer?.delegate = self
+    }
+
+    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
+        return viewControllers.count > 1
+    }
+}
\ No newline at end of file
diff --git a/Names 3/Names_3App.swift b/Names 3/Names_3App.swift
deleted file mode 100644
index f3d0fa4..0000000
--- a/Names 3/Names_3App.swift	
+++ /dev/null
@@ -1,53 +0,0 @@
-//
-//  Names_3App.swift
-//  Names 3
-//
-//  Created by Ricardo on 14/10/24.
-//
-
-import SwiftUI
-import SwiftData
-import UIKit
-
-@main
-struct Names_3App: App {
-    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
-
-    var sharedModelContainer: ModelContainer = {
-        let schema = Schema([
-            Contact.self,
-            Note.self,
-            Tag.self,
-            // FaceBatch models intentionally NOT added here to keep the Contacts store stable
-        ])
-        let modelConfiguration = ModelConfiguration(
-            "default",
-            schema: schema,
-            isStoredInMemoryOnly: false,
-            cloudKitDatabase: .private("iCloud.com.ricardo.Names4")
-        )
-
-        do {
-            return try ModelContainer(for: schema, configurations: [modelConfiguration])
-        } catch {
-            fatalError("Could not create ModelContainer: \(error)")
-        }
-    }()
-
-    var body: some Scene {
-        WindowGroup {
-            TabView {
-                ContentView()
-                    .tabItem {
-                        Label("People", systemImage: "person.3")
-                    }
-
-                NotesFeedView()
-                    .tabItem {
-                        Label("Notes", systemImage: "note.text")
-                    }
-            }
-        }
-        .modelContainer(sharedModelContainer)
-    }
-}
\ No newline at end of file
diff --git a/Names 3/QuizView.swift b/Names 3/QuizView.swift
deleted file mode 100644
index 7d9c0f5..0000000
--- a/Names 3/QuizView.swift	
+++ /dev/null
@@ -1,247 +0,0 @@
-import SwiftUI
-import SwiftData
-
-struct QuizView: View {
-    let contacts: [Contact]
-    @Environment(\.dismiss) private var dismiss
-
-    struct Question: Identifiable, Hashable {
-        let id = UUID()
-        let answer: Contact
-        let options: [Contact]
-    }
-
-    @State private var questions: [Question] = []
-    @State private var index: Int = 0
-    @State private var selection: Contact?
-    @State private var score: Int = 0
-
-    @State private var advanceTask: Task<Void, Never>?
-    private let autoAdvanceDelay: TimeInterval = 0.8
-
-    private var currentQuestion: Question? {
-        guard index >= 0 && index < questions.count else { return nil }
-        return questions[index]
-    }
-
-    private var isSelectionCorrect: Bool {
-        guard let q = currentQuestion, let selection else { return false }
-        return selection.id == q.answer.id
-    }
-
-    var body: some View {
-        NavigationStack {
-            VStack(spacing: 16) {
-                if let q = currentQuestion {
-                    ZStack {
-                        if let image = UIImage(data: q.answer.photo), image != UIImage() {
-                            Image(uiImage: image)
-                                .resizable()
-                                .scaledToFill()
-                                .frame(maxWidth: .infinity)
-                                .frame(height: 260)
-                                .clipped()
-                                .overlay {
-                                    LinearGradient(
-                                        gradient: Gradient(colors: [
-                                            .black.opacity(0.0),
-                                            .black.opacity(0.15),
-                                            .black.opacity(0.35)
-                                        ]),
-                                        startPoint: .top, endPoint: .bottom
-                                    )
-                                }
-                        } else {
-                            ZStack {
-                                Color(UIColor.secondarySystemGroupedBackground)
-                                Image(systemName: "person.crop.square")
-                                    .font(.system(size: 72, weight: .light))
-                                    .foregroundStyle(.secondary)
-                            }
-                            .frame(maxWidth: .infinity)
-                            .frame(height: 260)
-                        }
-                    }
-                    .clipShape(RoundedRectangle(cornerRadius: 14))
-                    .padding(.horizontal)
-
-                    VStack(alignment: .leading, spacing: 4) {
-                        Text("Group")
-                            .font(.caption)
-                            .foregroundStyle(.secondary)
-                        Text(groupLabel(for: q.answer))
-                            .font(.headline)
-                            .foregroundStyle(.primary)
-                            .lineLimit(2)
-                            .frame(maxWidth: .infinity, alignment: .leading)
-                    }
-                    .padding(.horizontal)
-
-                    Text("Choose the correct name")
-                        .font(.title3.weight(.semibold))
-                        .frame(maxWidth: .infinity, alignment: .leading)
-                        .padding(.horizontal)
-
-                    VStack(spacing: 10) {
-                        ForEach(q.options, id: \.id) { option in
-                            Button {
-                                guard selection == nil else { return }
-                                selection = option
-                                if option.id == q.answer.id {
-                                    score += 1
-                                }
-                                scheduleAutoAdvance(capturedIndex: index)
-                            } label: {
-                                HStack {
-                                    Text(option.name ?? "Unknown")
-                                        .font(.body.weight(.medium))
-                                        .foregroundStyle(.primary)
-                                        .lineLimit(1)
-                                    Spacer()
-                                }
-                                .padding(.vertical, 12)
-                                .padding(.horizontal, 14)
-                                .background(buttonBackground(for: option, in: q))
-                                .clipShape(RoundedRectangle(cornerRadius: 10))
-                            }
-                            .buttonStyle(.plain)
-                            .disabled(selection != nil)
-                            .accessibilityLabel(option.name ?? "Option")
-                        }
-                    }
-                    .padding(.horizontal)
-
-                    if selection != nil {
-                        Text(isSelectionCorrect ? "Correct" : "Wrong")
-                            .font(.subheadline.weight(.semibold))
-                            .foregroundStyle(isSelectionCorrect ? Color.green : Color.red)
-                            .transition(.opacity)
-                            .padding(.top, 4)
-                            .accessibilityHint(isSelectionCorrect ? "Correct answer selected" : "Incorrect answer selected")
-                    }
-
-                    HStack {
-                        Text("Score: \(score)/\(questions.count)")
-                            .font(.footnote)
-                            .foregroundStyle(.secondary)
-                        Spacer()
-                        Button("Skip") {
-                            advanceTask?.cancel()
-                            advance()
-                        }
-                        .buttonStyle(.bordered)
-                        .disabled(currentQuestion == nil)
-                        .accessibilityLabel("Skip question")
-                    }
-                    .padding(.horizontal)
-                    .padding(.top, 6)
-                } else {
-                    VStack(spacing: 12) {
-                        Text("Not enough contacts to start a quiz.")
-                            .font(.headline)
-                            .multilineTextAlignment(.center)
-                        Button("Close") { dismiss() }
-                            .buttonStyle(.borderedProminent)
-                    }
-                    .padding()
-                }
-
-                Spacer(minLength: 12)
-            }
-            .navigationTitle("Quiz")
-            .navigationBarTitleDisplayMode(.inline)
-            .toolbar {
-                ToolbarItem(placement: .topBarLeading) {
-                    Button {
-                        dismiss()
-                    } label: {
-                        Image(systemName: "xmark.circle.fill")
-                    }
-                    .accessibilityLabel("Close")
-                }
-                ToolbarItem(placement: .principal) {
-                    if questions.count > 0 {
-                        Text("Question \(min(index + 1, questions.count)) of \(questions.count)")
-                            .font(.subheadline)
-                            .foregroundStyle(.secondary)
-                    }
-                }
-            }
-            .padding(.top, 8)
-            .background(Color(UIColor.systemGroupedBackground))
-            .onAppear {
-                if questions.isEmpty {
-                    questions = buildQuestions(from: contacts)
-                }
-            }
-        }
-    }
-
-    private func scheduleAutoAdvance(capturedIndex: Int) {
-        advanceTask?.cancel()
-        advanceTask = Task { @MainActor in
-            try? await Task.sleep(nanoseconds: UInt64(autoAdvanceDelay * 1_000_000_000))
-            if !Task.isCancelled, index == capturedIndex {
-                advance()
-            }
-        }
-    }
-
-    private func groupLabel(for contact: Contact) -> String {
-        let names = (contact.tags ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
-        if names.isEmpty { return "—" }
-        return names.sorted().joined(separator: ", ")
-    }
-
-    private func advance() {
-        guard !questions.isEmpty else { dismiss(); return }
-        if index >= questions.count - 1 {
-            dismiss()
-        } else {
-            index += 1
-            selection = nil
-        }
-    }
-
-    private func buttonBackground(for option: Contact, in q: Question) -> some ShapeStyle {
-        guard let selection else {
-            return AnyShapeStyle(Color(UIColor.secondarySystemGroupedBackground))
-        }
-        if option.id == q.answer.id {
-            return AnyShapeStyle(Color.green.opacity(0.25))
-        } else if option.id == selection.id {
-            return AnyShapeStyle(Color.red.opacity(0.25))
-        } else {
-            return AnyShapeStyle(Color(UIColor.secondarySystemGroupedBackground))
-        }
-    }
-
-    private func buildQuestions(from all: [Contact]) -> [Question] {
-        let valid = all.filter { contact in
-            if let name = contact.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
-                return true
-            }
-            return false
-        }
-        guard !valid.isEmpty else { return [] }
-
-        let withPhotos = valid.filter { !$0.photo.isEmpty }
-        let answersPool = withPhotos.isEmpty ? valid.shuffled() : withPhotos.shuffled()
-
-        var qs: [Question] = []
-        for answer in answersPool {
-            let distractorPool = valid.filter { $0.id != answer.id }
-            let count = min(3, max(0, distractorPool.count))
-            let distractors = Array(distractorPool.shuffled().prefix(count))
-            var options = distractors + [answer]
-            options = Array(Set(options.map { $0.id })).compactMap { id in
-                (options.first { $0.id == id })
-            }
-            options.shuffle()
-            qs.append(Question(answer: answer, options: options))
-        }
-
-        let filtered = qs.filter { $0.options.count >= min(4, max(2, valid.count)) }
-        return filtered.isEmpty ? qs : filtered
-    }
-}
\ No newline at end of file
diff --git a/Names 3/SimpleCropView.swift b/Names 3/SimpleCropView.swift
deleted file mode 100644
index 0b985ce..0000000
--- a/Names 3/SimpleCropView.swift	
+++ /dev/null
@@ -1,146 +0,0 @@
-import SwiftUI
-import UIKit
-
-struct SimpleCropView: View {
-    let image: UIImage
-    var onComplete: (UIImage?) -> Void
-
-    @Environment(\.dismiss) private var dismiss
-    @State private var performCrop = false
-
-    var body: some View {
-        NavigationStack {
-            VStack {
-                Spacer(minLength: 0)
-                let side = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) - 40
-                CropScrollViewRepresentable(image: image, cropSize: CGSize(width: side, height: side), performCrop: $performCrop) { cropped in
-                    onComplete(cropped)
-                }
-                .frame(width: side, height: side)
-                .clipped()
-                .overlay {
-                    RoundedRectangle(cornerRadius: 10)
-                        .strokeBorder(.white.opacity(0.9), lineWidth: 1)
-                        .blendMode(.normal)
-                }
-                .padding()
-                Spacer(minLength: 0)
-            }
-            .background(Color(UIColor.systemBackground))
-            .navigationTitle("Crop")
-            .navigationBarTitleDisplayMode(.inline)
-            .toolbar {
-                ToolbarItem(placement: .topBarLeading) {
-                    Button("Cancel") {
-                        onComplete(nil)
-                    }
-                }
-                ToolbarItem(placement: .topBarTrailing) {
-                    Button("Done") {
-                        performCrop = true
-                    }
-                    .fontWeight(.semibold)
-                }
-            }
-        }
-    }
-}
-
-private struct CropScrollViewRepresentable: UIViewRepresentable {
-    let image: UIImage
-    let cropSize: CGSize
-    @Binding var performCrop: Bool
-    let onCropped: (UIImage?) -> Void
-
-    func makeCoordinator() -> Coordinator {
-        Coordinator(image: image, cropSize: cropSize, onCropped: onCropped)
-    }
-
-    func makeUIView(context: Context) -> UIScrollView {
-        let normalized = context.coordinator.normalizedImage
-        let scrollView = UIScrollView()
-        scrollView.bounces = false
-        scrollView.showsVerticalScrollIndicator = false
-        scrollView.showsHorizontalScrollIndicator = false
-        scrollView.clipsToBounds = true
-        scrollView.delegate = context.coordinator
-        scrollView.backgroundColor = .black
-
-        let imageView = UIImageView(image: normalized)
-        imageView.frame = CGRect(origin: .zero, size: normalized.size)
-        imageView.isUserInteractionEnabled = true
-        imageView.contentMode = .center
-
-        scrollView.addSubview(imageView)
-        scrollView.contentSize = normalized.size
-        context.coordinator.scrollView = scrollView
-        context.coordinator.imageView = imageView
-
-        let minZoom = max(cropSize.width / normalized.size.width, cropSize.height / normalized.size.height)
-        let maxZoom = max(minZoom * 4, 1.0)
-        scrollView.minimumZoomScale = minZoom
-        scrollView.maximumZoomScale = maxZoom
-        scrollView.zoomScale = minZoom
-
-        let offsetX = max((normalized.size.width * minZoom - cropSize.width) / 2, 0)
-        let offsetY = max((normalized.size.height * minZoom - cropSize.height) / 2, 0)
-        scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
-
-        return scrollView
-    }
-
-    func updateUIView(_ uiView: UIScrollView, context: Context) {
-        if performCrop {
-            performCrop = false
-            let cropped = context.coordinator.cropCurrentVisibleRect()
-            onCropped(cropped)
-        }
-    }
-
-    final class Coordinator: NSObject, UIScrollViewDelegate {
-        let originalImage: UIImage
-        let normalizedImage: UIImage
-        let cropSize: CGSize
-        let onCropped: (UIImage?) -> Void
-        weak var scrollView: UIScrollView?
-        weak var imageView: UIImageView?
-
-        init(image: UIImage, cropSize: CGSize, onCropped: @escaping (UIImage?) -> Void) {
-            self.originalImage = image
-            self.normalizedImage = Self.normalizeOrientation(of: image)
-            self.cropSize = cropSize
-            self.onCropped = onCropped
-        }
-
-        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
-            imageView
-        }
-
-        func cropCurrentVisibleRect() -> UIImage? {
-            guard let scrollView, let img = normalizedImage.cgImage else { return nil }
-            let scale = 1.0 / scrollView.zoomScale
-            let originX = max(scrollView.contentOffset.x * scale, 0)
-            let originY = max(scrollView.contentOffset.y * scale, 0)
-            var width = cropSize.width * scale
-            var height = cropSize.height * scale
-
-            width = min(width, CGFloat(img.width) - originX)
-            height = min(height, CGFloat(img.height) - originY)
-
-            guard width > 0, height > 0 else { return nil }
-            let rect = CGRect(x: originX, y: originY, width: width, height: height).integral
-
-            guard let cropped = img.cropping(to: rect) else { return nil }
-            return UIImage(cgImage: cropped, scale: originalImage.scale, orientation: .up)
-        }
-
-        static func normalizeOrientation(of image: UIImage) -> UIImage {
-            if image.imageOrientation == .up { return image }
-            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
-            image.draw(in: CGRect(origin: .zero, size: image.size))
-            let normalized = UIGraphicsGetImageFromCurrentImageContext()
-            UIGraphicsEndImageContext()
-            return normalized ?? image
-        }
-    }
-}
\ No newline at end of file
diff --git a/Names 3/Utilities/Image/ImageProcessing.swift b/Names 3/Utilities/Image/ImageProcessing.swift
new file mode 100644
index 0000000..554f889
--- /dev/null
+++ b/Names 3/Utilities/Image/ImageProcessing.swift	
@@ -0,0 +1,20 @@
+import UIKit
+
+func downscaleJPEG(data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
+    guard let image = UIImage(data: data) else { return data }
+    let width = image.size.width
+    let height = image.size.height
+    let maxSide = max(width, height)
+    guard maxSide > maxDimension else {
+        return image.jpegData(compressionQuality: quality) ?? data
+    }
+    let scale = maxDimension / maxSide
+    let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))
+    let format = UIGraphicsImageRendererFormat.default()
+    format.scale = 1
+    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
+    let scaled = renderer.image { _ in
+        image.draw(in: CGRect(origin: .zero, size: newSize))
+    }
+    return scaled.jpegData(compressionQuality: quality) ?? data
+}
\ No newline at end of file
diff --git a/Names 3/Views/Components/GroupActionsSheet.swift b/Names 3/Views/Components/GroupActionsSheet.swift
new file mode 100644
index 0000000..85fb3ec
--- /dev/null
+++ b/Names 3/Views/Components/GroupActionsSheet.swift	
@@ -0,0 +1,81 @@
+import SwiftUI
+
+struct GroupActionsSheet: View {
+    let date: Date
+    let onImport: () -> Void
+    let onEditDate: () -> Void
+    @State private var isBusy = false
+
+    var body: some View {
+        NavigationStack {
+            ZStack {
+                VStack(spacing: 16) {
+                    VStack(alignment: .leading, spacing: 4) {
+                        Text(date, style: .date)
+                            .font(.title3.weight(.semibold))
+                        Text(relativeString(for: date))
+                            .font(.subheadline)
+                            .foregroundStyle(.secondary)
+                    }
+                    .frame(maxWidth: .infinity, alignment: .leading)
+
+                    Button {
+                        isBusy = true
+                        onImport()
+                    } label: {
+                        HStack {
+                            Image(systemName: "photo.on.rectangle.angled")
+                            Text("Import photos for this day")
+                                .fontWeight(.semibold)
+                            Spacer()
+                        }
+                        .padding()
+                        .background(Color(UIColor.secondarySystemGroupedBackground))
+                        .clipShape(RoundedRectangle(cornerRadius: 12))
+                    }
+                    .buttonStyle(.plain)
+
+                    Button {
+                        isBusy = true
+                        onEditDate()
+                    } label: {
+                        HStack {
+                            Image(systemName: "calendar.badge.clock")
+                            Text("Edit date")
+                            Spacer()
+                        }
+                        .padding()
+                        .background(Color(UIColor.secondarySystemGroupedBackground))
+                        .clipShape(RoundedRectangle(cornerRadius: 12))
+                    }
+                    .buttonStyle(.plain)
+
+                    Spacer(minLength: 8)
+                }
+                .padding()
+
+                if isBusy {
+                    VStack(spacing: 10) {
+                        ProgressView()
+                        Text("Loading…")
+                            .font(.footnote)
+                            .foregroundStyle(.secondary)
+                    }
+                    .padding(14)
+                    .background(.ultraThinMaterial)
+                    .clipShape(RoundedRectangle(cornerRadius: 12))
+                    .allowsHitTesting(false)
+                    .transition(.opacity)
+                }
+            }
+            .navigationTitle("Group")
+            .navigationBarTitleDisplayMode(.inline)
+        }
+    }
+
+    private func relativeString(for date: Date) -> String {
+        let f = RelativeDateTimeFormatter()
+        f.unitsStyle = .full
+        return f.localizedString(for: date, relativeTo: Date())
+    }
+}
\ No newline at end of file
diff --git a/Names 3/Views/Components/LoadingOverlay.swift b/Names 3/Views/Components/LoadingOverlay.swift
new file mode 100644
index 0000000..4fe7009
--- /dev/null
+++ b/Names 3/Views/Components/LoadingOverlay.swift	
@@ -0,0 +1,23 @@
+import SwiftUI
+
+struct LoadingOverlay: View {
+    var message: String? = nil
+    var body: some View {
+        ZStack {
+            Color.black.opacity(0.25).ignoresSafeArea()
+            VStack(spacing: 12) {
+                ProgressView()
+                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
+                if let message {
+                    Text(message)
+                        .foregroundColor(.white)
+                        .font(.footnote)
+                }
+            }
+            .padding(16)
+            .background(.ultraThinMaterial)
+            .clipShape(RoundedRectangle(cornerRadius: 12))
+        }
+        .transition(.opacity)
+    }
+}
\ No newline at end of file
diff --git a/Names 3/Views/Components/UIKit/BlurView.swift b/Names 3/Views/Components/UIKit/BlurView.swift
new file mode 100644
index 0000000..6839f8e
--- /dev/null
+++ b/Names 3/Views/Components/UIKit/BlurView.swift	
@@ -0,0 +1,18 @@
+import SwiftUI
+import UIKit
+
+struct BlurView: UIViewRepresentable {
+    let style: UIBlurEffect.Style
+
+    init(style: UIBlurEffect.Style) {
+        self.style = style
+    }
+
+    func makeUIView(context: Context) -> UIVisualEffectView {
+        let blurEffect = UIBlurEffect(style: style)
+        let blurView = UIVisualEffectView(effect: blurEffect)
+        return blurView
+    }
+
+    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
+}
\ No newline at end of file
diff --git a/Names 3/Views/Contacts/ContactDetailsView.swift b/Names 3/Views/Contacts/ContactDetailsView.swift
new file mode 100644
index 0000000..dde8e2d
--- /dev/null
+++ b/Names 3/Views/Contacts/ContactDetailsView.swift	
@@ -0,0 +1,308 @@
+import SwiftUI
+import SwiftData
+import PhotosUI
+import UIKit
+
+struct ContactDetailsView: View {
+    @Environment(\.modelContext) private var modelContext
+    @Environment(\.dismiss) private var dismiss
+
+    @Bindable var contact: Contact
+
+    @State var viewState = CGSize.zero
+
+    @State private var showPhotosPicker = false
+
+    @State private var selectedItem: PhotosPickerItem?
+
+    @State private var showDatePicker = false
+    @State private var showTagPicker = false
+    @State private var showCropView = false
+    @State private var isLoading = false
+
+    @Query private var notes: [Note]
+
+    @State private var noteText = ""
+    @State private var stateNotes : [Note] = []
+    @State private var CustomBackButtonAnimationValue = 40.0
+
+    var image: UIImage { UIImage(data: contact.photo) ?? UIImage() }
+
+    var body: some View {
+        GeometryReader { g in
+            ScrollView{
+                ZStack(alignment: .bottom){
+                    if image != UIImage() {
+                        GeometryReader {
+                            let size = $0.size
+                            Image(uiImage: image)
+                                .resizable()
+                                .aspectRatio(contentMode: .fill)
+                                .frame(width: size.width, height: size.height)
+                                .overlay {
+                                    LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.2), .black.opacity(0.8)]), startPoint: .init(x: 0.5, y: 0.05), endPoint: .bottom)
+                                }
+                        }
+                        .contentShape(.rect)
+                        .frame(height: 400)
+                        .clipped()
+                    }
+
+                    VStack{
+                        HStack{
+                            TextField(
+                                "Name",
+                                text: $contact.name ?? "",
+                                prompt: Text("Name")
+                                    .foregroundColor(image != UIImage() ? Color(.white.opacity(0.7)) : Color(uiColor: .placeholderText) ),
+                                axis: .vertical
+                            )
+                            .font(.system(size: 36, weight: .bold))
+                            .lineLimit(4)
+                            .foregroundColor(image != UIImage() ? .white : .primary )
+
+                            Image(systemName: "camera")
+                                .font(.system(size: 18))
+                                .padding(12)
+                                .foregroundColor(image != UIImage() ? .blue.mix(with: .white, by: 0.3) : .blue)
+                                .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.blue.opacity(0.08))))
+                                .background(image != UIImage() ? .black.opacity(0.2) : .clear)
+                                .clipShape(Circle())
+                                .onTapGesture { showPhotosPicker = true }
+                                .padding(.leading, 4)
+
+                            Group{
+                                if !(contact.tags?.isEmpty ?? true) {
+                                    Text((contact.tags ?? []).compactMap { $0.name }.sorted().joined(separator: ", "))
+                                        .foregroundColor(image != UIImage() ? .white : Color(.secondaryLabel) )
+                                        .font(.system(size: 15, weight: .medium))
+                                        .padding(.vertical, 7)
+                                        .padding(.bottom, 1)
+                                        .padding(.horizontal, 13)
+                                        .background(image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.6)) : AnyShapeStyle(Color(.quaternarySystemFill )))
+                                        .cornerRadius(8)
+
+                                } else {
+                                    Image(systemName: "person.2")
+                                        .font(.system(size: 18))
+                                        .padding(12)
+                                        .foregroundColor(image != UIImage() ? .purple.mix(with: .white, by: 0.3) : .purple)
+                                        .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.purple.opacity(0.08))))
+                                        .clipShape(Circle())
+                                        .padding(.leading, 4)
+                                }
+                            }
+                            .onTapGesture { showTagPicker = true }
+                        }
+                        .padding(.horizontal)
+
+                        TextField(
+                            "",
+                            text: $contact.summary ?? "",
+                            prompt: Text("Main Note")
+                                .foregroundColor(image != UIImage() ? Color(uiColor: .lightText).opacity(0.8) : Color(uiColor:.placeholderText)),
+                            axis: .vertical
+                        )
+                        .lineLimit(2...)
+                        .padding(10)
+                        .foregroundStyle(image != UIImage() ? Color(uiColor: .lightText) : Color.primary)
+                        .background(
+                            BlurView(style: .regular)
+                        )
+                        .clipShape(RoundedRectangle(cornerRadius: 12))
+
+                        .padding(.horizontal).padding(.top, 12)
+                        .onTapGesture {
+                        }
+                        .gesture(
+                            DragGesture()
+                                .onChanged { value in
+                                    viewState = value.translation
+                                }
+                        )
+
+                        HStack{
+                            Spacer()
+                            Text(contact.timestamp, style: .date)
+                                .foregroundColor(image != UIImage() ? .white : Color(UIColor.secondaryLabel))
+                                .font(.system(size: 15))
+                                .frame(alignment: .trailing)
+                                .padding(.top, 4)
+                                .padding(.trailing)
+                                .padding(.trailing, 4)
+                                .onTapGesture {
+                                    showDatePicker = true
+                                }
+                                .padding(.bottom)
+                                .onAppear{
+                                }
+                        }
+                    }
+                }
+
+                HStack{
+                    Text("Notes")
+                        .font(.body.smallCaps())
+                        .fontWeight(.light)
+                        .foregroundStyle(.secondary)
+                        .padding(.leading)
+                    Spacer()
+                }
+                Button(action: {
+                    let newNote = Note(content: "Test", creationDate: Date())
+                    if contact.notes == nil { contact.notes = [] }
+                    contact.notes?.append(newNote)
+                    do {
+                        try modelContext.save()
+                    } catch {
+                        print("Save failed: \(error)")
+                    }
+                }) {
+                    HStack {
+                        Image(systemName: "plus.circle.fill")
+                        Text("Add Note")
+                        Spacer()
+                    }
+                    .padding(.horizontal).padding(.vertical, 14)
+                    .background(Color(uiColor: .tertiarySystemBackground))
+                    .clipShape(RoundedRectangle(cornerRadius: 12))
+                    .padding(.horizontal)
+                    .foregroundStyle(.blue)
+                }
+                .buttonStyle(PlainButtonStyle())
+
+                List{
+                    let array = contact.notes ?? []
+                    ForEach(array, id: \.self) { note in
+                        Section{
+                            VStack {
+                                TextField("Note Content", text: Binding(
+                                    get: { note.content },
+                                    set: { note.content = $0 }
+                                ), axis: .vertical)
+                                    .lineLimit(2...)
+                                HStack {
+                                    Spacer()
+                                    Text(note.creationDate, style: .date)
+                                        .font(.caption)
+                                }
+                            }
+                            .swipeActions(edge: .trailing) {
+                                Button(role: .destructive) {
+                                    modelContext.delete(note)
+                                } label: {
+                                    Label("Delete", systemImage: "trash")
+                                }
+                            }
+                            .swipeActions(edge: .leading) {
+                                Button {
+                                } label: {
+                                    Label("Edit Date", systemImage: "calendar")
+                                }
+                                .tint(.blue)
+                            }
+                        }
+                    }
+                }
+                .frame(width: g.size.width, height: g.size.height)
+            }
+            .padding(.top, image != UIImage() ? 0 : 8 )
+            .ignoresSafeArea(image != UIImage() ? .all : [])
+            .background(Color(UIColor.systemGroupedBackground))
+            .toolbar {
+                ToolbarItem(placement: .topBarTrailing) {
+                    Menu {
+                        Button {
+                        } label: {
+                            Text("Duplicate")
+                        }
+                        Button {
+                            modelContext.delete(contact)
+                            dismiss()
+                        } label: {
+                            Text("Delete")
+                        }
+                    } label: {
+                        Image(systemName: "ellipsis.circle")
+                    }
+                }
+                ToolbarItem(placement: .navigationBarLeading) {
+                    Button {
+                        dismiss()
+                    } label: {
+                        HStack {
+                            HStack{
+                                Image(systemName: image != UIImage() ? "" : "chevron.backward")
+                                Text("Back")
+                                    .fontWeight(image != UIImage() ? .medium : .regular)
+                            }
+                            .padding(.trailing, 8)
+                        }
+                        .padding(.leading, CustomBackButtonAnimationValue)
+                        .onAppear{
+                            withAnimation {
+                                CustomBackButtonAnimationValue = 0
+                            }
+                        }
+                    }
+                }
+            }
+            .navigationBarBackButtonHidden(true)
+        }
+        .toolbarBackground(.hidden)
+        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
+        .sheet(isPresented: $showDatePicker) {
+            CustomDatePicker(contact: contact)
+        }
+        .sheet(isPresented: $showTagPicker) {
+            CustomTagPicker(contact: contact)
+        }
+        .fullScreenCover(isPresented: $showCropView){
+            if let image = UIImage(data: contact.photo) {
+                CropView(
+                    image: image,
+                    initialScale: CGFloat(contact.cropScale),
+                    initialOffset: CGSize(width: CGFloat(contact.cropOffsetX), height: CGFloat(contact.cropOffsetY))
+                ) { croppedImage, scale, offset in
+                    updateCroppingParameters(croppedImage: croppedImage, scale: scale, offset: offset)
+                }
+            }
+        }
+        .overlay {
+            if isLoading {
+                LoadingOverlay(message: "Processing photo…")
+            }
+        }
+        .onChange(of: selectedItem) {
+            isLoading = true
+            Task {
+                if let loaded = try? await selectedItem?.loadTransferable(type: Data.self) {
+                    contact.photo = loaded
+                    showCropView = true
+                    do {
+                        try modelContext.save()
+                    } catch {
+                        print("Save failed: \(error)")
+                    }
+                } else {
+                    print("Failed")
+                }
+                isLoading = false
+            }
+        }
+    }
+
+    func updateCroppingParameters(croppedImage: UIImage?, scale: CGFloat, offset: CGSize) {
+        if let croppedImage = croppedImage {
+            contact.photo = croppedImage.jpegData(compressionQuality: 1.0) ?? Data()
+        }
+        contact.cropScale = Float(scale)
+        contact.cropOffsetX = Float(offset.width)
+        contact.cropOffsetY = Float(offset.height)
+        do {
+            try modelContext.save()
+        } catch {
+            print("Save failed: \(error)")
+        }
+    }
+}
\ No newline at end of file
diff --git a/Names 3/Views/Contacts/ContactFormView.swift b/Names 3/Views/Contacts/ContactFormView.swift
new file mode 100644
index 0000000..fe5ea62
--- /dev/null
+++ b/Names 3/Views/Contacts/ContactFormView.swift	
@@ -0,0 +1,14 @@
+import SwiftUI
+import SwiftData
+
+struct ContactFormView: View {
+    @Bindable var contact: Contact
+
+    var body: some View {
+        Form {
+            Section {
+                TextField("Name", text: $contact.name ?? "")
+            }
+        }
+    }
+}
\ No newline at end of file
diff --git a/Names 3/Views/Contacts/CustomDatePicker.swift b/Names 3/Views/Contacts/CustomDatePicker.swift
new file mode 100644
index 0000000..bb16e89
--- /dev/null
+++ b/Names 3/Views/Contacts/CustomDatePicker.swift	
@@ -0,0 +1,31 @@
+import SwiftUI
+import SwiftData
+
+struct CustomDatePicker: View {
+    @Bindable var contact: Contact
+    @Environment(\.dismiss) private var dismiss
+    @Environment(\.modelContext) private var modelContext
+
+    @State private var date = Date()
+    @State private var bool: Bool = false
+
+    var body: some View {
+        VStack{
+            GroupBox{
+                Toggle("Met long ago", isOn: $contact.isMetLongAgo)
+                    .onChange(of: contact.isMetLongAgo) { _ in
+                    }
+                Divider()
+                DatePicker("Exact Date", selection: $contact.timestamp,in: ...Date(),displayedComponents: .date)
+                    .datePickerStyle(GraphicalDatePickerStyle())
+                    .disabled(contact.isMetLongAgo)
+
+            }
+            .backgroundStyle(Color(UIColor.systemBackground))
+            .padding()
+            Spacer()
+        }
+        .containerRelativeFrame([.horizontal, .vertical])
+        .background(Color(UIColor.systemGroupedBackground))
+    }
+}
\ No newline at end of file
diff --git a/Names 3/Views/Contacts/CustomTagPicker.swift b/Names 3/Views/Contacts/CustomTagPicker.swift
new file mode 100644
index 0000000..3917a3e
--- /dev/null
+++ b/Names 3/Views/Contacts/CustomTagPicker.swift	
@@ -0,0 +1,72 @@
+import SwiftUI
+import SwiftData
+
+struct CustomTagPicker: View {
+    @Environment(\.modelContext) private var modelContext
+    @Query private var tags: [Tag]
+    @Bindable var contact: Contact
+    @Environment(\.dismiss) private var dismiss
+    @State private var searchText: String = ""
+
+    var body: some View{
+        NavigationView{
+            List{
+
+                if !searchText.isEmpty {
+                    Section{
+                        Button{
+                            if let tag = Tag.fetchOrCreate(named: searchText, in: modelContext) {
+                                if !(contact.tags?.contains(where: { $0.normalizedKey == tag.normalizedKey }) ?? false) {
+                                    if contact.tags == nil { contact.tags = [] }
+                                    contact.tags?.append(tag)
+                                }
+                            }
+                        } label: {
+                            Group{
+                                HStack{
+                                    Text("Add \(searchText)")
+                                    Image(systemName: "plus.circle.fill")
+                                }
+                            }
+                        }
+                    }
+                }
+
+                Section{
+                    let uniqueTags: [Tag] = {
+                        var map: [String: Tag] = [:]
+                        for tag in tags {
+                            let key = tag.normalizedKey
+                            if map[key] == nil { map[key] = tag }
+                        }
+                        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
+                    }()
+
+                    ForEach(uniqueTags, id: \.self) { tag in
+                        HStack{
+                            Text(tag.name)
+                            Spacer()
+                            if contact.tags?.contains(where: { $0.normalizedKey == tag.normalizedKey }) == true {
+                                Image(systemName: "checkmark")
+                                    .foregroundColor(.accentColor)
+                            }
+                        }
+                        .contentShape(Rectangle())
+                        .onTapGesture {
+                            if let existingIndex = contact.tags?.firstIndex(where: { $0.normalizedKey == tag.normalizedKey }) {
+                                contact.tags?.remove(at: existingIndex)
+                            } else {
+                                if contact.tags == nil { contact.tags = [] }
+                                contact.tags?.append(tag)
+                            }
+                        }
+                    }
+                }
+            }
+            .navigationTitle("Groups & Places")
+            .navigationBarTitleDisplayMode(.inline)
+            .searchable(text: $searchText, placement:.navigationBarDrawer(displayMode: .always))
+            .contentMargins(.top, 8)
+        }
+    }
+}
\ No newline at end of file
diff --git a/Names 3/Views/Photos/PhotosDayPickerHost.swift b/Names 3/Views/Photos/PhotosDayPickerHost.swift
new file mode 100644
index 0000000..4a383a8
--- /dev/null
+++ b/Names 3/Views/Photos/PhotosDayPickerHost.swift	
@@ -0,0 +1,35 @@
+import SwiftUI
+
+struct PhotosDayPickerHost: View {
+    let day: Date
+    let onPick: (UIImage) -> Void
+    @State private var showSpinner = true
+
+    var body: some View {
+        ZStack {
+            PhotosDayPickerView(day: day) { image in
+                onPick(image)
+            }
+
+            if showSpinner {
+                VStack(spacing: 10) {
+                    ProgressView()
+                    Text("Loading photos…")
+                        .font(.footnote)
+                        .foregroundStyle(.secondary)
+                }
+                .padding(14)
+                .background(.ultraThinMaterial)
+                .clipShape(RoundedRectangle(cornerRadius: 12))
+                .allowsHitTesting(false)
+                .transition(.opacity)
+            }
+        }
+        .task {
+            try? await Task.sleep(nanoseconds: 300_000_000)
+            withAnimation(.easeInOut(duration: 0.2)) {
+                showSpinner = false
+            }
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/AppSettings.swift b/Video Feed Test/AppSettings.swift
new file mode 100644
index 0000000..030b62b
--- /dev/null
+++ b/Video Feed Test/AppSettings.swift	
@@ -0,0 +1,18 @@
+import Foundation
+import Combine
+
+@MainActor
+final class AppSettings: ObservableObject {
+    @Published var showDownloadOverlay: Bool {
+        didSet { UserDefaults.standard.set(showDownloadOverlay, forKey: Self.kShowOverlay) }
+    }
+    
+    private static let kShowOverlay = "settings.showDownloadOverlay"
+    
+    init() {
+        if UserDefaults.standard.object(forKey: Self.kShowOverlay) == nil {
+            UserDefaults.standard.set(true, forKey: Self.kShowOverlay)
+        }
+        self.showDownloadOverlay = UserDefaults.standard.bool(forKey: Self.kShowOverlay)
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/AppleMusicAuth.swift b/Video Feed Test/AppleMusicAuth.swift
new file mode 100644
index 0000000..ae19654
--- /dev/null
+++ b/Video Feed Test/AppleMusicAuth.swift	
@@ -0,0 +1,82 @@
+import Foundation
+import StoreKit
+import Combine
+
+@MainActor
+final class AppleMusicAuth: ObservableObject {
+    @Published private(set) var authStatus: SKCloudServiceAuthorizationStatus = SKCloudServiceController.authorizationStatus()
+    @Published private(set) var capabilities: SKCloudServiceCapability = []
+    @Published private(set) var userToken: String?
+    @Published private(set) var lastError: String?
+
+    private let keychain = KeychainStore(service: "VideoFeedTest.AppleMusic")
+    private let userTokenKey = "appleMusic.userToken"
+
+    init() {
+        if let data = try? keychain.getData(key: userTokenKey), let token = String(data: data, encoding: .utf8) {
+            self.userToken = token
+        }
+        Task { await refreshCapabilities() }
+    }
+
+    var isAuthorized: Bool { authStatus == .authorized }
+    var hasCatalogPlayback: Bool { capabilities.contains(.musicCatalogPlayback) }
+    var canAddToCloudLibrary: Bool { capabilities.contains(.addToCloudMusicLibrary) }
+
+    func requestAuthorization() async {
+        if #available(iOS 15.0, *) {
+            let status = await SKCloudServiceController.requestAuthorization()
+            authStatus = status
+            if status == .authorized {
+                await refreshCapabilities()
+            }
+        } else {
+            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
+                SKCloudServiceController.requestAuthorization { [weak self] status in
+                    Task { @MainActor in
+                        self?.authStatus = status
+                        if status == .authorized {
+                            Task { await self?.refreshCapabilities() }
+                        }
+                        cont.resume()
+                    }
+                }
+            }
+        }
+    }
+
+    func refreshCapabilities() async {
+        let controller = SKCloudServiceController()
+        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
+            controller.requestCapabilities { [weak self] caps, error in
+                Task { @MainActor in
+                    self?.capabilities = caps
+                    self?.lastError = error?.localizedDescription
+                    cont.resume()
+                }
+            }
+        }
+    }
+
+    func requestUserTokenIfPossible() async {
+        guard let devToken = Bundle.main.object(forInfoDictionaryKey: "APPLE_MUSIC_DEVELOPER_TOKEN") as? String, !devToken.isEmpty else {
+            lastError = "Missing APPLE_MUSIC_DEVELOPER_TOKEN in Info.plist."
+            return
+        }
+        let controller = SKCloudServiceController()
+        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
+            controller.requestUserToken(forDeveloperToken: devToken) { [weak self] token, error in
+                Task { @MainActor in
+                    if let token {
+                        self?.userToken = token
+                        try? self?.keychain.setData(Data(token.utf8), key: self?.userTokenKey ?? "appleMusic.userToken")
+                        self?.lastError = nil
+                    } else {
+                        self?.lastError = error?.localizedDescription ?? "Failed to get Apple Music user token."
+                    }
+                    cont.resume()
+                }
+            }
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/AppleMusicCatalog.swift b/Video Feed Test/AppleMusicCatalog.swift
new file mode 100644
index 0000000..95ba116
--- /dev/null
+++ b/Video Feed Test/AppleMusicCatalog.swift	
@@ -0,0 +1,179 @@
+import Foundation
+import MediaPlayer
+
+struct AppleCatalogSong: Sendable, Hashable {
+    let storeID: String
+    let title: String
+    let artist: String
+    let duration: TimeInterval?
+    let artworkURL: URL?
+    let storefront: String
+}
+
+actor AppleMusicCatalog {
+    static let shared = AppleMusicCatalog()
+
+
+    nonisolated static var isConfigured: Bool {
+        if let t = Bundle.main.object(forInfoDictionaryKey: "APPLE_MUSIC_DEVELOPER_TOKEN") as? String, !t.isEmpty {
+            return true
+        }
+        return false
+    }
+
+    nonisolated static func currentDeveloperToken() -> String? {
+        Bundle.main.object(forInfoDictionaryKey: "APPLE_MUSIC_DEVELOPER_TOKEN") as? String
+    }
+
+    func match(tracks: [YouTubeTrack], limit: Int = 3) async throws -> [AppleCatalogSong] {
+        guard let token = Self.currentDeveloperToken(), !token.isEmpty else {
+            throw NSError(domain: "AppleMusicCatalog", code: -1, userInfo: [NSLocalizedDescriptionKey: "Developer token missing"])
+        }
+        let storefront = Self.inferStorefront() ?? "us"
+        var scored: [(AppleCatalogSong, Double)] = []
+
+        for t in tracks {
+            let candidates = try await searchSongs(token: token, storefront: storefront, title: t.title, artist: t.artist, limit: 5)
+            let best = Self.pickBestCandidate(youtube: t, candidates: candidates)
+            if let best {
+                scored.append(best)
+            }
+        }
+
+        let sorted = scored.sorted(by: { $0.1 > $1.1 }).map { $0.0 }
+        var uniq: [AppleCatalogSong] = []
+        var seen = Set<String>()
+        for s in sorted {
+            if !seen.contains(s.storeID) {
+                uniq.append(s)
+                seen.insert(s.storeID)
+            }
+            if uniq.count >= limit { break }
+        }
+        return uniq
+    }
+
+    private func searchSongs(token: String, storefront: String, title: String, artist: String, limit: Int) async throws -> [AppleCatalogSong] {
+        var comps = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(storefront)/search")!
+        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
+        comps.queryItems = [
+            .init(name: "term", value: term),
+            .init(name: "types", value: "songs"),
+            .init(name: "limit", value: String(limit))
+        ]
+
+        var req = URLRequest(url: comps.url!)
+        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
+        req.setValue("application/json", forHTTPHeaderField: "Accept")
+
+        let (data, resp) = try await URLSession.shared.data(for: req)
+        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
+        guard (200..<300).contains(status) else {
+            throw NSError(domain: "AppleMusicCatalog", code: status, userInfo: [NSLocalizedDescriptionKey: "Search failed \(status)"])
+        }
+
+        struct SearchResponse: Decodable {
+            struct Results: Decodable {
+                struct Songs: Decodable {
+                    struct DataItem: Decodable {
+                        struct Attributes: Decodable {
+                            let name: String
+                            let artistName: String
+                            let durationInMillis: Double?
+                            struct Artwork: Decodable { let url: String?; let width: Int?; let height: Int? }
+                            let artwork: Artwork?
+                        }
+                        let id: String
+                        let attributes: Attributes
+                    }
+                    let data: [DataItem]
+                }
+                let songs: Songs?
+            }
+            let results: Results?
+        }
+
+        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
+        let items = decoded.results?.songs?.data ?? []
+        return items.map { item in
+            let dur = item.attributes.durationInMillis.map { $0 / 1000.0 }
+            let urlTemplate = item.attributes.artwork?.url
+            let artURL = urlTemplate.flatMap { URL(string: $0.replacingOccurrences(of: "{w}", with: "200").replacingOccurrences(of: "{h}", with: "200")) }
+            return AppleCatalogSong(
+                storeID: item.id,
+                title: item.attributes.name,
+                artist: item.attributes.artistName,
+                duration: dur,
+                artworkURL: artURL,
+                storefront: storefront
+            )
+        }
+    }
+
+    private static func pickBestCandidate(youtube: YouTubeTrack, candidates: [AppleCatalogSong]) -> (AppleCatalogSong, Double)? {
+        let ytTitle = normalize(youtube.title)
+        let ytArtist = normalize(youtube.artist)
+        let ytTitleWords = words(from: ytTitle)
+        let ytArtistWords = words(from: ytArtist)
+
+        var best: AppleCatalogSong?
+        var bestScore: Double = 0
+
+        for c in candidates {
+            let cTitle = normalize(c.title)
+            let cArtist = normalize(c.artist)
+            let titleScore = jaccard(ytTitleWords, words(from: cTitle))
+            let artistScore = jaccard(ytArtistWords, words(from: cArtist))
+            var score = 0.7 * titleScore + 0.3 * artistScore
+
+            if let ytDur = youtube.duration, let cDur = c.duration, ytDur > 1, cDur > 1 {
+                let delta = abs(ytDur - cDur)
+                if delta <= 3 { score += 0.2 }
+                else if delta <= 8 { score += 0.1 }
+                else if delta > 20 { score -= 0.2 }
+            }
+
+            if score > bestScore {
+                bestScore = score
+                best = c
+            }
+        }
+
+        if let best, bestScore >= 0.45 {
+            return (best, bestScore)
+        }
+        return nil
+    }
+
+    // Text utilities (mirrors SongMatcher)
+    private static func normalize(_ s: String) -> String {
+        var out = s.lowercased()
+        let removals = ["(official video)", "(official audio)", "(lyrics)", "[official video]", "[official audio]", "[lyrics]"]
+        removals.forEach { out = out.replacingOccurrences(of: $0, with: "") }
+        out = out.replacingOccurrences(of: "’", with: "'")
+        out = out.replacingOccurrences(of: "“", with: "\"")
+        out = out.replacingOccurrences(of: "”", with: "\"")
+        out = out.replacingOccurrences(of: "&", with: "and")
+        out = out.replacingOccurrences(of: "-", with: " ")
+        out = out.replacingOccurrences(of: "_", with: " ")
+        return out.trimmingCharacters(in: .whitespacesAndNewlines)
+    }
+
+    private static func words(from s: String) -> Set<String> {
+        Set(s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 })
+    }
+
+    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
+        if a.isEmpty || b.isEmpty { return 0 }
+        let inter = a.intersection(b).count
+        let uni = a.union(b).count
+        return Double(inter) / Double(uni)
+    }
+
+    private static func inferStorefront() -> String? {
+        if let region = Locale.current.regionCode?.lowercased() {
+            return region
+        }
+        return nil
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/AppleMusicController.swift b/Video Feed Test/AppleMusicController.swift
new file mode 100644
index 0000000..9ca25c8
--- /dev/null
+++ b/Video Feed Test/AppleMusicController.swift	
@@ -0,0 +1,142 @@
+import Foundation
+import MediaPlayer
+
+final class AppleMusicController {
+    static let shared = AppleMusicController()
+
+    private let player = MPMusicPlayerController.applicationMusicPlayer
+    private let systemPlayer = MPMusicPlayerController.systemMusicPlayer
+    private(set) var hasActiveManagedPlayback = false
+    private var didPrewarm = false
+
+    private enum ManagedController {
+        case none
+        case application
+        case system
+    }
+
+    private var managedController: ManagedController = .none
+
+    private init() {}
+
+    func prewarm() {
+        guard !didPrewarm else { return }
+        didPrewarm = true
+        DispatchQueue.global(qos: .utility).async { [player] in
+            _ = player.playbackState
+            player.beginGeneratingPlaybackNotifications()
+            player.prepareToPlay()
+        }
+    }
+
+    func play(item: MPMediaItem) {
+        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
+            guard let self else { return }
+            Diagnostics.log("AM.play(item) title=\(item.title ?? "nil") artist=\(item.artist ?? "nil")")
+            self.player.setQueue(with: MPMediaItemCollection(items: [item]))
+            self.player.prepareToPlay()
+            self.player.play()
+        }
+        managedController = .application
+        hasActiveManagedPlayback = true
+    }
+
+    func play(storeID: String) {
+        Diagnostics.log("AM.play(storeID) id=\(storeID)")
+        let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: [storeID])
+        systemPlayer.setQueue(with: descriptor)
+        systemPlayer.play()
+        managedController = .system
+        hasActiveManagedPlayback = true
+    }
+
+    func play(reference: SongReference) {
+        switch reference.service {
+        case .appleMusic:
+            if let id = reference.appleMusicStoreID, !id.isEmpty {
+                play(storeID: id)
+            } else {
+                Diagnostics.log("AM.play(reference) appleMusic missing storeID; ignoring")
+            }
+        case .spotify, .youtubeMusic:
+            Diagnostics.log("AM.play(reference) unsupported service=\(String(describing: reference.service))")
+        }
+    }
+
+    func pauseIfManaged() {
+        guard hasActiveManagedPlayback else { return }
+        switch managedController {
+        case .application:
+            Diagnostics.log("AM.pauseIfManaged -> application")
+            player.pause()
+        case .system:
+            Diagnostics.log("AM.pauseIfManaged -> system")
+            systemPlayer.pause()
+        case .none:
+            break
+        }
+    }
+
+    func resumeIfManaged() {
+        guard hasActiveManagedPlayback else { return }
+        switch managedController {
+        case .application:
+            Diagnostics.log("AM.resumeIfManaged -> application")
+            player.play()
+        case .system:
+            Diagnostics.log("AM.resumeIfManaged -> system")
+            systemPlayer.play()
+        case .none:
+            break
+        }
+    }
+
+    func skipToNext() {
+        guard hasActiveManagedPlayback else { return }
+        switch managedController {
+        case .application:
+            Diagnostics.log("AM.skipToNext -> application")
+            player.skipToNextItem()
+            player.play()
+        case .system:
+            Diagnostics.log("AM.skipToNext -> system")
+            systemPlayer.skipToNextItem()
+            systemPlayer.play()
+        case .none:
+            break
+        }
+    }
+
+    func skipToPrevious() {
+        guard hasActiveManagedPlayback else { return }
+        switch managedController {
+        case .application:
+            Diagnostics.log("AM.skipToPrevious -> application")
+            player.skipToPreviousItem()
+            player.play()
+        case .system:
+            Diagnostics.log("AM.skipToPrevious -> system")
+            systemPlayer.skipToPreviousItem()
+            systemPlayer.play()
+        case .none:
+            break
+        }
+    }
+
+    func stopManaging() {
+        Diagnostics.log("AM.stopManaging")
+        hasActiveManagedPlayback = false
+        managedController = .none
+    }
+
+    func managedNowPlayingStoreID() -> String? {
+        switch managedController {
+        case .application:
+            return player.nowPlayingItem?.playbackStoreID
+        case .system:
+            return systemPlayer.nowPlayingItem?.playbackStoreID
+        case .none:
+            return nil
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/AppleMusicManager.swift b/Video Feed Test/AppleMusicManager.swift
new file mode 100644
index 0000000..9a60dff
--- /dev/null
+++ b/Video Feed Test/AppleMusicManager.swift	
@@ -0,0 +1,51 @@
+import Foundation
+import MediaPlayer
+import Combine
+
+@MainActor
+final class AppleMusicManager: ObservableObject {
+    @Published private(set) var authorization: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
+    @Published private(set) var recentItems: [MPMediaItem] = []
+
+    init() {
+        if authorization == .authorized {
+            loadRecent()
+        }
+    }
+
+    func refreshAuthorization() {
+        authorization = MPMediaLibrary.authorizationStatus()
+    }
+
+    func requestAuthorization() {
+        MPMediaLibrary.requestAuthorization { [weak self] status in
+            DispatchQueue.main.async {
+                self?.authorization = status
+                if status == .authorized {
+                    self?.loadRecent()
+                }
+            }
+        }
+    }
+
+    func loadRecent(limit: Int = 3) {
+        let query = MPMediaQuery.songs()
+        guard let items = query.items, !items.isEmpty else {
+            recentItems = []
+            return
+        }
+        let sorted = items.sorted { lhs, rhs in
+            let l = lhs.dateAdded
+            let r = rhs.dateAdded
+            return l > r
+        }
+        recentItems = Array(sorted.prefix(limit))
+    }
+
+    func play(item: MPMediaItem) {
+        let player = MPMusicPlayerController.systemMusicPlayer
+        let collection = MPMediaItemCollection(items: [item])
+        player.setQueue(with: collection)
+        player.play()
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/Assets.xcassets/AccentColor.colorset/Contents.json b/Video Feed Test/Assets.xcassets/AccentColor.colorset/Contents.json
new file mode 100644
index 0000000..eb87897
--- /dev/null
+++ b/Video Feed Test/Assets.xcassets/AccentColor.colorset/Contents.json	
@@ -0,0 +1,11 @@
+{
+  "colors" : [
+    {
+      "idiom" : "universal"
+    }
+  ],
+  "info" : {
+    "author" : "xcode",
+    "version" : 1
+  }
+}
diff --git a/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Contents.json b/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Contents.json
new file mode 100644
index 0000000..7b7c647
--- /dev/null
+++ b/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Contents.json	
@@ -0,0 +1,38 @@
+{
+  "images" : [
+    {
+      "filename" : "Icon-iOS-Default-1024x1024@1x.png",
+      "idiom" : "universal",
+      "platform" : "ios",
+      "size" : "1024x1024"
+    },
+    {
+      "appearances" : [
+        {
+          "appearance" : "luminosity",
+          "value" : "dark"
+        }
+      ],
+      "filename" : "Icon-iOS-Dark-1024x1024@1x.png",
+      "idiom" : "universal",
+      "platform" : "ios",
+      "size" : "1024x1024"
+    },
+    {
+      "appearances" : [
+        {
+          "appearance" : "luminosity",
+          "value" : "tinted"
+        }
+      ],
+      "filename" : "Icon-iOS-TintedDark-1024x1024@1x.png",
+      "idiom" : "universal",
+      "platform" : "ios",
+      "size" : "1024x1024"
+    }
+  ],
+  "info" : {
+    "author" : "xcode",
+    "version" : 1
+  }
+}
diff --git a/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Dark-1024x1024@1x.png b/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Dark-1024x1024@1x.png
new file mode 100644
index 0000000..b68d9f0
Binary files /dev/null and b/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Dark-1024x1024@1x.png differ
diff --git a/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png b/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png
new file mode 100644
index 0000000..747fd4c
Binary files /dev/null and b/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png differ
diff --git a/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-TintedDark-1024x1024@1x.png b/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-TintedDark-1024x1024@1x.png
new file mode 100644
index 0000000..dd3f8e1
Binary files /dev/null and b/Video Feed Test/Assets.xcassets/AppIcon.appiconset/Icon-iOS-TintedDark-1024x1024@1x.png differ
diff --git a/Video Feed Test/Assets.xcassets/Contents.json b/Video Feed Test/Assets.xcassets/Contents.json
new file mode 100644
index 0000000..73c0059
--- /dev/null
+++ b/Video Feed Test/Assets.xcassets/Contents.json	
@@ -0,0 +1,6 @@
+{
+  "info" : {
+    "author" : "xcode",
+    "version" : 1
+  }
+}
diff --git a/Video Feed Test/AutoPlayView.swift b/Video Feed Test/AutoPlayView.swift
new file mode 100644
index 0000000..860c625
--- /dev/null
+++ b/Video Feed Test/AutoPlayView.swift	
@@ -0,0 +1 @@
+// Removed: AutoPlayView and related view model. Project uses TikTokFeedView exclusively.
\ No newline at end of file
diff --git a/Video Feed Test/CurrentMonthGridView.swift b/Video Feed Test/CurrentMonthGridView.swift
new file mode 100644
index 0000000..4d41838
--- /dev/null
+++ b/Video Feed Test/CurrentMonthGridView.swift	
@@ -0,0 +1,1217 @@
+/*
+ UI and behavior spec — CurrentMonthGridView (keep this section up to date)
+
+ Summary
+ - Month-scoped media browser with two modes layered together:
+   1) Base non-favorites grid (all assets for month; favorites are shown or hidden depending on mode).
+   2) Favorites overlay (sections and highlights), animating with matchedGeometryEffect.
+
+ Data & filtering
+ - Scope: assets whose creationDate is within [selectedMonthStart, selectedMonthStart + 1 month).
+ - Types: images (excluding screenshots), videos restricted heuristically to camera-likely files (IMG_/VID_ filename prefixes).
+ - Sort: descending by creationDate (most recent first).
+ - Authorization: request Photos.readWrite on first appearance; register for library changes on success (authorized/limited).
+ - Reload on PHPhotoLibrary changes; month navigation triggers refetch.
+
+ Primary views and layout
+ - Navigation: title shows current month in "LLLL yyyy". Toolbar has chevrons (previous/next month) and a mode toggle (grid <-> heart).
+ - Base grid (NonFavoritesGrid):
+   - Columns: portrait=3, landscape=5, spacing=0.
+   - Shows all month assets when non-favorites mode is active.
+   - When favorites mode is active, favorites are replaced by placeholders to preserve grid geometry and enable matchedGeometryEffect.
+ - Favorites overlay (FavoritesSectionsView), visible only in favorites mode:
+   - Highlights: up to 9 super favorites (3 columns) at the top.
+   - Below, sections by day ranges: 21..end, 11..20, 1..10 in a 4-column grid (spacing=6).
+   - Up to 8 items per section. If not enough items (especially for current month’s ongoing section), placeholders fill the layout to stable 2x4 blocks.
+   - Favorite cells are clipped with a rounded rectangle (8pt corner); matchedGeometryEffect syncs with base grid cells.
+ - Placeholder cells are non-interactive and accessibility-hidden.
+ - Background uses systemBackground and respects safe areas.
+
+ Interactions
+ - Single-tap on a cell toggles asset.isFavorite.
+ - Double-tap toggles "super favorite" (persisted via actor-backed store), and auto-favorites if not already a favorite.
+ - Mode toggle switches between showing the base grid (all) and the favorites overlay (with base grid showing placeholders for the favorites).
+ - Month navigation animates and reloads; matchedGeometryEffect keeps favorites visually consistent between modes.
+
+ Performance policy
+ - Minimize main-thread work: filename-based video filtering (PHAssetResource) offloaded to a background queue; UI updates are generation-gated to drop stale results.
+ - Thumbnails: PHCachingImageManager with fastFormat + resizeMode.fast, network allowed, degraded images acceptable.
+ - Target thumb size: cellSide * screenScale * 0.85 (tuned to reduce decoding cost and memory while being visually crisp).
+ - Preheating: rolling window (~40 assets) around the latest visible index; stop old caching when month changes; incremental start/stop based on set differences.
+ - Cancellation: in-flight thumb requests are cancelled on disappear.
+ - Memory/overdraw: grid uses zero spacing for base content; favorites overlay uses spacing 6 with rounded clips; background set to systemBackground.
+ - Expected perf envelopes (debug build guidance):
+   - p50 thumbnail latency < 150 ms; p95 < 400 ms; monitor in logs.
+   - Steady-state memory: < 120 MB for typical months on device-class under test.
+   - Smoothness: 55–60 FPS while scrolling on modern devices.
+
+ Accessibility
+ - VoiceOver labels: "Photo, <date>[, Favorite]" or "Video, <date>, <duration>[, Favorite]".
+ - Touch target equals the entire cell; placeholders are marked accessibilityHidden.
+ - Toolbars have accessibility labels: "Previous month", "Next month", and toggle label reflects current mode.
+
+ Diagnostics and instrumentation
+ - Structured logs on: auth flow (with signpost), month reload triggers, preheating decisions (start/stop counts), thumb request begin/end with latency, PhotoKit info keys.
+ - Generation token ensures we ignore slow/out-of-date results.
+ - Use Instruments to correlate "Missing prefetched properties" messages with user actions; prefer explicit preheating windows to avoid main-queue fetches.
+
+ Edge cases
+ - Limited library: behaves as authorized within the allowed scope.
+ - iCloud-only assets: degraded images may arrive first; network is allowed; cancellation respected.
+ - Empty month: stop all caching, clear IDs, show empty content (with loading cleared).
+ */
+
+import SwiftUI
+import Photos
+import UIKit
+import AVFoundation
+import Combine
+import os
+import os.signpost
+
+actor SuperFavoritesStore {
+    private let key = "super_favorites_v1"
+    private var ids: Set<String>
+
+    init() {
+        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
+    }
+
+    func all() -> Set<String> { ids }
+
+    func contains(_ id: String) -> Bool { ids.contains(id) }
+
+    func toggle(id: String) {
+        if ids.contains(id) {
+            ids.remove(id)
+        } else {
+            ids.insert(id)
+        }
+        persist()
+    }
+
+    func set(id: String, value: Bool) {
+        if value {
+            ids.insert(id)
+        } else {
+            ids.remove(id)
+        }
+        persist()
+    }
+
+    private func persist() {
+        UserDefaults.standard.set(Array(ids), forKey: key)
+    }
+}
+
+@MainActor
+final class CurrentMonthGridViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
+    @Published var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
+    @Published var assets: [PHAsset] = []
+    @Published var isLoading = false
+    @Published var selectedMonthStart: Date = {
+        let calendar = Calendar.current
+        let now = Date()
+        return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
+    }()
+    @Published var superFavoriteIDs: Set<String> = []
+
+    private let superFavoritesStore = SuperFavoritesStore()
+    private var cachedIDs: Set<String> = []
+    private var idToIndex: [String: Int] = [:]
+    private var loadGeneration: Int = 0
+    private var lastPreheatCenter: Int?
+    private var lastPreheatTarget: CGSize?
+
+    private let cameraFilenamePrefixes: [String] = ["IMG_", "VID_"]
+
+    override init() {
+        super.init()
+        if authorization == .authorized || authorization == .limited {
+            PHPhotoLibrary.shared().register(self)
+        }
+        Task { [weak self] in
+            guard let self else { return }
+            let ids = await superFavoritesStore.all()
+            await MainActor.run {
+                self.superFavoriteIDs = ids
+            }
+        }
+    }
+
+    deinit {
+        PHPhotoLibrary.shared().unregisterChangeObserver(self)
+        monthCachingManager.stopCachingImagesForAllAssets()
+    }
+
+    func onAppear() {
+        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
+        Diagnostics.log("Photos onAppear authorization=\(String(describing: status.rawValue))")
+        authorization = status
+        switch status {
+        case .notDetermined:
+            var signpost: OSSignpostID?
+            Diagnostics.signpostBegin("AuthRequest", id: &signpost)
+            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
+                Task { @MainActor [weak self] in
+                    Diagnostics.log("Photos authorization result=\(String(describing: newStatus.rawValue))")
+                    Diagnostics.signpostEnd("AuthRequest", id: signpost)
+                    self?.authorization = newStatus
+                    if newStatus == .authorized || newStatus == .limited {
+                        guard let self else { return }
+                        PHPhotoLibrary.shared().register(self)
+                        self.loadSelectedMonth()
+                    }
+                }
+            }
+        case .authorized, .limited:
+            loadSelectedMonth()
+        default:
+            break
+        }
+    }
+
+    func reload() {
+        loadSelectedMonth()
+    }
+
+    func isSuperFavorite(_ asset: PHAsset) -> Bool {
+        superFavoriteIDs.contains(asset.localIdentifier)
+    }
+
+    func toggleSuperFavorite(for asset: PHAsset) {
+        Task { [weak self] in
+            guard let self else { return }
+            let id = asset.localIdentifier
+            let isSuper = self.superFavoriteIDs.contains(id)
+            if isSuper {
+                await self.superFavoritesStore.set(id: id, value: false)
+            } else {
+                await self.superFavoritesStore.set(id: id, value: true)
+                if !asset.isFavorite {
+                    self.toggleFavorite(for: asset)
+                }
+            }
+            let refreshed = await self.superFavoritesStore.all()
+            await MainActor.run {
+                self.superFavoriteIDs = refreshed
+            }
+        }
+    }
+
+    func toggleFavorite(for asset: PHAsset) {
+        let targetValue = !asset.isFavorite
+        PHPhotoLibrary.shared().performChanges({
+            let request = PHAssetChangeRequest(for: asset)
+            request.isFavorite = targetValue
+        }, completionHandler: nil)
+    }
+
+    func photoLibraryDidChange(_ changeInstance: PHChange) {
+        Diagnostics.log("PhotoLibrary didChange received, reloading month")
+        Task { @MainActor in
+            self.loadSelectedMonth()
+        }
+    }
+
+    func preheat(center: Int, targetSize: CGSize, window: Int = 40) {
+        guard !assets.isEmpty else { return }
+        if let lastCenter = lastPreheatCenter, let lastTarget = lastPreheatTarget {
+            let delta = abs(center - lastCenter)
+            let minStep = max(8, window / 4)
+            if delta < minStep && lastTarget == targetSize {
+                return
+            }
+        }
+        lastPreheatCenter = center
+        lastPreheatTarget = targetSize
+
+        let halfWindow = window / 2
+        let range = (center - halfWindow)..<(center + halfWindow)
+        let identifiers = Set(assets(in: range).map(\.localIdentifier))
+        let toStart = identifiers.subtracting(cachedIDs)
+        let toStop = cachedIDs.subtracting(identifiers)
+
+        Diagnostics.log("Preheat center=\(center) window=\(window) start=\(toStart.count) stop=\(toStop.count) target=\(Int(targetSize.width))x\(Int(targetSize.height))")
+
+        if !toStop.isEmpty {
+            let stopAssets = toStop.compactMap(asset(withIdentifier:))
+            monthCachingManager.stopCachingImages(for: stopAssets,
+                                                  targetSize: targetSize,
+                                                  contentMode: .aspectFill,
+                                                  options: cachingOptions())
+            cachedIDs.subtract(stopAssets.map(\.localIdentifier))
+        }
+
+        if !toStart.isEmpty {
+            let startAssets = toStart.compactMap(asset(withIdentifier:))
+            monthCachingManager.startCachingImages(for: startAssets,
+                                                   targetSize: targetSize,
+                                                   contentMode: .aspectFill,
+                                                   options: cachingOptions())
+            cachedIDs.formUnion(startAssets.map(\.localIdentifier))
+        }
+    }
+
+    func preheatForAsset(_ asset: PHAsset, targetSize: CGSize, window: Int = 40) {
+        guard let index = idToIndex[asset.localIdentifier] else { return }
+        Diagnostics.log("PreheatForAsset id=\(asset.localIdentifier) idx=\(index) window=\(window) target=\(Int(targetSize.width))x\(Int(targetSize.height))")
+        preheat(center: index, targetSize: targetSize, window: window)
+    }
+
+    func goToPreviousMonth() {
+        let calendar = Calendar.current
+        guard let newStart = calendar.date(byAdding: DateComponents(month: -1), to: selectedMonthStart) else { return }
+        Diagnostics.log("Navigate previousMonth from=\(selectedMonthStart.timeIntervalSince1970) to=\(newStart.timeIntervalSince1970)")
+        selectedMonthStart = newStart
+        loadSelectedMonth()
+    }
+
+    func goToNextMonth() {
+        let calendar = Calendar.current
+        guard let newStart = calendar.date(byAdding: DateComponents(month: 1), to: selectedMonthStart) else { return }
+        Diagnostics.log("Navigate nextMonth from=\(selectedMonthStart.timeIntervalSince1970) to=\(newStart.timeIntervalSince1970)")
+        selectedMonthStart = newStart
+        loadSelectedMonth()
+    }
+
+    private func loadSelectedMonth() {
+        isLoading = true
+        let bounds = monthBounds()
+        let options = PHFetchOptions()
+
+        let typeImage = PHAssetMediaType.image.rawValue
+        let typeVideo = PHAssetMediaType.video.rawValue
+        let screenshotMask = PHAssetMediaSubtype.photoScreenshot.rawValue
+
+        let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", bounds.start as NSDate, bounds.end as NSDate)
+        let imagesPredicate = NSPredicate(format: "mediaType == %d AND ((mediaSubtypes & %d) == 0)", typeImage, Int(screenshotMask))
+        let videosPredicate = NSPredicate(format: "mediaType == %d", typeVideo)
+        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
+            NSCompoundPredicate(orPredicateWithSubpredicates: [imagesPredicate, videosPredicate]),
+            datePredicate
+        ])
+        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
+
+        let startTime = CACurrentMediaTime()
+        let result = PHAsset.fetchAssets(with: options)
+        let count = result.count
+
+        monthCachingManager.stopCachingImagesForAllAssets()
+        cachedIDs.removeAll()
+        loadGeneration &+= 1
+        let generation = loadGeneration
+
+        guard count > 0 else {
+            idToIndex.removeAll()
+            assets = []
+            isLoading = false
+            Diagnostics.log("MonthFetch result=0 total=\(String(format: "%.3f", CACurrentMediaTime() - startTime))s")
+            return
+        }
+
+        let indexSet = IndexSet(integersIn: 0..<count)
+        let fetched = result.objects(at: indexSet)
+        let fetchElapsed = CACurrentMediaTime() - startTime
+
+        let images = fetched.filter { $0.mediaType == .image }
+        let videos = fetched.filter { $0.mediaType == .video }
+
+        Task.detached(priority: .userInitiated) { [weak self] in
+            guard let self else { return }
+            let filterStart = CACurrentMediaTime()
+            // Filename-based heuristic: keep only camera-likely videos
+            let filteredVideos: [PHAsset] = videos.filter { asset in
+                let resources = PHAssetResource.assetResources(for: asset)
+                // Check any resource name; uppercase for case-insensitive compare
+                let names = resources.map { $0.originalFilename.uppercased() }
+                return names.contains(where: { name in
+                    self.cameraFilenamePrefixes.contains(where: { prefix in name.hasPrefix(prefix) })
+                })
+            }
+            let combined = images + filteredVideos
+            let filterElapsed = CACurrentMediaTime() - filterStart
+            let totalElapsed = CACurrentMediaTime() - startTime
+
+            await MainActor.run {
+                guard self.loadGeneration == generation else {
+                    Diagnostics.log("MonthFetch drop-stale gen requested=\(generation) current=\(self.loadGeneration)")
+                    return
+                }
+                self.idToIndex = Dictionary(uniqueKeysWithValues: combined.enumerated().map { index, asset in
+                    (asset.localIdentifier, index)
+                })
+                self.assets = combined
+                self.isLoading = false
+                Diagnostics.log("MonthFetch result=\(combined.count) images=\(images.count) videos=\(videos.count) videosKept=\(filteredVideos.count) fetch=\(String(format: "%.3f", fetchElapsed))s filter=\(String(format: "%.3f", filterElapsed))s total=\(String(format: "%.3f", totalElapsed))s")
+            }
+        }
+    }
+
+    private func monthBounds() -> (start: Date, end: Date) {
+        let calendar = Calendar.current
+        let start = selectedMonthStart
+        let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? start
+        return (start, end)
+    }
+
+    private func assets(in range: Range<Int>) -> [PHAsset] {
+        guard !assets.isEmpty else { return [] }
+        let lower = max(range.lowerBound, 0)
+        let upper = min(range.upperBound, assets.count)
+        guard lower < upper else { return [] }
+        return Array(assets[lower..<upper])
+    }
+
+    private func asset(withIdentifier id: String) -> PHAsset? {
+        guard let index = idToIndex[id], assets.indices.contains(index) else { return nil }
+        return assets[index]
+    }
+
+    private func cachingOptions() -> PHImageRequestOptions {
+        let options = PHImageRequestOptions()
+        options.deliveryMode = .fastFormat
+        options.resizeMode = .fast
+        options.isSynchronous = false
+        options.isNetworkAccessAllowed = true
+        return options
+    }
+}
+
+private let monthCachingManager = PHCachingImageManager()
+private let thumbnailScaleFactor: CGFloat = 0.85
+
+struct CurrentMonthGridView: View {
+    @Environment(\.dismiss) private var dismiss
+    @StateObject private var model = CurrentMonthGridViewModel()
+
+    @State private var showFavoritesView = true
+    @Namespace private var gridNamespace
+
+    private var favoriteAssets: [PHAsset] {
+        model.assets.filter(\.isFavorite)
+    }
+
+    private var superFavoriteAssets: [PHAsset] {
+        model.assets.filter { $0.isFavorite && model.isSuperFavorite($0) }
+    }
+
+    private var monthTitle: String {
+        let formatter = DateFormatter()
+        formatter.dateFormat = "LLLL yyyy"
+        return formatter.string(from: model.selectedMonthStart)
+    }
+
+    private var lastDayOfCurrentMonth: Int {
+        let calendar = Calendar.current
+        return calendar.range(of: .day, in: .month, for: model.selectedMonthStart)?.count ?? 30
+    }
+
+    var body: some View {
+        NavigationStack {
+            Group {
+                switch model.authorization {
+                case .denied, .restricted:
+                    deniedView
+                default:
+                    content
+                }
+            }
+            .navigationTitle(monthTitle)
+            .toolbar {
+                ToolbarItemGroup(placement: .topBarTrailing) {
+                    Button {
+                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
+                            model.goToPreviousMonth()
+                        }
+                    } label: {
+                        Image(systemName: "chevron.left")
+                    }
+                    .accessibilityLabel("Previous month")
+
+                    Button {
+                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
+                            model.goToNextMonth()
+                        }
+                    } label: {
+                        Image(systemName: "chevron.right")
+                    }
+                    .accessibilityLabel("Next month")
+
+                    Button {
+                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
+                            showFavoritesView.toggle()
+                        }
+                    } label: {
+                        Image(systemName: showFavoritesView ? "square.grid.3x3" : "heart.fill")
+                    }
+                    .accessibilityLabel(showFavoritesView ? "Show non-favorites" : "Show favorites")
+                }
+            }
+        }
+        .onAppear {
+            monthCachingManager.allowsCachingHighQualityImages = false
+            model.onAppear()
+        }
+    }
+
+    private var content: some View {
+        ZStack {
+            NonFavoritesGrid(
+                model: model,
+                showFavoritesView: $showFavoritesView,
+                gridNamespace: gridNamespace
+            )
+            FavoritesSectionsView(
+                model: model,
+                showFavoritesView: $showFavoritesView,
+                gridNamespace: gridNamespace,
+                highlightsTop: Array(superFavoriteAssets.prefix(9)),
+                favoritesProvider: favorites(in:),
+                isRangeFullyPast: isRangeFullyPast(_:),
+                lastDayOfMonth: lastDayOfCurrentMonth
+            )
+            .opacity(showFavoritesView ? 1 : 0)
+            .allowsHitTesting(showFavoritesView)
+            .transition(.opacity)
+        }
+        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
+        .animation(.spring(response: 0.55, dampingFraction: 0.88), value: showFavoritesView)
+    }
+
+    private func favorites(in range: ClosedRange<Int>) -> [PHAsset] {
+        let calendar = Calendar.current
+        return favoriteAssets
+            .filter { asset in
+                guard let date = asset.creationDate else { return false }
+                let day = calendar.component(.day, from: date)
+                return range.contains(day)
+            }
+            .sorted { lhs, rhs in
+                let leftDate = lhs.creationDate ?? .distantPast
+                let rightDate = rhs.creationDate ?? .distantPast
+                if leftDate != rightDate {
+                    return leftDate > rightDate
+                }
+                return lhs.localIdentifier > rhs.localIdentifier
+            }
+    }
+
+    private func isRangeFullyPast(_ range: ClosedRange<Int>) -> Bool {
+        let calendar = Calendar.current
+        guard calendar.isDate(model.selectedMonthStart, equalTo: Date(), toGranularity: .month) else {
+            return true
+        }
+        let today = calendar.component(.day, from: Date())
+        return today > range.upperBound
+    }
+
+    private var deniedView: some View {
+        VStack(spacing: 12) {
+            Spacer()
+            Image(systemName: "photo.on.rectangle.angled")
+                .font(.system(size: 48))
+                .foregroundStyle(.secondary)
+            Text("Photos access needed")
+                .font(.headline)
+            Text("Allow access in Settings to view this month's media.")
+                .font(.subheadline)
+                .foregroundStyle(.secondary)
+                .multilineTextAlignment(.center)
+                .padding(.horizontal)
+            HStack(spacing: 16) {
+                Button("Open Settings") {
+                    if let url = URL(string: UIApplication.openSettingsURLString) {
+                        UIApplication.shared.open(url)
+                    }
+                }
+                .buttonStyle(.borderedProminent)
+
+                Button("Close") { dismiss() }
+                    .buttonStyle(.bordered)
+            }
+            Spacer()
+        }
+        .padding()
+        .background(Color.black.ignoresSafeArea())
+    }
+}
+
+private struct NonFavoritesGrid: View {
+    @ObservedObject var model: CurrentMonthGridViewModel
+    @Binding var showFavoritesView: Bool
+    let gridNamespace: Namespace.ID
+    var feedMode: Bool = false
+
+    var body: some View {
+        GeometryReader { geometry in
+            let size = geometry.size
+            let spacing: CGFloat = 0
+            let columns = columnCount(for: size)
+            let cellSide = floor((size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
+            let grid = Array(repeating: GridItem(.fixed(cellSide), spacing: spacing, alignment: .top), count: columns)
+            let scale = UIScreen.main.scale
+            let targetPixels = CGSize(width: cellSide * scale, height: cellSide * scale)
+            let requestPixels = CGSize(width: targetPixels.width * thumbnailScaleFactor,
+                                       height: targetPixels.height * thumbnailScaleFactor)
+
+            if feedMode {
+                let rowsFit = max(1, Int(floor(size.height / max(cellSide, 1))))
+                let maxItems = max(1, rowsFit * columns)
+                let visible = Array(model.assets.prefix(maxItems).enumerated())
+
+                VStack(spacing: 0) {
+                    if model.isLoading {
+                        ProgressView()
+                            .padding(.vertical, 12)
+                    }
+
+                    LazyVGrid(columns: grid, spacing: spacing) {
+                        ForEach(visible, id: \.element.localIdentifier) { index, asset in
+                            if showFavoritesView && asset.isFavorite {
+                                PlaceholderCell()
+                                    .frame(width: cellSide, height: cellSide)
+                                    .clipped()
+                            } else {
+                                AssetGridCell(
+                                    asset: asset,
+                                    targetPixelSize: requestPixels,
+                                    isFavorite: asset.isFavorite,
+                                    onSingleTap: { model.toggleFavorite(for: asset) },
+                                    onDoubleTap: { model.toggleSuperFavorite(for: asset) }
+                                )
+                                .frame(width: cellSide, height: cellSide)
+                                .clipped()
+                                .accessibilityElement(children: .ignore)
+                                .accessibilityLabel(assetAccessibilityLabel(for: asset))
+                                .matchedGeometryEffect(id: asset.localIdentifier,
+                                                       in: gridNamespace,
+                                                       isSource: !showFavoritesView && asset.isFavorite)
+                                .zIndex(asset.isFavorite ? 1 : 0)
+                                .onAppear {
+                                    model.preheat(center: index, targetSize: requestPixels)
+                                }
+                            }
+                        }
+                    }
+
+                    Spacer(minLength: 0)
+                }
+                .frame(height: size.height, alignment: .top)
+                .clipped()
+            } else {
+                ScrollView {
+                    if model.isLoading {
+                        ProgressView()
+                            .padding(.vertical, 12)
+                    }
+
+                    LazyVGrid(columns: grid, spacing: spacing) {
+                        ForEach(Array(model.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
+                            if showFavoritesView && asset.isFavorite {
+                                PlaceholderCell()
+                                    .frame(width: cellSide, height: cellSide)
+                                    .clipped()
+                            } else {
+                                AssetGridCell(
+                                    asset: asset,
+                                    targetPixelSize: requestPixels,
+                                    isFavorite: asset.isFavorite,
+                                    onSingleTap: { model.toggleFavorite(for: asset) },
+                                    onDoubleTap: { model.toggleSuperFavorite(for: asset) }
+                                )
+                                .frame(width: cellSide, height: cellSide)
+                                .clipped()
+                                .accessibilityElement(children: .ignore)
+                                .accessibilityLabel(assetAccessibilityLabel(for: asset))
+                                .matchedGeometryEffect(id: asset.localIdentifier,
+                                                       in: gridNamespace,
+                                                       isSource: !showFavoritesView && asset.isFavorite)
+                                .zIndex(asset.isFavorite ? 1 : 0)
+                                .onAppear {
+                                    model.preheat(center: index, targetSize: requestPixels)
+                                }
+                            }
+                        }
+                    }
+                    .padding(.top, 2)
+                    .padding(.bottom, 8)
+                }
+            }
+        }
+    }
+
+    private func columnCount(for size: CGSize) -> Int {
+        size.width > size.height ? 5 : 3
+    }
+}
+
+private struct FavoritesSectionsView: View {
+    @ObservedObject var model: CurrentMonthGridViewModel
+    @Binding var showFavoritesView: Bool
+    let gridNamespace: Namespace.ID
+    var feedMode: Bool = false
+
+    let highlightsTop: [PHAsset]
+    let favoritesProvider: (ClosedRange<Int>) -> [PHAsset]
+    let isRangeFullyPast: (ClosedRange<Int>) -> Bool
+    let lastDayOfMonth: Int
+
+    private var highlightIDs: Set<String> {
+        Set(highlightsTop.map(\.localIdentifier))
+    }
+
+    var body: some View {
+        GeometryReader { geometry in
+            let width = geometry.size.width
+            let spacing: CGFloat = 6
+            let scale = UIScreen.main.scale
+
+            let topColumns = 3
+            let topCellSide = floor((width - CGFloat(topColumns - 1) * spacing) / CGFloat(topColumns))
+            let topTargetPixels = CGSize(width: topCellSide * scale, height: topCellSide * scale)
+            let topRequestPixels = CGSize(width: topTargetPixels.width * thumbnailScaleFactor,
+                                          height: topTargetPixels.height * thumbnailScaleFactor)
+            let topGrid = Array(repeating: GridItem(.fixed(topCellSide), spacing: spacing, alignment: .top), count: topColumns)
+
+            let lowerColumns = 4
+            let lowerCellSide = floor((width - CGFloat(lowerColumns - 1) * spacing) / CGFloat(lowerColumns))
+            let lowerTargetPixels = CGSize(width: lowerCellSide * scale, height: lowerCellSide * scale)
+            let lowerRequestPixels = CGSize(width: lowerTargetPixels.width * thumbnailScaleFactor,
+                                            height: lowerTargetPixels.height * thumbnailScaleFactor)
+            let lowerGrid = Array(repeating: GridItem(.fixed(lowerCellSide), spacing: spacing, alignment: .top), count: lowerColumns)
+
+            if feedMode {
+                // Non-scroll, fit into one page. Compute how many lower rows fit after highlights.
+                let topRows = Int(ceil(Double(highlightsTop.count) / Double(topColumns)))
+                let topHeight = topRows > 0
+                    ? (CGFloat(topRows) * topCellSide + CGFloat(max(0, topRows - 1)) * spacing)
+                    : 0
+                let contentTopPadding: CGFloat = 8
+                let contentBottomPadding: CGFloat = 16
+                let afterHighlightsSpacing: CGFloat = (topRows > 0 ? 24 : 0)
+                let availableHeight = max(0, geometry.size.height - contentTopPadding - contentBottomPadding)
+                let lowerRowHeight = lowerCellSide + 6
+                let remainingHeight = max(0, availableHeight - topHeight - afterHighlightsSpacing)
+                let lowerRowsBudget = max(0, Int(floor(remainingHeight / max(lowerRowHeight, 1))))
+                let sectionRowBudgets = computeSectionRowBudgets(totalRows: lowerRowsBudget)
+
+                VStack(alignment: .leading, spacing: 24) {
+                    if model.isLoading {
+                        ProgressView()
+                            .padding(.vertical, 12)
+                    }
+
+                    if !highlightsTop.isEmpty {
+                        LazyVGrid(columns: topGrid, spacing: spacing) {
+                            ForEach(highlightsTop, id: \.localIdentifier) { asset in
+                                overlayCell(asset: asset,
+                                            cellSide: topCellSide,
+                                            targetPixelSize: topRequestPixels)
+                            }
+                        }
+                    }
+
+                    ForEach(FavoritesSectionRange.displayOrder) { section in
+                        if let rows = sectionRowBudgets[section], rows > 0 {
+                            sectionGrid(range: section.range(lastDayOfMonth: lastDayOfMonth),
+                                        columns: lowerGrid,
+                                        cellSide: lowerCellSide,
+                                        targetPixelSize: lowerRequestPixels,
+                                        maxSlotsOverride: rows * lowerColumns)
+                        }
+                    }
+                }
+                .padding(.top, contentTopPadding)
+                .padding(.bottom, contentBottomPadding)
+                .frame(height: geometry.size.height, alignment: .top)
+                .clipped()
+                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
+            } else {
+                ScrollView {
+                    VStack(alignment: .leading, spacing: 24) {
+                        if model.isLoading {
+                            ProgressView()
+                                .padding(.vertical, 12)
+                        }
+
+                        if !highlightsTop.isEmpty {
+                            LazyVGrid(columns: topGrid, spacing: spacing) {
+                                ForEach(highlightsTop, id: \.localIdentifier) { asset in
+                                    overlayCell(asset: asset,
+                                                cellSide: topCellSide,
+                                                targetPixelSize: topRequestPixels)
+                                }
+                            }
+                        }
+
+                        ForEach(FavoritesSectionRange.displayOrder) { section in
+                            sectionGrid(range: section.range(lastDayOfMonth: lastDayOfMonth),
+                                        columns: lowerGrid,
+                                        cellSide: lowerCellSide,
+                                        targetPixelSize: lowerRequestPixels)
+                        }
+                    }
+                    .padding(.top, 8)
+                    .padding(.bottom, 16)
+                }
+                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
+            }
+        }
+    }
+
+    @ViewBuilder
+    private func sectionGrid(range: ClosedRange<Int>,
+                             columns: [GridItem],
+                             cellSide: CGFloat,
+                             targetPixelSize: CGSize,
+                             maxSlotsOverride: Int? = nil) -> some View {
+        let filteredFavorites = favoritesProvider(range)
+            .filter { !highlightIDs.contains($0.localIdentifier) }
+        let columnCount = max(columns.count, 1)
+        let defaultMaxSlots = columnCount * 2
+        let maxSlots = min(maxSlotsOverride ?? defaultMaxSlots, defaultMaxSlots)
+        let hideEmptyRows = isRangeFullyPast(range)
+        let slots = arrangedSlots(for: Array(filteredFavorites.prefix(maxSlots)),
+                                  range: range,
+                                  columnCount: columnCount,
+                                  maxSlots: maxSlots,
+                                  hideEmptyRows: hideEmptyRows)
+
+        if slots.isEmpty {
+            EmptyView()
+        } else {
+            LazyVGrid(columns: columns, spacing: 6) {
+                ForEach(slots) { slot in
+                    switch slot.kind {
+                    case .asset(let asset):
+                        overlayCell(asset: asset,
+                                    cellSide: cellSide,
+                                    targetPixelSize: targetPixelSize)
+                    case .placeholder:
+                        PlaceholderCell()
+                            .frame(width: cellSide, height: cellSide)
+                            .clipped()
+                    }
+                }
+            }
+        }
+    }
+
+    private func arrangedSlots(for assets: [PHAsset],
+                               range: ClosedRange<Int>,
+                               columnCount: Int,
+                               maxSlots: Int,
+                               hideEmptyRows: Bool) -> [FavoritesSectionSlot] {
+        guard columnCount > 0, maxSlots > 0 else { return [] }
+        let limitedAssets = Array(assets.prefix(maxSlots))
+        if limitedAssets.isEmpty && hideEmptyRows {
+            return []
+        }
+
+        if hideEmptyRows {
+            return limitedAssets.map { asset in
+                FavoritesSectionSlot(id: asset.localIdentifier, kind: .asset(asset))
+            }
+        } else {
+            var slots: [FavoritesSectionSlot] = []
+            for index in 0..<maxSlots {
+                if index < limitedAssets.count {
+                    let asset = limitedAssets[index]
+                    slots.append(FavoritesSectionSlot(id: asset.localIdentifier, kind: .asset(asset)))
+                } else {
+                    slots.append(FavoritesSectionSlot(id: placeholderIdentifier(range: range, index: index),
+                                                      kind: .placeholder))
+                }
+            }
+            return slots
+        }
+    }
+
+    private func placeholderIdentifier(range: ClosedRange<Int>, index: Int) -> String {
+        "placeholder-\(range.lowerBound)-\(range.upperBound)-\(index)"
+    }
+
+    private func overlayCell(asset: PHAsset,
+                             cellSide: CGFloat,
+                             targetPixelSize: CGSize) -> some View {
+        AssetGridCell(
+            asset: asset,
+            targetPixelSize: targetPixelSize,
+            isFavorite: true,
+            onSingleTap: nil,
+            onDoubleTap: { model.toggleSuperFavorite(for: asset) }
+        )
+        .frame(width: cellSide, height: cellSide)
+        .clipShape(RoundedRectangle(cornerRadius: 8))
+        .matchedGeometryEffect(id: asset.localIdentifier,
+                               in: gridNamespace,
+                               isSource: showFavoritesView)
+        .accessibilityElement(children: .ignore)
+        .accessibilityLabel(assetAccessibilityLabel(for: asset))
+        .zIndex(2)
+        .onAppear {
+            model.preheatForAsset(asset, targetSize: targetPixelSize)
+        }
+        .contextMenu {
+            if asset.isFavorite {
+                Button(role: .destructive) {
+                    model.toggleFavorite(for: asset)
+                } label: {
+                    Label("Remove from Favorites", systemImage: "heart.slash")
+                }
+            } else {
+                Button {
+                    model.toggleFavorite(for: asset)
+                } label: {
+                    Label("Add to Favorites", systemImage: "heart")
+                }
+            }
+
+            if model.isSuperFavorite(asset) {
+                Button {
+                    model.toggleSuperFavorite(for: asset)
+                } label: {
+                    Label("Remove Super Favorite", systemImage: "star.slash")
+                }
+            } else {
+                Button {
+                    model.toggleSuperFavorite(for: asset)
+                } label: {
+                    Label("Make Super Favorite", systemImage: "star")
+                }
+            }
+        }
+    }
+
+    private func computeSectionRowBudgets(totalRows: Int) -> [FavoritesSectionRange: Int] {
+        var remaining = max(0, totalRows)
+        var dict: [FavoritesSectionRange: Int] = [:]
+        for section in FavoritesSectionRange.displayOrder {
+            if remaining <= 0 {
+                dict[section] = 0
+            } else {
+                let take = min(2, remaining)
+                dict[section] = take
+                remaining -= take
+            }
+        }
+        return dict
+    }
+}
+
+private enum FavoritesSectionRange: CaseIterable, Identifiable {
+    case lateMonth
+    case midMonth
+    case earlyMonth
+
+    var id: String {
+        switch self {
+        case .lateMonth: return "late"
+        case .midMonth: return "mid"
+        case .earlyMonth: return "early"
+        }
+    }
+
+    var priority: Int {
+        switch self {
+        case .lateMonth: return 0
+        case .midMonth: return 1
+        case .earlyMonth: return 2
+        }
+    }
+
+    static var displayOrder: [FavoritesSectionRange] {
+        allCases.sorted { $0.priority < $1.priority }
+    }
+
+    func range(lastDayOfMonth: Int) -> ClosedRange<Int> {
+        switch self {
+        case .lateMonth:
+            return max(21, 1)...lastDayOfMonth
+        case .midMonth:
+            return 11...20
+        case .earlyMonth:
+            return 1...10
+        }
+    }
+}
+
+private struct AssetGridCell: View {
+    let asset: PHAsset
+    let targetPixelSize: CGSize
+    var isFavorite: Bool = false
+    var onSingleTap: (() -> Void)?
+    var onDoubleTap: (() -> Void)?
+
+    @State private var image: UIImage?
+    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID
+    @State private var requestStartTime: CFTimeInterval = 0
+    @State private var currentAssetID: String = ""
+
+    var body: some View {
+        ZStack(alignment: .bottomTrailing) {
+            Group {
+                if let image {
+                    Image(uiImage: image)
+                        .resizable()
+                        .scaledToFill()
+                } else {
+                    RoundedRectangle(cornerRadius: 16)
+                        .fill(Color.red.opacity(0.65))
+                        .overlay(
+                            ProgressView()
+                                .tint(.white)
+                        )
+                }
+            }
+            .overlay {
+                if !isFavorite {
+                    Rectangle().fill(Color(uiColor: .systemGroupedBackground).opacity(0.65))
+                }
+            }
+        }
+        .contentShape(Rectangle())
+        .onTapGesture(count: 2) { onDoubleTap?() }
+        .onTapGesture { onSingleTap?() }
+        .onAppear {
+            handleAppear()
+        }
+        .onDisappear {
+            cancelRequest()
+            currentAssetID = ""
+            image = nil
+        }
+        .onChange(of: asset.localIdentifier) { newID in
+            guard newID != currentAssetID else { return }
+            currentAssetID = newID
+            reloadImage()
+        }
+        .accessibilityAddTraits(asset.mediaType == .video ? .isButton : [])
+    }
+
+    private func handleAppear() {
+        if currentAssetID != asset.localIdentifier {
+            currentAssetID = asset.localIdentifier
+            reloadImage()
+        } else if image == nil {
+            reloadImage()
+        } else if requestID == PHInvalidImageRequestID {
+            requestImage()
+        }
+    }
+
+    private func reloadImage() {
+        image = nil
+        requestImage()
+    }
+
+    private func requestImage() {
+        cancelRequest()
+        let options = PHImageRequestOptions()
+        options.deliveryMode = .fastFormat
+        options.resizeMode = .fast
+        options.isSynchronous = false
+        options.isNetworkAccessAllowed = true
+
+        requestStartTime = CACurrentMediaTime()
+        Diagnostics.log("Thumb request begin id=\(asset.localIdentifier) size=\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height)) fav=\(isFavorite)")
+
+        requestID = monthCachingManager.requestImage(for: asset,
+                                                     targetSize: targetPixelSize,
+                                                     contentMode: .aspectFill,
+                                                     options: options) { image, info in
+            let latency = CACurrentMediaTime() - requestStartTime
+            PhotoKitDiagnostics.logResultInfo(prefix: "Thumb info id=\(self.asset.localIdentifier)", info: info)
+            if let image {
+                self.image = image
+            }
+            Diagnostics.log("Thumb request end id=\(self.asset.localIdentifier) hasImage=\(image != nil) dt=\(String(format: "%.3f", latency))s")
+        }
+    }
+
+    private func cancelRequest() {
+        if requestID != PHInvalidImageRequestID {
+            Diagnostics.log("Thumb request cancel id=\(asset.localIdentifier)")
+            monthCachingManager.cancelImageRequest(requestID)
+            requestID = PHInvalidImageRequestID
+        }
+    }
+}
+
+private struct PlaceholderCell: View {
+    var body: some View {
+        RoundedRectangle(cornerRadius: 8)
+            .fill(Color(uiColor: .label).opacity(0.1))
+            .accessibilityHidden(true)
+    }
+}
+
+private func assetAccessibilityLabel(for asset: PHAsset) -> String {
+    let formatter = DateFormatter()
+    formatter.dateStyle = .medium
+    formatter.timeStyle = .none
+    let dateString = asset.creationDate.map { formatter.string(from: $0) } ?? "Unknown date"
+    let favoriteSuffix = asset.isFavorite ? ", Favorite" : ""
+    switch asset.mediaType {
+    case .video:
+        let duration = formatDuration(asset.duration)
+        return "Video, \(dateString), \(duration)\(favoriteSuffix)"
+    case .image:
+        return "Photo, \(dateString)\(favoriteSuffix)"
+    default:
+        return dateString
+    }
+}
+
+private func formatDuration(_ seconds: TimeInterval) -> String {
+    let totalSeconds = Int(seconds.rounded())
+    let hours = totalSeconds / 3600
+    let minutes = (totalSeconds % 3600) / 60
+    let secs = totalSeconds % 60
+    if hours > 0 {
+        return String(format: "%d:%02d:%02d", hours, minutes, secs)
+    } else {
+        return String(format: "%d:%02d", minutes, secs)
+    }
+}
+
+private struct FavoritesSectionSlot: Identifiable {
+    enum Kind {
+        case asset(PHAsset)
+        case placeholder
+    }
+
+    let id: String
+    let kind: Kind
+}
+
+struct MonthPageGridView: View {
+    let monthStart: Date
+
+    @StateObject private var model = CurrentMonthGridViewModel()
+    @State private var showFavoritesView = true
+    @Namespace private var gridNamespace
+
+    private var favoriteAssets: [PHAsset] {
+        model.assets.filter(\.isFavorite)
+    }
+
+    private var superFavoriteAssets: [PHAsset] {
+        model.assets.filter { $0.isFavorite && model.isSuperFavorite($0) }
+    }
+
+    private var lastDayOfCurrentMonth: Int {
+        let calendar = Calendar.current
+        return calendar.range(of: .day, in: .month, for: model.selectedMonthStart)?.count ?? 30
+    }
+
+    var body: some View {
+        ZStack(alignment: .topTrailing) {
+            NonFavoritesGrid(
+                model: model,
+                showFavoritesView: $showFavoritesView,
+                gridNamespace: gridNamespace,
+                feedMode: true
+            )
+            FavoritesSectionsView(
+                model: model,
+                showFavoritesView: $showFavoritesView,
+                gridNamespace: gridNamespace,
+                feedMode: true,
+                highlightsTop: Array(superFavoriteAssets.prefix(9)),
+                favoritesProvider: favorites(in:),
+                isRangeFullyPast: isRangeFullyPast(_:),
+                lastDayOfMonth: lastDayOfCurrentMonth
+            )
+            .opacity(showFavoritesView ? 1 : 0)
+            .allowsHitTesting(showFavoritesView)
+            .transition(.opacity)
+
+            Button {
+                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
+                    showFavoritesView.toggle()
+                }
+            } label: {
+                Image(systemName: showFavoritesView ? "square.grid.3x3" : "heart.fill")
+                    .font(.title2)
+                    .padding(10)
+                    .background(.ultraThinMaterial, in: Capsule())
+            }
+            .padding(.top, 12)
+            .padding(.trailing, 12)
+            .accessibilityLabel(showFavoritesView ? "Show non-favorites" : "Show favorites")
+        }
+        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
+        .animation(.spring(response: 0.55, dampingFraction: 0.88), value: showFavoritesView)
+        .onAppear {
+            monthCachingManager.allowsCachingHighQualityImages = false
+            if model.selectedMonthStart != monthStart {
+                model.selectedMonthStart = monthStart
+            }
+            model.onAppear()
+        }
+    }
+
+    private func favorites(in range: ClosedRange<Int>) -> [PHAsset] {
+        let calendar = Calendar.current
+        return favoriteAssets
+            .filter { asset in
+                guard let date = asset.creationDate else { return false }
+                let day = calendar.component(.day, from: date)
+                return range.contains(day)
+            }
+            .sorted { lhs, rhs in
+                let leftDate = lhs.creationDate ?? .distantPast
+                let rightDate = rhs.creationDate ?? .distantPast
+                if leftDate != rightDate {
+                    return leftDate > rightDate
+                }
+                return lhs.localIdentifier > rhs.localIdentifier
+            }
+    }
+
+    private func isRangeFullyPast(_ range: ClosedRange<Int>) -> Bool {
+        let calendar = Calendar.current
+        guard calendar.isDate(model.selectedMonthStart, equalTo: Date(), toGranularity: .month) else {
+            return true
+        }
+        let today = calendar.component(.day, from: Date())
+        return today > range.upperBound
+    }
+}
+
+struct MonthFeedView: View {
+    private let monthsAhead = 24
+
+    private var baseMonthStart: Date {
+        let calendar = Calendar.current
+        let now = Date()
+        return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
+    }
+
+    private var monthOffsets: [Int] {
+        Array(0...monthsAhead)
+    }
+
+    var body: some View {
+        ScrollView(.vertical) {
+            LazyVStack(spacing: 0) {
+                ForEach(monthOffsets, id: \.self) { offset in
+                    let monthDate = offsetMonth(from: baseMonthStart, by: offset)
+                    MonthPageGridView(monthStart: monthDate)
+                        .containerRelativeFrame(.vertical)
+                        .id(offset)
+                }
+            }
+            .scrollTargetLayout()
+        }
+        .scrollTargetBehavior(.paging)
+        .scrollIndicators(.hidden)
+        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
+    }
+
+    private func offsetMonth(from start: Date, by delta: Int) -> Date {
+        Calendar.current.date(byAdding: DateComponents(month: delta), to: start) ?? start
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/CurrentPlayback.swift b/Video Feed Test/CurrentPlayback.swift
new file mode 100644
index 0000000..7461d7a
--- /dev/null
+++ b/Video Feed Test/CurrentPlayback.swift	
@@ -0,0 +1,9 @@
+import Foundation
+import Combine
+
+@MainActor
+final class CurrentPlayback: ObservableObject {
+    static let shared = CurrentPlayback()
+    @Published var currentAssetID: String?
+    private init() {}
+}
\ No newline at end of file
diff --git a/Video Feed Test/DeletedCountBadge.swift b/Video Feed Test/DeletedCountBadge.swift
new file mode 100644
index 0000000..ee92099
--- /dev/null
+++ b/Video Feed Test/DeletedCountBadge.swift	
@@ -0,0 +1,29 @@
+import SwiftUI
+
+struct DeletedCountBadge: View {
+    @State private var count: Int = 0
+
+    var body: some View {
+        Text("\(count)")
+            .font(.footnote.monospacedDigit())
+            .padding(.horizontal, 8)
+            .padding(.vertical, 4)
+            .background(
+                Capsule().fill(Color.secondary.opacity(0.15))
+            )
+            .onAppear {
+                refresh()
+                NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { _ in
+                    refresh()
+                }
+            }
+            .onDisappear {
+                NotificationCenter.default.removeObserver(self, name: .deletedVideosChanged, object: nil)
+            }
+            .accessibilityLabel("Deleted videos count \(count)")
+    }
+
+    private func refresh() {
+        count = DeletedVideosStore.snapshot().count
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/DeletedVideosStore.swift b/Video Feed Test/DeletedVideosStore.swift
new file mode 100644
index 0000000..621c358
--- /dev/null
+++ b/Video Feed Test/DeletedVideosStore.swift	
@@ -0,0 +1,66 @@
+import Foundation
+import Photos
+
+actor DeletedVideosStore {
+    static let shared = DeletedVideosStore()
+    private let key = "deleted_videos_v1"
+    private var ids: Set<String>
+
+    init() {
+        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
+    }
+
+    func all() -> Set<String> { ids }
+
+    func hide(id: String) {
+        ids.insert(id)
+        persist()
+        notify()
+    }
+
+    func unhide(id: String) {
+        ids.remove(id)
+        persist()
+        notify()
+    }
+
+    func unhideAll() {
+        ids.removeAll()
+        persist()
+        notify()
+    }
+
+    func purge(ids idsToDelete: [String]) async throws {
+        guard !idsToDelete.isEmpty else { return }
+        let result = PHAsset.fetchAssets(withLocalIdentifiers: idsToDelete, options: nil)
+        var assets: [PHAsset] = []
+        result.enumerateObjects { asset, _, _ in assets.append(asset) }
+        guard !assets.isEmpty else { return }
+        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
+            PHPhotoLibrary.shared().performChanges({
+                PHAssetChangeRequest.deleteAssets(assets as NSArray)
+            }, completionHandler: { success, error in
+                if let error { cont.resume(throwing: error) } else { cont.resume(returning: ()) }
+            })
+        }
+        for id in idsToDelete { ids.remove(id) }
+        persist()
+        notify()
+    }
+
+    private func persist() {
+        UserDefaults.standard.set(Array(ids), forKey: key)
+    }
+
+    private func notify() {
+        NotificationCenter.default.post(name: .deletedVideosChanged, object: nil)
+    }
+
+    nonisolated static func snapshot() -> Set<String> {
+        Set(UserDefaults.standard.stringArray(forKey: "deleted_videos_v1") ?? [])
+    }
+}
+
+extension Notification.Name {
+    static let deletedVideosChanged = Notification.Name("DeletedVideosChanged")
+}
\ No newline at end of file
diff --git a/Video Feed Test/DeletedVideosView.swift b/Video Feed Test/DeletedVideosView.swift
new file mode 100644
index 0000000..b025fcf
--- /dev/null
+++ b/Video Feed Test/DeletedVideosView.swift	
@@ -0,0 +1,239 @@
+import SwiftUI
+import Photos
+import UIKit
+import Combine
+
+@MainActor
+final class DeletedVideosViewModel: ObservableObject {
+    @Published var ids: [String] = []
+    @Published var assets: [PHAsset] = []
+    @Published var isLoading = false
+    @Published var errorMessage: String?
+
+    init() {
+        reload()
+        NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { [weak self] _ in
+            self?.reload()
+        }
+    }
+
+    deinit {
+        NotificationCenter.default.removeObserver(self)
+    }
+
+    func reload() {
+        let snapshot = Array(DeletedVideosStore.snapshot())
+        ids = snapshot.sorted()
+        fetchAssets()
+    }
+
+    private func fetchAssets() {
+        isLoading = true
+        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
+        var list: [PHAsset] = []
+        result.enumerateObjects { a, _, _ in list.append(a) }
+        assets = list.sorted { lhs, rhs in
+            let ld = lhs.creationDate ?? .distantPast
+            let rd = rhs.creationDate ?? .distantPast
+            if ld != rd { return ld > rd }
+            return lhs.localIdentifier > rhs.localIdentifier
+        }
+        isLoading = false
+    }
+
+    func restore(_ asset: PHAsset) {
+        Task { await DeletedVideosStore.shared.unhide(id: asset.localIdentifier) }
+    }
+
+    func restoreAll() {
+        Task { await DeletedVideosStore.shared.unhideAll() }
+    }
+
+    func deletePermanently(_ asset: PHAsset) {
+        Task {
+            do {
+                try await DeletedVideosStore.shared.purge(ids: [asset.localIdentifier])
+            } catch {
+                await MainActor.run {
+                    self.errorMessage = error.localizedDescription
+                }
+            }
+        }
+    }
+
+    func deleteAllPermanently() {
+        Task {
+            do {
+                try await DeletedVideosStore.shared.purge(ids: ids)
+            } catch {
+                await MainActor.run {
+                    self.errorMessage = error.localizedDescription
+                }
+            }
+        }
+    }
+}
+
+struct DeletedVideosView: View {
+    @StateObject private var model = DeletedVideosViewModel()
+    @Environment(\.dismiss) private var dismiss
+    @State private var showingDeleteAllConfirm = false
+
+    var body: some View {
+        List {
+            if model.isLoading {
+                ProgressView()
+                    .frame(maxWidth: .infinity)
+            } else if model.assets.isEmpty {
+                VStack(spacing: 8) {
+                    Image(systemName: "trash")
+                        .font(.system(size: 40))
+                        .foregroundStyle(.secondary)
+                    Text("No deleted videos")
+                        .font(.headline)
+                    Text("Videos you hide will appear here. You can restore them or delete them permanently.")
+                        .font(.subheadline)
+                        .multilineTextAlignment(.center)
+                        .foregroundStyle(.secondary)
+                        .padding(.horizontal)
+                }
+                .frame(maxWidth: .infinity)
+                .listRowBackground(Color.clear)
+            } else {
+                ForEach(model.assets, id: \.localIdentifier) { asset in
+                    DeletedRow(asset: asset)
+                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
+                            Button(role: .destructive) {
+                                model.deletePermanently(asset)
+                            } label: {
+                                Label("Delete", systemImage: "trash")
+                            }
+                            Button {
+                                model.restore(asset)
+                            } label: {
+                                Label("Restore", systemImage: "arrow.uturn.backward")
+                            }
+                            .tint(.green)
+                        }
+                }
+            }
+        }
+        .navigationTitle("Deleted videos")
+        .toolbar {
+            ToolbarItem(placement: .topBarLeading) {
+                Button("Restore All") {
+                    model.restoreAll()
+                }
+                .disabled(model.assets.isEmpty)
+            }
+            ToolbarItem(placement: .topBarTrailing) {
+                Button("Delete All") {
+                    showingDeleteAllConfirm = true
+                }
+                .disabled(model.assets.isEmpty)
+            }
+        }
+        .alert("Delete all permanently?", isPresented: $showingDeleteAllConfirm) {
+            Button("Delete All", role: .destructive) {
+                model.deleteAllPermanently()
+            }
+            Button("Cancel", role: .cancel) {}
+        } message: {
+            Text("This will delete the videos from your Photos library and cannot be undone.")
+        }
+        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { _ in model.errorMessage = nil })) {
+            Button("OK", role: .cancel) {}
+        } message: {
+            Text(model.errorMessage ?? "")
+        }
+    }
+}
+
+private struct DeletedRow: View {
+    let asset: PHAsset
+    @State private var image: UIImage?
+    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID
+
+    var body: some View {
+        HStack(spacing: 12) {
+            ZStack(alignment: .bottomTrailing) {
+                Group {
+                    if let image {
+                        Image(uiImage: image)
+                            .resizable()
+                            .scaledToFill()
+                    } else {
+                        Color.gray.opacity(0.18)
+                            .overlay(ProgressView())
+                    }
+                }
+                .frame(width: 72, height: 72)
+                .clipShape(RoundedRectangle(cornerRadius: 8))
+
+                if asset.mediaType == .video {
+                    Image(systemName: "play.circle.fill")
+                        .foregroundStyle(.white)
+                        .shadow(radius: 3)
+                        .padding(4)
+                }
+            }
+
+            VStack(alignment: .leading, spacing: 4) {
+                Text(dateString(asset.creationDate))
+                    .font(.headline)
+                if asset.mediaType == .video {
+                    Text(durationString(asset.duration))
+                        .font(.caption)
+                        .foregroundStyle(.secondary)
+                }
+                Text(asset.localIdentifier)
+                    .font(.caption2)
+                    .foregroundStyle(.secondary)
+                    .lineLimit(1)
+            }
+        }
+        .onAppear { loadThumb() }
+        .onDisappear { cancelThumb() }
+    }
+
+    private func loadThumb() {
+        cancelThumb()
+        let options = PHImageRequestOptions()
+        options.deliveryMode = .fastFormat
+        options.resizeMode = .fast
+        options.isNetworkAccessAllowed = true
+        requestID = PHImageManager.default().requestImage(for: asset,
+                                                          targetSize: CGSize(width: 160, height: 160),
+                                                          contentMode: .aspectFill,
+                                                          options: options) { img, _ in
+            if let img { self.image = img }
+        }
+    }
+
+    private func cancelThumb() {
+        if requestID != PHInvalidImageRequestID {
+            PHImageManager.default().cancelImageRequest(requestID)
+            requestID = PHInvalidImageRequestID
+        }
+    }
+
+    private func dateString(_ d: Date?) -> String {
+        guard let d else { return "Unknown date" }
+        let df = DateFormatter()
+        df.dateStyle = .medium
+        df.timeStyle = .none
+        return df.string(from: d)
+    }
+
+    private func durationString(_ seconds: TimeInterval) -> String {
+        let total = Int(seconds.rounded())
+        let h = total / 3600
+        let m = (total % 3600) / 60
+        let s = total % 60
+        if h > 0 {
+            return String(format: "%d:%02d:%02d", h, m, s)
+        } else {
+            return String(format: "%d:%02d", m, s)
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/Diagnostics.swift b/Video Feed Test/Diagnostics.swift
new file mode 100644
index 0000000..8381865
--- /dev/null
+++ b/Video Feed Test/Diagnostics.swift	
@@ -0,0 +1,227 @@
+//
+//  Diagnostics.swift
+//  Video Feed Test
+//
+//  Created by Alex (AI) on 10/1/25.
+//
+
+import Foundation
+import AVFoundation
+import os
+import os.signpost
+import Photos
+import QuartzCore
+
+enum Diagnostics {
+    static let logger = Logger(subsystem: "VideoFeedTest", category: "Diagnostics")
+    static let signpostLog = OSLog(subsystem: "VideoFeedTest", category: "Signpost")
+
+    @discardableResult
+    static func signpostBegin(_ name: StaticString, id: inout OSSignpostID?) -> OSSignpostID {
+        let sid = id ?? OSSignpostID(log: signpostLog)
+        os_signpost(.begin, log: signpostLog, name: name, signpostID: sid)
+        id = sid
+        return sid
+    }
+
+    static func signpostEnd(_ name: StaticString, id: OSSignpostID?) {
+        guard let sid = id else { return }
+        os_signpost(.end, log: signpostLog, name: name, signpostID: sid)
+    }
+
+    static func log(_ message: String) {
+        logger.debug("\(message, privacy: .public)")
+    }
+}
+
+@MainActor
+final class PlayerLeakDetector {
+    static let shared = PlayerLeakDetector()
+
+    private let probes = NSHashTable<PlayerProbe>.weakObjects()
+
+    func register(_ probe: PlayerProbe) {
+        probes.add(probe)
+    }
+
+    func unregister(_ probe: PlayerProbe) {
+        probes.remove(probe)
+    }
+
+    @discardableResult
+    func snapshotActive(log: Bool) -> [(context: String, assetID: String, status: AVPlayer.TimeControlStatus, time: CMTime)] {
+        let list: [(context: String, assetID: String, status: AVPlayer.TimeControlStatus, time: CMTime)] = probes.allObjects.map { probe in
+            (context: probe.context, assetID: probe.assetID, status: probe.player.timeControlStatus, time: probe.player.currentTime())
+        }
+        if log {
+            if list.isEmpty {
+                Diagnostics.log("LeakDetector: No active players")
+            } else {
+                Diagnostics.log("LeakDetector: Active players count=\(list.count)")
+                for e in list {
+                    Diagnostics.log("LeakDetector: [\(e.context)] asset=\(e.assetID) status=\(String(describing: e.status)) t=\(CMTimeGetSeconds(e.time))s")
+                }
+            }
+        }
+        return list
+    }
+}
+
+@MainActor
+final class PlayerProbe {
+    let player: AVPlayer
+    let context: String
+    let assetID: String
+
+    private var timeControlObs: NSKeyValueObservation?
+    private var rateObs: NSKeyValueObservation?
+    private var itemStatusObs: NSKeyValueObservation?
+    private var itemLikelyObs: NSKeyValueObservation?
+    private var itemEmptyObs: NSKeyValueObservation?
+    private var itemFullObs: NSKeyValueObservation?
+    private var timeObs: Any?
+    private var firstFrameLogged = false
+
+    private var phaseID: OSSignpostID?
+    private var t0: CFTimeInterval = 0
+
+    init(player: AVPlayer, context: String, assetID: String) {
+        self.player = player
+        self.context = context
+        self.assetID = assetID
+        PlayerLeakDetector.shared.register(self)
+        attachPlayerObservers()
+    }
+
+    deinit {
+        // Avoid main-actor calls here to keep Swift 6 happy.
+        // Observations use weak self; player timeObserver closure uses weak self.
+        // We explicitly nil out probes from owners when tearing down.
+    }
+
+    func startPhase(_ name: StaticString) {
+        t0 = CACurrentMediaTime()
+        Diagnostics.signpostBegin(name, id: &phaseID)
+        Diagnostics.log("[\(context)] asset=\(assetID) phase begin: \(name)")
+    }
+
+    func endPhase(_ name: StaticString) {
+        let dt = CACurrentMediaTime() - t0
+        Diagnostics.signpostEnd(name, id: phaseID)
+        Diagnostics.log("[\(context)] asset=\(assetID) phase end: \(name) dt=\(String(format: "%.3f", dt))s")
+        phaseID = nil
+        t0 = 0
+    }
+
+    func attach(item: AVPlayerItem) {
+        itemStatusObs = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
+            Task { @MainActor [weak self] in
+                guard let self else { return }
+                Diagnostics.log("[\(self.context)] asset=\(self.assetID) item.status=\(String(describing: item.status.rawValue)) error=\(String(describing: item.error?.localizedDescription))")
+                if item.status == .readyToPlay {
+                    self.logLoadedTimeRanges(item)
+                }
+            }
+        }
+        itemLikelyObs = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
+            Task { @MainActor [weak self] in
+                guard let self else { return }
+                Diagnostics.log("[\(self.context)] asset=\(self.assetID) isPlaybackLikelyToKeepUp=\(item.isPlaybackLikelyToKeepUp)")
+            }
+        }
+        itemEmptyObs = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] item, _ in
+            Task { @MainActor [weak self] in
+                guard let self else { return }
+                Diagnostics.log("[\(self.context)] asset=\(self.assetID) isPlaybackBufferEmpty=\(item.isPlaybackBufferEmpty)")
+            }
+        }
+        itemFullObs = item.observe(\.isPlaybackBufferFull, options: [.initial, .new]) { [weak self] item, _ in
+            Task { @MainActor [weak self] in
+                guard let self else { return }
+                Diagnostics.log("[\(self.context)] asset=\(self.assetID) isPlaybackBufferFull=\(item.isPlaybackBufferFull)")
+            }
+        }
+        installFirstFrameTimeObserver()
+    }
+
+    func detach() {
+        if let timeObs {
+            player.removeTimeObserver(timeObs)
+            self.timeObs = nil
+        }
+        timeControlObs = nil
+        rateObs = nil
+        itemStatusObs = nil
+        itemLikelyObs = nil
+        itemEmptyObs = nil
+        itemFullObs = nil
+        PlayerLeakDetector.shared.unregister(self)
+    }
+
+    private func attachPlayerObservers() {
+        timeControlObs = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
+            Task { @MainActor [weak self] in
+                guard let self else { return }
+                let reason = player.reasonForWaitingToPlay?.rawValue ?? "nil"
+                Diagnostics.log("[\(self.context)] asset=\(self.assetID) timeControlStatus=\(String(describing: player.timeControlStatus)) reason=\(reason)")
+                if let item = player.currentItem {
+                    self.logLoadedTimeRanges(item)
+                }
+            }
+        }
+        rateObs = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
+            Task { @MainActor [weak self] in
+                guard let self else { return }
+                Diagnostics.log("[\(self.context)] asset=\(self.assetID) rate=\(player.rate)")
+            }
+        }
+    }
+
+    private func installFirstFrameTimeObserver() {
+        firstFrameLogged = false
+        timeObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
+            Task { @MainActor [weak self] in
+                guard let self else { return }
+                if !self.firstFrameLogged, t.seconds > 0 {
+                    self.firstFrameLogged = true
+                    Diagnostics.log("[\(self.context)] asset=\(self.assetID) firstTimeObserved=\(String(format: "%.3f", t.seconds))s since start=\(String(format: "%.3f", CACurrentMediaTime() - self.t0))s")
+                }
+            }
+        }
+    }
+
+    private func logLoadedTimeRanges(_ item: AVPlayerItem) {
+        let ranges = item.loadedTimeRanges.compactMap { $0.timeRangeValue }
+        let desc = ranges.map { r in
+            let start = CMTimeGetSeconds(r.start)
+            let dur = CMTimeGetSeconds(r.duration)
+            return "[start=\(String(format: "%.2f", start)), dur=\(String(format: "%.2f", dur))]"
+        }.joined(separator: ", ")
+        Diagnostics.log("[\(context)] asset=\(assetID) loadedTimeRanges=\(desc)")
+    }
+}
+
+extension PHAsset {
+    var diagSummary: String {
+        "id=\(localIdentifier) dur=\(String(format: "%.2f", duration))s size=\(pixelWidth)x\(pixelHeight)"
+    }
+}
+
+struct PhotoKitDiagnostics {
+    static func logResultInfo(prefix: String, info: [AnyHashable: Any]?) {
+        guard let info else {
+            Diagnostics.log("\(prefix) info=nil")
+            return
+        }
+        let inCloud = (info[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
+        let cancelled = (info[PHImageCancelledKey] as? NSNumber)?.boolValue ?? false
+        let error = (info[PHImageErrorKey] as? NSError)
+        let keysDesc = Array(info.keys).map { "\($0)" }.joined(separator: ",")
+        Diagnostics.log("\(prefix) info: inCloud=\(inCloud) cancelled=\(cancelled) error=\(String(describing: error?.localizedDescription)) keys=\(keysDesc)")
+    }
+}
+
+extension Notification.Name {
+    static let videoPrefetcherDidCacheAsset = Notification.Name("VideoPrefetcherDidCacheAsset")
+    static let videoPlaybackItemReady = Notification.Name("VideoPlaybackItemReady")
+}
\ No newline at end of file
diff --git a/Video Feed Test/DownloadOverlayView.swift b/Video Feed Test/DownloadOverlayView.swift
new file mode 100644
index 0000000..1422575
--- /dev/null
+++ b/Video Feed Test/DownloadOverlayView.swift	
@@ -0,0 +1,122 @@
+import SwiftUI
+
+struct DownloadOverlayView: View {
+    @ObservedObject private var tracker = DownloadTracker.shared
+    @ObservedObject private var playback = CurrentPlayback.shared
+
+    private var averageRatePercentPerSec: Double? {
+        let rates = tracker.entries.filter { !$0.isComplete && !$0.isFailed }.compactMap { $0.progressRatePercentPerSec }
+        guard !rates.isEmpty else { return nil }
+        let sum = rates.reduce(0, +)
+        return sum / Double(rates.count)
+    }
+    
+    var body: some View {
+        VStack(spacing: 6) {
+            HStack {
+                Text("Active: \(tracker.entries.filter { !$0.isComplete && !$0.isFailed }.count)")
+                    .font(.caption)
+                if let avg = averageRatePercentPerSec, avg.isFinite {
+                    Text(String(format: "Avg: %.1f%%/s", avg))
+                        .font(.caption)
+                        .foregroundStyle(.secondary)
+                }
+                Spacer()
+                Text("Downloads")
+                    .font(.caption)
+                    .foregroundStyle(.secondary)
+            }
+            .padding(.horizontal, 10)
+            .padding(.top, 8)
+            
+            Divider().opacity(0.25)
+            
+            ScrollViewReader { proxy in
+                ScrollView {
+                    LazyVStack(alignment: .leading, spacing: 6) {
+                        ForEach(tracker.entries) { e in
+                            HStack(spacing: 8) {
+                                VStack(alignment: .leading, spacing: 2) {
+                                    Text(shortID(e.id))
+                                        .font(.caption2)
+                                        .foregroundStyle(.secondary)
+                                    Text(e.title)
+                                        .font(.caption2)
+                                        .lineLimit(1)
+                                        .foregroundStyle(e.isFailed ? .red : .primary)
+                                    if let note = e.note, !note.isEmpty {
+                                        Text(note)
+                                            .font(.caption2)
+                                            .foregroundStyle(.secondary)
+                                            .lineLimit(1)
+                                    }
+                                }
+                                Spacer()
+                                if e.isComplete {
+                                    HStack(spacing: 4) {
+                                        Image(systemName: "checkmark.circle.fill")
+                                            .foregroundStyle(.green)
+                                        Text("Ready")
+                                            .font(.caption2)
+                                            .foregroundStyle(.green)
+                                    }
+                                } else {
+                                    VStack(alignment: .trailing, spacing: 2) {
+                                        Text("\(Int(e.progress * 100))%")
+                                            .font(.caption2)
+                                            .monospacedDigit()
+                                        if let r = e.progressRatePercentPerSec, r.isFinite {
+                                            Text(String(format: "%.1f%%/s", r))
+                                                .font(.caption2)
+                                                .foregroundStyle(.secondary)
+                                        }
+                                    }
+                                }
+                            }
+                            .id(e.id)
+                            .padding(6)
+                            .background(playback.currentAssetID == e.id ? Color.white.opacity(0.08) : Color.clear)
+                            .cornerRadius(8)
+                        }
+                    }
+                    .padding(.horizontal, 10)
+                    .padding(.bottom, 8)
+                }
+                .frame(maxHeight: 160)
+                .onAppear {
+                    if let current = playback.currentAssetID {
+                        withAnimation {
+                            proxy.scrollTo(current, anchor: .center)
+                        }
+                    }
+                }
+                .onChange(of: playback.currentAssetID) { _, current in
+                    if let current {
+                        withAnimation {
+                            proxy.scrollTo(current, anchor: .center)
+                        }
+                    }
+                }
+                .onChange(of: tracker.entries.map(\.id)) { _, _ in
+                    if let current = playback.currentAssetID {
+                        withAnimation {
+                            proxy.scrollTo(current, anchor: .center)
+                        }
+                    }
+                }
+            }
+        }
+        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
+        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
+        .padding(.horizontal, 8)
+        .padding(.top, 8)
+        .animation(.easeInOut(duration: 0.2), value: playback.currentAssetID)
+    }
+    
+    private func shortID(_ id: String) -> String {
+        if id.count <= 6 { return id }
+        let start = id.prefix(4)
+        let end = id.suffix(3)
+        return "\(start)…\(end)"
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/DownloadTracker.swift b/Video Feed Test/DownloadTracker.swift
new file mode 100644
index 0000000..2b057b4
--- /dev/null
+++ b/Video Feed Test/DownloadTracker.swift	
@@ -0,0 +1,133 @@
+import Foundation
+import SwiftUI
+import Combine
+
+@MainActor
+final class DownloadTracker: ObservableObject {
+    static let shared = DownloadTracker()
+
+    enum Phase: String, Codable, Hashable {
+        case prefetch
+        case playerItem
+        case ready
+    }
+
+    struct Entry: Identifiable {
+        let id: String
+        var phase: Phase
+        var title: String
+        var progress: Double
+        var progressRatePercentPerSec: Double?
+        var lastUpdate: Date
+        var isComplete: Bool
+        var isFailed: Bool
+        var note: String?
+        let createdAt: Date
+        let seq: Int
+    }
+
+    @Published private(set) var entries: [Entry] = []
+
+    private var lastProgressSnapshot: [String: (progress: Double, time: Date)] = [:]
+    private let maxEntries = 50
+    private var seqCounter = 0
+
+    private init() {}
+
+    func updateProgress(for id: String, phase: Phase, progress: Double, note: String? = nil) {
+        let clamped = min(max(progress, 0), 1)
+        let now = Date()
+
+        let idx = ensureEntry(id, phase: phase, title: phase.rawValue)
+
+        let prev = lastProgressSnapshot[id] ?? (entries[idx].progress, entries[idx].lastUpdate)
+        let dt = now.timeIntervalSince(prev.time)
+        let ratePctPerSec = dt > 0 ? ((clamped - prev.progress) * 100.0) / dt : nil
+
+        entries[idx].phase = phase
+        entries[idx].title = phase.rawValue
+        entries[idx].progress = clamped
+        entries[idx].progressRatePercentPerSec = ratePctPerSec
+        entries[idx].lastUpdate = now
+        entries[idx].isFailed = false
+        entries[idx].note = note
+
+        if phase == .ready {
+            entries[idx].isComplete = true
+            entries[idx].progress = 1.0
+            entries[idx].progressRatePercentPerSec = nil
+        }
+
+        lastProgressSnapshot[id] = (entries[idx].progress, now)
+        trimIfNeeded()
+    }
+
+    func markPlaybackReady(id: String) {
+        let idx = ensureEntry(id, phase: .ready, title: Phase.ready.rawValue)
+        entries[idx].phase = .ready
+        entries[idx].title = Phase.ready.rawValue
+        entries[idx].progress = 1.0
+        entries[idx].isComplete = true
+        entries[idx].isFailed = false
+        entries[idx].progressRatePercentPerSec = nil
+        entries[idx].lastUpdate = Date()
+        lastProgressSnapshot[id] = (1.0, Date())
+        trimIfNeeded()
+    }
+
+    func markComplete(id: String) {
+        markPlaybackReady(id: id)
+    }
+
+    func markFailed(id: String, note: String? = nil) {
+        if let i = entries.firstIndex(where: { $0.id == id }) {
+            entries[i].isFailed = true
+            entries[i].lastUpdate = Date()
+            entries[i].note = note
+            lastProgressSnapshot[id] = (entries[i].progress, Date())
+        } else {
+            let now = Date()
+            let e = Entry(id: id,
+                          phase: .prefetch,
+                          title: "Request",
+                          progress: 0,
+                          progressRatePercentPerSec: nil,
+                          lastUpdate: now,
+                          isComplete: false,
+                          isFailed: true,
+                          note: note,
+                          createdAt: now,
+                          seq: seqCounter)
+            seqCounter &+= 1
+            entries.append(e)
+        }
+        trimIfNeeded()
+    }
+
+    private func trimIfNeeded() {
+        if entries.count > maxEntries {
+            entries.removeFirst(entries.count - maxEntries)
+        }
+    }
+
+    private func ensureEntry(_ id: String, phase: Phase, title: String) -> Int {
+        if let idx = entries.firstIndex(where: { $0.id == id }) {
+            return idx
+        }
+        let now = Date()
+        let e = Entry(id: id,
+                      phase: phase,
+                      title: title,
+                      progress: 0,
+                      progressRatePercentPerSec: nil,
+                      lastUpdate: now,
+                      isComplete: false,
+                      isFailed: false,
+                      note: nil,
+                      createdAt: now,
+                      seq: seqCounter)
+        seqCounter &+= 1
+        entries.append(e)
+        return entries.count - 1
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/FPSMonitor.swift b/Video Feed Test/FPSMonitor.swift
new file mode 100644
index 0000000..9c69673
--- /dev/null
+++ b/Video Feed Test/FPSMonitor.swift	
@@ -0,0 +1,72 @@
+import Foundation
+import QuartzCore
+import Combine
+import UIKit
+
+@MainActor
+final class FPSMonitor: ObservableObject {
+    static let shared = FPSMonitor()
+
+    @Published private(set) var fps: Double = 0
+
+    private var link: CADisplayLink?
+    private var lastTimestamp: CFTimeInterval = 0
+    private var frameCount: Int = 0
+    private var windowStart: CFTimeInterval = 0
+
+    private init() {}
+
+    func start() {
+        guard link == nil else { return }
+        lastTimestamp = 0
+        frameCount = 0
+        windowStart = CACurrentMediaTime()
+        let proxy = DisplayLinkProxy { [weak self] ts in
+            self?.step(ts: ts)
+        }
+        let l = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
+        proxy.ownerLink = l
+        l.add(to: .main, forMode: .common)
+        link = l
+    }
+
+    func stop() {
+        link?.invalidate()
+        link = nil
+    }
+
+    private func step(ts: CFTimeInterval) {
+        if lastTimestamp == 0 {
+            lastTimestamp = ts
+            windowStart = ts
+            return
+        }
+        frameCount &+= 1
+        let dt = ts - windowStart
+        if dt >= 1.0 {
+            let value = Double(frameCount) / dt
+            fps = min(120, max(0, value))
+            frameCount = 0
+            windowStart = ts
+        }
+        lastTimestamp = ts
+    }
+}
+
+@MainActor
+private final class DisplayLinkProxy: NSObject {
+    var callback: (CFTimeInterval) -> Void
+    weak var ownerLink: CADisplayLink?
+
+    init(callback: @escaping (CFTimeInterval) -> Void) {
+        self.callback = callback
+    }
+
+    @objc func tick(_ sender: CADisplayLink) {
+        callback(sender.timestamp)
+    }
+
+    deinit {
+        ownerLink?.invalidate()
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/FeatureFlags.swift b/Video Feed Test/FeatureFlags.swift
new file mode 100644
index 0000000..082205b
--- /dev/null
+++ b/Video Feed Test/FeatureFlags.swift	
@@ -0,0 +1,5 @@
+import Foundation
+
+enum FeatureFlags {
+    static let enablePhotoPosts: Bool = false
+}
\ No newline at end of file
diff --git a/Video Feed Test/FeedItem.swift b/Video Feed Test/FeedItem.swift
new file mode 100644
index 0000000..75eaa42
--- /dev/null
+++ b/Video Feed Test/FeedItem.swift	
@@ -0,0 +1,18 @@
+import Photos
+
+struct FeedItem {
+    enum Kind {
+        case video(PHAsset)
+        case photoCarousel([PHAsset])
+    }
+    let id: String
+    let kind: Kind
+    
+    static func video(_ asset: PHAsset) -> FeedItem {
+        FeedItem(id: "v:\(asset.localIdentifier)", kind: .video(asset))
+    }
+    static func carousel(_ assets: [PHAsset]) -> FeedItem {
+        let first = assets.first?.localIdentifier ?? UUID().uuidString
+        return FeedItem(id: "c:\(first):\(assets.count)", kind: .photoCarousel(assets))
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/GlassBackgroundCompat.swift b/Video Feed Test/GlassBackgroundCompat.swift
new file mode 100644
index 0000000..97c1423
--- /dev/null
+++ b/Video Feed Test/GlassBackgroundCompat.swift	
@@ -0,0 +1,30 @@
+import SwiftUI
+
+extension View {
+    @ViewBuilder
+    func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
+        liquidGlass(in: shape, stroke: true)
+    }
+
+    @ViewBuilder
+    func liquidGlass<S: InsettableShape>(in shape: S, stroke: Bool) -> some View {
+        if #available(iOS 18.0, *) {
+            self.glassEffect(.clear, in: shape)
+        } else {
+            self
+                .background(.ultraThinMaterial, in: shape)
+                .overlay {
+                    if stroke {
+                        shape.stroke(Color.white.opacity(0.15), lineWidth: 1)
+                    }
+                }
+        }
+    }
+}
+
+@available(iOS 18.0, *)
+private extension View {
+    func _liquidGlass18<S: InsettableShape>(in shape: S) -> some View {
+        self.glassEffect(.clear, in: shape)
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/GoogleAuth.swift b/Video Feed Test/GoogleAuth.swift
new file mode 100644
index 0000000..5badd0a
--- /dev/null
+++ b/Video Feed Test/GoogleAuth.swift	
@@ -0,0 +1,325 @@
+import Foundation
+import AuthenticationServices
+import UIKit
+
+struct GoogleOAuthConfig {
+    private static let placeholder = "YOUR_IOS_CLIENT_ID.apps.googleusercontent.com"
+
+    static var clientID: String {
+        if let id = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
+           !id.isEmpty { return id }
+        return placeholder
+    }
+
+    private static var redirectURIOverride: String? {
+        if let r = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_REDIRECT_URI") as? String,
+           !r.isEmpty { return r }
+        return nil
+    }
+
+    static var scopes: [String] = [
+        "openid",
+        "email",
+        "https://www.googleapis.com/auth/youtube.readonly"
+    ]
+    static var tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
+    static var authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
+
+    static var redirectScheme: String {
+        if let override = redirectURIOverride,
+           let scheme = URL(string: override)?.scheme,
+           !scheme.isEmpty {
+            return scheme
+        }
+        let base = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
+        return "com.googleusercontent.apps.\(base)"
+    }
+
+    static var redirectURI: String {
+        if let override = redirectURIOverride { return override }
+        return "\(redirectScheme):/oauthredirect"
+    }
+
+    static var isConfigured: Bool {
+        clientID != placeholder
+    }
+}
+
+struct GoogleTokens: Codable {
+    var accessToken: String
+    var expiresAt: Date
+    var refreshToken: String?
+
+    var isExpired: Bool {
+        Date() >= expiresAt.addingTimeInterval(-60)
+    }
+}
+
+actor GoogleAuth {
+    static let shared = GoogleAuth()
+
+    private let keychain = KeychainStore(service: "VideoFeedTest.Google")
+    private let tokenKey = "google.tokens"
+
+    private var tokens: GoogleTokens?
+
+    @MainActor private static var currentSession: ASWebAuthenticationSession?
+    @MainActor private static let sharedPresenter = WebAuthPresenter()
+
+    var isReady: Bool {
+        GoogleOAuthConfig.isConfigured
+    }
+
+    func restore() async -> Bool {
+        if let data = try? keychain.getData(key: tokenKey),
+           let t = try? JSONDecoder().decode(GoogleTokens.self, from: data) {
+            Diagnostics.log("GoogleAuth.restore: found tokens; expired=\(t.isExpired) hasRefresh=\(t.refreshToken != nil)")
+            if t.isExpired && t.refreshToken == nil {
+                Diagnostics.log("GoogleAuth.restore: tokens expired and no refresh_token; ignoring stored tokens")
+                tokens = nil
+                return false
+            }
+            tokens = t
+            return true
+        }
+        Diagnostics.log("GoogleAuth.restore: no stored tokens")
+        return false
+    }
+
+    func signIn() async throws -> Bool {
+        guard isReady else {
+            Diagnostics.log("GoogleAuth.signIn: not ready (missing clientID/redirect)")
+            return false
+        }
+
+        let state = UUID().uuidString
+        let codeVerifier = Self.randomString(64)
+        let codeChallenge = Self.base64url(Data(Self.sha256(codeVerifier)))
+
+        var comps = URLComponents(url: GoogleOAuthConfig.authURL, resolvingAgainstBaseURL: false)!
+        comps.queryItems = [
+            .init(name: "client_id", value: GoogleOAuthConfig.clientID),
+            .init(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
+            .init(name: "response_type", value: "code"),
+            .init(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
+            .init(name: "access_type", value: "offline"),
+            .init(name: "include_granted_scopes", value: "true"),
+            .init(name: "state", value: state),
+            .init(name: "code_challenge", value: codeChallenge),
+            .init(name: "code_challenge_method", value: "S256"),
+            .init(name: "prompt", value: "consent")
+        ]
+
+        let callbackScheme = GoogleOAuthConfig.redirectScheme
+
+        let url = comps.url!
+        Diagnostics.log("GoogleAuth.signIn: starting ASWebAuthenticationSession; redirect=\(GoogleOAuthConfig.redirectURI)")
+        let (callbackURL, returnedState) = try await Self.startWebAuth(url: url, callbackScheme: callbackScheme)
+        Diagnostics.log("GoogleAuth.signIn: got callbackURL")
+        guard returnedState == state else {
+            Diagnostics.log("GoogleAuth.signIn: state mismatch")
+            throw NSError(domain: "GoogleAuth", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid state"])
+        }
+
+        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
+            .queryItems?.first(where: { $0.name == "code" })?.value else {
+            Diagnostics.log("GoogleAuth.signIn: missing code in callback")
+            throw NSError(domain: "GoogleAuth", code: -11, userInfo: [NSLocalizedDescriptionKey: "Missing code"])
+        }
+
+        let newTokens = try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
+        Diagnostics.log("GoogleAuth.signIn: token exchange ok; hasRefresh=\(newTokens.refreshToken != nil)")
+        tokens = newTokens
+        try persist(tokens: newTokens)
+        return true
+    }
+
+    func signOut() async {
+        Diagnostics.log("GoogleAuth.signOut: clearing tokens")
+        tokens = nil
+        try? keychain.delete(key: tokenKey)
+    }
+
+    func validAccessToken() async throws -> String {
+        if let t = tokens {
+            Diagnostics.log("GoogleAuth.validAccessToken: have tokens; expired=\(t.isExpired) hasRefresh=\(t.refreshToken != nil)")
+        } else {
+            Diagnostics.log("GoogleAuth.validAccessToken: no tokens loaded")
+        }
+
+        if let t = tokens, !t.isExpired {
+            return t.accessToken
+        }
+        if let refreshed = try await refreshTokensIfNeeded() {
+            return refreshed.accessToken
+        }
+        Diagnostics.log("GoogleAuth.validAccessToken: not signed in (no token / no refresh)")
+        throw NSError(domain: "GoogleAuth", code: -20, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
+    }
+
+    // MARK: - Internals
+
+    private func refreshTokensIfNeeded() async throws -> GoogleTokens? {
+        guard var t = tokens else {
+            Diagnostics.log("GoogleAuth.refresh: no tokens to refresh")
+            return nil
+        }
+        guard t.isExpired, let refresh = t.refreshToken else {
+            Diagnostics.log("GoogleAuth.refresh: not needed or no refresh token")
+            return nil
+        }
+
+        Diagnostics.log("GoogleAuth.refresh: attempting refresh_token grant")
+        var req = URLRequest(url: GoogleOAuthConfig.tokenURL)
+        req.httpMethod = "POST"
+        let body: [String: String] = [
+            "client_id": GoogleOAuthConfig.clientID,
+            "grant_type": "refresh_token",
+            "refresh_token": refresh
+        ]
+        req.httpBody = body
+            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
+            .joined(separator: "&")
+            .data(using: .utf8)
+        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
+
+        let (data, resp) = try await URLSession.shared.data(for: req)
+        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
+        guard status == 200 else {
+            let text = String(data: data, encoding: .utf8) ?? ""
+            Diagnostics.log("GoogleAuth.refresh: failed status=\(status) body=\(text)")
+            throw NSError(domain: "GoogleAuth", code: -22, userInfo: [NSLocalizedDescriptionKey: "Refresh failed"])
+        }
+        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
+        guard let access = payload?["access_token"] as? String,
+              let expires = payload?["expires_in"] as? Double else {
+            Diagnostics.log("GoogleAuth.refresh: bad payload")
+            throw NSError(domain: "GoogleAuth", code: -23, userInfo: [NSLocalizedDescriptionKey: "Bad token response"])
+        }
+        t.accessToken = access
+        t.expiresAt = Date().addingTimeInterval(expires)
+        tokens = t
+        try persist(tokens: t)
+        Diagnostics.log("GoogleAuth.refresh: success; new expiry set")
+        return t
+    }
+
+    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> GoogleTokens {
+        var req = URLRequest(url: GoogleOAuthConfig.tokenURL)
+        req.httpMethod = "POST"
+        let body: [String: String] = [
+            "client_id": GoogleOAuthConfig.clientID,
+            "code": code,
+            "code_verifier": codeVerifier,
+            "grant_type": "authorization_code",
+            "redirect_uri": GoogleOAuthConfig.redirectURI
+        ]
+        req.httpBody = body
+            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
+            .joined(separator: "&")
+            .data(using: .utf8)
+        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
+
+        let (data, resp) = try await URLSession.shared.data(for: req)
+        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
+        guard status == 200 else {
+            let text = String(data: data, encoding: .utf8) ?? ""
+            Diagnostics.log("GoogleAuth.exchange: token exchange failed status=\(status) body=\(text)")
+            throw NSError(domain: "GoogleAuth", code: -12, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed"])
+        }
+        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
+        guard let access = payload?["access_token"] as? String,
+              let expires = payload?["expires_in"] as? Double else {
+            Diagnostics.log("GoogleAuth.exchange: invalid payload")
+            throw NSError(domain: "GoogleAuth", code: -13, userInfo: [NSLocalizedDescriptionKey: "Invalid token payload"])
+        }
+
+        let preservedRefresh = (payload?["refresh_token"] as? String) ?? self.tokens?.refreshToken
+        Diagnostics.log("GoogleAuth.exchange: hasRefresh=\(preservedRefresh != nil)")
+
+        return GoogleTokens(
+            accessToken: access,
+            expiresAt: Date().addingTimeInterval(expires),
+            refreshToken: preservedRefresh
+        )
+    }
+
+    private func persist(tokens: GoogleTokens) throws {
+        let data = try JSONEncoder().encode(tokens)
+        try keychain.setData(data, key: tokenKey)
+    }
+
+    @MainActor
+    private static func startWebAuth(url: URL, callbackScheme: String) async throws -> (URL, String) {
+        Diagnostics.log("GoogleAuth.webAuth: launching session")
+        return try await withCheckedThrowingContinuation { cont in
+            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
+                // Release session when finished
+                Self.currentSession = nil
+                if let error {
+                    Diagnostics.log("GoogleAuth.webAuth: error=\(error.localizedDescription)")
+                    return cont.resume(throwing: error)
+                }
+                guard let callback else {
+                    Diagnostics.log("GoogleAuth.webAuth: no callback URL")
+                    return cont.resume(throwing: NSError(domain: "GoogleAuth", code: -9, userInfo: [NSLocalizedDescriptionKey: "No callback URL"]))
+                }
+                let state = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
+                    .queryItems?.first(where: { $0.name == "state" })?.value ?? ""
+                Diagnostics.log("GoogleAuth.webAuth: callback received")
+                cont.resume(returning: (callback, state))
+            }
+            session.prefersEphemeralWebBrowserSession = false
+            session.presentationContextProvider = Self.sharedPresenter
+
+            let started = session.start()
+            Diagnostics.log("GoogleAuth.webAuth: session.start()=\(started)")
+            if started {
+                Self.currentSession = session
+            } else {
+                cont.resume(throwing: NSError(domain: "GoogleAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to start web auth session"]))
+            }
+        }
+    }
+
+    private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
+        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
+            UIApplication.shared.connectedScenes
+                .compactMap { $0 as? UIWindowScene }
+                .flatMap { $0.windows }
+                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
+        }
+    }
+
+    private static func randomString(_ len: Int) -> String {
+        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
+        var s = ""
+        s.reserveCapacity(len)
+        for _ in 0..<len { s.append(chars.randomElement()!) }
+        return s
+    }
+
+    private static func sha256(_ str: String) -> Data {
+        let data = Data(str.utf8)
+        return data.sha256()
+    }
+
+    private static func base64url(_ data: Data) -> String {
+        data.base64EncodedString()
+            .replacingOccurrences(of: "+", with: "-")
+            .replacingOccurrences(of: "/", with: "_")
+            .replacingOccurrences(of: "=", with: "")
+    }
+}
+
+private extension Data {
+    func sha256() -> Data {
+        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
+        self.withUnsafeBytes { buffer in
+            _ = CC_SHA256(buffer.baseAddress, CC_LONG(self.count), &hash)
+        }
+        return Data(hash)
+    }
+}
+
+import CommonCrypto
\ No newline at end of file
diff --git a/Video Feed Test/ImagePrefetcher.swift b/Video Feed Test/ImagePrefetcher.swift
new file mode 100644
index 0000000..59c40b2
--- /dev/null
+++ b/Video Feed Test/ImagePrefetcher.swift	
@@ -0,0 +1,51 @@
+import Foundation
+import Photos
+import UIKit
+
+@MainActor
+final class ImagePrefetcher {
+    static let shared = ImagePrefetcher()
+    private let manager = PHCachingImageManager()
+    private let options: PHImageRequestOptions = {
+        let o = PHImageRequestOptions()
+        o.deliveryMode = .highQualityFormat
+        o.resizeMode = .exact
+        o.isNetworkAccessAllowed = true
+        return o
+    }()
+
+    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
+        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
+        manager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
+    }
+
+    func stopPreheating(_ assets: [PHAsset], targetSize: CGSize) {
+        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
+        manager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
+    }
+
+    func requestImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
+        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
+            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
+                cont.resume(returning: image)
+            }
+        }
+    }
+
+    func progressiveImage(for asset: PHAsset, targetSize: CGSize) -> AsyncStream<(UIImage, Bool /* isDegraded */)> {
+        AsyncStream { continuation in
+            let requestID = manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
+                guard let image else { return }
+                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
+                continuation.yield((image, isDegraded))
+                if !isDegraded {
+                    continuation.finish()
+                }
+            }
+
+            continuation.onTermination = { _ in
+                self.manager.cancelImageRequest(requestID)
+            }
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/KeychainStore.swift b/Video Feed Test/KeychainStore.swift
new file mode 100644
index 0000000..86e2ade
--- /dev/null
+++ b/Video Feed Test/KeychainStore.swift	
@@ -0,0 +1,51 @@
+import Foundation
+import Security
+
+struct KeychainStore {
+    let service: String
+
+    func setData(_ data: Data, key: String) throws {
+        let query: [String: Any] = [
+            kSecClass as String: kSecClassGenericPassword,
+            kSecAttrService as String: service,
+            kSecAttrAccount as String: key
+        ]
+        SecItemDelete(query as CFDictionary)
+
+        var attrs = query
+        attrs[kSecValueData as String] = data
+
+        let status = SecItemAdd(attrs as CFDictionary, nil)
+        guard status == errSecSuccess else {
+            throw NSError(domain: "Keychain", code: Int(status), userInfo: nil)
+        }
+    }
+
+    func getData(key: String) throws -> Data {
+        let query: [String: Any] = [
+            kSecClass as String: kSecClassGenericPassword,
+            kSecAttrService as String: service,
+            kSecAttrAccount as String: key,
+            kSecReturnData as String: true,
+            kSecMatchLimit as String: kSecMatchLimitOne
+        ]
+        var item: CFTypeRef?
+        let status = SecItemCopyMatching(query as CFDictionary, &item)
+        guard status == errSecSuccess, let data = item as? Data else {
+            throw NSError(domain: "Keychain", code: Int(status), userInfo: nil)
+        }
+        return data
+    }
+
+    func delete(key: String) throws {
+        let query: [String: Any] = [
+            kSecClass as String: kSecClassGenericPassword,
+            kSecAttrService as String: service,
+            kSecAttrAccount as String: key
+        ]
+        let status = SecItemDelete(query as CFDictionary)
+        guard status == errSecSuccess || status == errSecItemNotFound else {
+            throw NSError(domain: "Keychain", code: Int(status), userInfo: nil)
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/MusicLibrary.swift b/Video Feed Test/MusicLibrary.swift
new file mode 100644
index 0000000..06a07d2
--- /dev/null
+++ b/Video Feed Test/MusicLibrary.swift	
@@ -0,0 +1,235 @@
+import Foundation
+import MediaPlayer
+import SwiftUI
+import Combine
+
+@MainActor
+final class MusicLibraryModel: ObservableObject {
+    @Published var authorization: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
+    @Published var isLoading = false
+    @Published var lastAdded: [MPMediaItem] = []
+
+    @Published var isGoogleConnected = false
+    @Published var isGoogleSyncing = false
+    @Published var googleStatusMessage: String?
+    @Published var catalogMatches: [AppleCatalogSong] = []
+    @Published var lastGoogleSyncAt: Date?
+
+    private var cancellables = Set<AnyCancellable>()
+
+    func bootstrap() {
+        authorization = MPMediaLibrary.authorizationStatus()
+        Diagnostics.log("MusicLibrary.bootstrap: auth=\(authorization.rawValue) starting restore")
+
+        Task { @MainActor in
+            let connected = await GoogleAuth.shared.restore()
+            Diagnostics.log("MusicLibrary.bootstrap: restore connected=\(connected)")
+            self.isGoogleConnected = connected
+            if connected {
+                await self.refreshGoogleLikes(limit: 15)
+            } else if authorization == .authorized, lastAdded.isEmpty {
+                self.loadLastAdded(limit: 15)
+            }
+        }
+    }
+
+    func requestAccessAndLoad() {
+        MPMediaLibrary.requestAuthorization { [weak self] status in
+            Task { @MainActor [weak self] in
+                guard let self else { return }
+                self.authorization = status
+                if status == .authorized, !self.isGoogleConnected {
+                    self.loadLastAdded(limit: 15)
+                }
+            }
+        }
+    }
+
+    func loadLastAdded(limit: Int = 15) {
+        isLoading = true
+        Task.detached(priority: .userInitiated) {
+            let items = MPMediaQuery.songs().items ?? []
+            let sorted = items.sorted { a, b in
+                a.dateAdded > b.dateAdded
+            }
+            let filtered = sorted.filter { $0.playbackDuration > 0.1 }
+            let picks = Array(filtered.prefix(limit))
+            await MainActor.run {
+                self.lastAdded = picks
+                self.isLoading = false
+            }
+        }
+    }
+
+    func connectGoogle() {
+        Task { @MainActor in
+            let ready = await GoogleAuth.shared.isReady
+            Diagnostics.log("MusicLibrary.connectGoogle: ready=\(ready)")
+            guard ready else {
+                self.googleStatusMessage = "Google not configured. Set GOOGLE_CLIENT_ID in Info.plist and add the reversed client ID URL scheme."
+                self.isGoogleConnected = false
+                return
+            }
+
+            isGoogleSyncing = true
+            googleStatusMessage = "Connecting Google…"
+            Diagnostics.log("MusicLibrary.connectGoogle: starting signIn()")
+            do {
+                let ok = try await GoogleAuth.shared.signIn()
+                Diagnostics.log("MusicLibrary.connectGoogle: signIn ok=\(ok)")
+                self.isGoogleConnected = ok
+                if ok {
+                    await self.refreshGoogleLikes(limit: 15)
+                } else {
+                    self.googleStatusMessage = "Google connection cancelled."
+                }
+            } catch {
+                Diagnostics.log("MusicLibrary.connectGoogle: signIn error=\(error.localizedDescription)")
+                self.googleStatusMessage = "Google sign-in failed: \(error.localizedDescription)"
+            }
+            isGoogleSyncing = false
+        }
+    }
+
+    func disconnectGoogle() {
+        Task { @MainActor in
+            Diagnostics.log("MusicLibrary.disconnectGoogle")
+            await GoogleAuth.shared.signOut()
+            isGoogleConnected = false
+            lastGoogleSyncAt = nil
+            googleStatusMessage = "Disconnected."
+            catalogMatches = []
+            if authorization == .authorized {
+                loadLastAdded(limit: 15)
+            } else {
+                lastAdded = []
+            }
+        }
+    }
+
+    func retryGoogleSync() {
+        Task { @MainActor in
+            guard isGoogleConnected, !isGoogleSyncing else {
+                Diagnostics.log("MusicLibrary.retryGoogleSync: ignored connected=\(isGoogleConnected) syncing=\(isGoogleSyncing)")
+                return
+            }
+            Diagnostics.log("MusicLibrary.retryGoogleSync: retrying")
+            googleStatusMessage = "Retrying sync…"
+            await refreshGoogleLikes(limit: 15)
+        }
+    }
+
+    func refreshGoogleLikes(limit: Int = 15) async {
+        isGoogleSyncing = true
+        googleStatusMessage = "Fetching YouTube likes…"
+        Diagnostics.log("MusicLibrary.refreshGoogleLikes: begin limit=\(limit)")
+        defer {
+            isGoogleSyncing = false
+            Diagnostics.log("MusicLibrary.refreshGoogleLikes: end")
+        }
+
+        guard await GoogleAuth.shared.isReady else {
+            Diagnostics.log("MusicLibrary.refreshGoogleLikes: Google not configured")
+            googleStatusMessage = "Google not configured. Set clientID and redirect URI."
+            if authorization == .authorized {
+                loadLastAdded(limit: limit)
+            }
+            return
+        }
+
+        func fetchAndMatch() async throws {
+            let tracks = try await YouTubeAPI.shared.fetchRecentLikedTracks(limit: 25)
+            Diagnostics.log("MusicLibrary.refreshGoogleLikes: fetched \(tracks.count) tracks")
+
+            if AppleMusicCatalog.isConfigured {
+                do {
+                    let catalog = try await AppleMusicCatalog.shared.match(tracks: tracks, limit: limit)
+                    Diagnostics.log("MusicLibrary.refreshGoogleLikes: catalog matches=\(catalog.count)")
+                    if !catalog.isEmpty {
+                        await MainActor.run {
+                            self.catalogMatches = catalog
+                            self.lastAdded = []
+                            self.googleStatusMessage = "Showing your latest likes from Apple Music."
+                            self.lastGoogleSyncAt = Date()
+                        }
+                        return
+                    }
+                } catch {
+                    Diagnostics.log("MusicLibrary.refreshGoogleLikes: catalog match error=\(error.localizedDescription)")
+                }
+            }
+
+            let matchedLocal = try await SongMatcher.shared.match(tracks: tracks, limit: limit)
+            Diagnostics.log("MusicLibrary.refreshGoogleLikes: local matches=\(matchedLocal.count)")
+            await MainActor.run {
+                if matchedLocal.isEmpty {
+                    self.googleStatusMessage = "No close matches found in Apple Music or your library."
+                    if self.authorization == .authorized {
+                        self.loadLastAdded(limit: limit)
+                    } else {
+                        self.lastAdded = []
+                        self.catalogMatches = []
+                    }
+                } else {
+                    self.googleStatusMessage = "Showing your latest likes."
+                    self.lastAdded = matchedLocal
+                    self.catalogMatches = []
+                }
+                self.lastGoogleSyncAt = Date()
+            }
+        }
+
+        do {
+            try await fetchAndMatch()
+        } catch {
+            if let nsErr = error as NSError?, nsErr.domain == "GoogleAuth", nsErr.code == -20 {
+                Diagnostics.log("MusicLibrary.refreshGoogleLikes: not signed in → re-consent")
+                do {
+                    _ = try await GoogleAuth.shared.signIn()
+                    try await fetchAndMatch()
+                    return
+                } catch {
+                    Diagnostics.log("MusicLibrary.refreshGoogleLikes: re-consent failed \(error.localizedDescription)")
+                    await MainActor.run {
+                        self.isGoogleConnected = false
+                        self.googleStatusMessage = "Google re-consent required: \(error.localizedDescription)"
+                    }
+                }
+            } else if let apiErr = error as? YouTubeAPI.APIError {
+                switch apiErr {
+                case .http(let code, let message, let reason):
+                    Diagnostics.log("MusicLibrary.refreshGoogleLikes: HTTP error \(code) \(message) reason=\(String(describing: reason))")
+                    if code == 401 || code == 403 {
+                        do {
+                            _ = try await GoogleAuth.shared.signIn()
+                            try await fetchAndMatch()
+                            return
+                        } catch {
+                            Diagnostics.log("MusicLibrary.refreshGoogleLikes: re-consent failed \(error.localizedDescription)")
+                            await MainActor.run {
+                                self.isGoogleConnected = false
+                                self.googleStatusMessage = "Google re-consent failed: \(error.localizedDescription)"
+                            }
+                        }
+                    }
+                default:
+                    break
+                }
+            }
+            await MainActor.run {
+                self.googleStatusMessage = "Failed to load likes: \(error.localizedDescription)"
+                if self.authorization == .authorized {
+                    self.loadLastAdded(limit: limit)
+                }
+            }
+        }
+    }
+
+    func play(_ item: MPMediaItem) {
+        AppleMusicController.shared.play(item: item)
+    }
+
+    func artwork(for item: MPMediaItem, size: CGSize) -> UIImage? {
+        item.artwork?.image(at: size)
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/MusicPlaybackMonitor.swift b/Video Feed Test/MusicPlaybackMonitor.swift
new file mode 100644
index 0000000..15916f5
--- /dev/null
+++ b/Video Feed Test/MusicPlaybackMonitor.swift	
@@ -0,0 +1,54 @@
+import Foundation
+import MediaPlayer
+import Combine
+
+@MainActor
+final class MusicPlaybackMonitor: ObservableObject {
+    static let shared = MusicPlaybackMonitor()
+
+    @Published private(set) var isPlaying: Bool = false
+
+    private var appPlayer: MPMusicPlayerController!
+    private var sysPlayer: MPMusicPlayerController!
+    private var tokens: [NSObjectProtocol] = []
+
+    private init() {
+        appPlayer = MPMusicPlayerController.applicationMusicPlayer
+        sysPlayer = MPMusicPlayerController.systemMusicPlayer
+
+        appPlayer.beginGeneratingPlaybackNotifications()
+        sysPlayer.beginGeneratingPlaybackNotifications()
+
+        let center = NotificationCenter.default
+        let names: [Notification.Name] = [
+            .MPMusicPlayerControllerPlaybackStateDidChange,
+            .MPMusicPlayerControllerNowPlayingItemDidChange
+        ]
+
+        for name in names {
+            tokens.append(center.addObserver(forName: name, object: appPlayer, queue: .main) { [weak self] _ in
+                self?.refresh()
+            })
+            tokens.append(center.addObserver(forName: name, object: sysPlayer, queue: .main) { [weak self] _ in
+                self?.refresh()
+            })
+        }
+
+        refresh()
+    }
+
+    deinit {
+        let center = NotificationCenter.default
+        for t in tokens { center.removeObserver(t) }
+        tokens.removeAll()
+        MPMusicPlayerController.applicationMusicPlayer.endGeneratingPlaybackNotifications()
+        MPMusicPlayerController.systemMusicPlayer.endGeneratingPlaybackNotifications()
+    }
+
+    private func refresh() {
+        let playing = (appPlayer.playbackState == .playing) || (sysPlayer.playbackState == .playing)
+        if isPlaying != playing {
+            isPlaying = playing
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/NetworkSpeedMonitor.swift b/Video Feed Test/NetworkSpeedMonitor.swift
new file mode 100644
index 0000000..5dbd782
--- /dev/null
+++ b/Video Feed Test/NetworkSpeedMonitor.swift	
@@ -0,0 +1,9 @@
+import Foundation
+import Combine
+
+@MainActor
+final class NetworkSpeedMonitor: ObservableObject {
+    static let shared = NetworkSpeedMonitor()
+    @Published var downloadBps: Double = 0
+    private init() {}
+}
\ No newline at end of file
diff --git a/Video Feed Test/OptionsSheetView.swift b/Video Feed Test/OptionsSheetView.swift
new file mode 100644
index 0000000..ea2ed7b
--- /dev/null
+++ b/Video Feed Test/OptionsSheetView.swift	
@@ -0,0 +1,729 @@
+import SwiftUI
+import Combine
+import MediaPlayer
+
+private enum OptionsTheme {
+    static let text = Color.primary
+    static let secondaryText = Color.secondary
+    static let background = Color(red: 0.07, green: 0.08, blue: 0.09).opacity(0.36)
+    static let separator = Color.white.opacity(0.12)
+    static let subtleFill = Color.white.opacity(0.06)
+    static let chipFill = Color.white.opacity(0.08)
+    static let placeholderFill = Color.white.opacity(0.06)
+    static let grabber = Color.white.opacity(0.4)
+}
+
+@MainActor
+final class OptionsCoordinator: ObservableObject {
+    @Published private(set) var base: CGFloat = 0
+    @Published private(set) var gestureDelta: CGFloat = 0
+    @Published var isPresented: Bool = false
+    @Published private(set) var isInteracting: Bool = false
+
+    var progress: CGFloat { clamp01(base + gestureDelta) }
+
+    func beginOpenInteraction() {
+        withAnimation(nil) {
+            base = progress
+            gestureDelta = 0
+            isInteracting = true
+        }
+    }
+
+    func updateOpenDrag(dy: CGFloat, distance: CGFloat) {
+        let target = clamp01(-dy / max(distance, 1))
+        withAnimation(nil) {
+            gestureDelta = target - base
+        }
+    }
+
+    func endOpen(velocityUp: CGFloat) {
+        let p = progress
+        let shouldOpen = p > 0.25 || velocityUp > 900
+        let stiffness: CGFloat = velocityUp > 1400 ? 280 : 220
+        let damping: CGFloat = 28
+        isInteracting = false
+        withAnimation(.interpolatingSpring(stiffness: stiffness, damping: damping)) {
+            base = shouldOpen ? 1 : 0
+            gestureDelta = 0
+            isPresented = shouldOpen
+        }
+    }
+
+    func beginCloseInteraction() {
+        withAnimation(nil) {
+            base = progress
+            gestureDelta = 0
+            isInteracting = true
+        }
+    }
+
+    func updateCloseDrag(dy: CGFloat, distance: CGFloat) {
+        let target = clamp01(base - (dy / max(distance, 1)))
+        withAnimation(nil) {
+            gestureDelta = target - base
+        }
+    }
+
+    func endClose(velocityDown: CGFloat) {
+        let p = progress
+        let shouldClose = p < 0.6 || velocityDown > 900
+        let stiffness: CGFloat = velocityDown > 1400 ? 280 : 220
+        let damping: CGFloat = 28
+        isInteracting = false
+        withAnimation(.interpolatingSpring(stiffness: stiffness, damping: damping)) {
+            base = shouldClose ? 0 : 1
+            gestureDelta = 0
+            isPresented = !shouldClose
+        }
+    }
+}
+
+struct OptionsPinnedTransform: ViewModifier {
+    let progress: CGFloat
+
+    func body(content: Content) -> some View {
+        GeometryReader { proxy in
+            let size = proxy.size
+            let targetH = targetPinnedHeight(for: size)
+            let minScale = min(1.0, max(0.01, targetH / max(1, size.height)))
+            let s = lerp(1.0, minScale, clamp01(progress))
+            content
+                .scaleEffect(s, anchor: .top)
+                .shadow(color: Color.black.opacity(0.25 * clamp01(progress)), radius: 10 * clamp01(progress), x: 0, y: 6 * clamp01(progress))
+                .ignoresSafeArea()
+                .animation(nil, value: size)
+        }
+    }
+}
+
+extension View {
+    func optionsPinnedTopTransform(progress: CGFloat) -> some View {
+        modifier(OptionsPinnedTransform(progress: progress))
+    }
+}
+
+// Bottom-sheet style panel that slides up from the bottom.
+// Dimmed backdrop is pass-through; only the sheet captures gestures.
+struct OptionsSheet: View {
+    @ObservedObject var options: OptionsCoordinator
+    @ObservedObject var appleMusic: MusicLibraryModel
+    let currentAssetID: String?
+    let onDelete: () -> Void
+    let onShare: () -> Void
+    let onOpenSettings: () -> Void
+    @State private var isClosingDrag = false
+    @State private var panelHeight: CGFloat = 0
+    @ObservedObject private var videoVolume = VideoVolumeManager.shared
+    @ObservedObject private var music = MusicPlaybackMonitor.shared
+    @State private var perVideoVolume: Float?
+
+    var body: some View {
+        GeometryReader { proxy in
+            let progress = options.progress
+            let reveal = clamp01(progress)
+            let bottomInset = proxy.safeAreaInsets.bottom
+            let measured = panelHeight > 0 ? panelHeight : proxy.size.height * 0.4
+            let offscreen = measured + bottomInset + 24
+            let containerH = proxy.size.height
+            let pinnedH = targetPinnedHeight(for: proxy.size)
+            let yMin = max(0, pinnedH + measured - containerH)
+            let travel = max(1, offscreen - yMin)
+            let yOffset = yMin + (1 - reveal) * travel
+
+            ZStack(alignment: .bottom) {
+                Color.black.opacity(0.0001 + 0.24 * reveal)
+                    .ignoresSafeArea()
+                    .allowsHitTesting(false)
+
+                VStack(alignment: .leading, spacing: 10) {
+
+                    HStack {
+                        Text("Options")
+                            .font(.headline)
+                            .foregroundColor(OptionsTheme.text)
+                        Spacer()
+                        if currentAssetID != nil {
+                            Button {
+                                onDelete()
+                            } label: {
+                                Image(systemName: "trash")
+                                    .font(.system(size: 16, weight: .bold))
+                                    .foregroundStyle(.red)
+                                    .padding(10)
+                                    .background(
+                                        Circle().fill(OptionsTheme.chipFill)
+                                            .overlay(Circle().stroke(OptionsTheme.separator, lineWidth: 1))
+                                    )
+                            }
+                            .buttonStyle(.plain)
+                            .accessibilityLabel("Delete video")
+                            .accessibilityHint("Deletes the current video from your feed")
+                        }
+                        GlassCloseButton {
+                            options.beginCloseInteraction()
+                            options.updateCloseDrag(dy: 999, distance: 999)
+                            options.endClose(velocityDown: 1000)
+                        }
+                    }
+
+                    VStack(alignment: .leading, spacing: 8) {
+                        Text("Music playback")
+                            .font(.subheadline.weight(.semibold))
+                            .foregroundColor(OptionsTheme.text)
+
+                        HStack(spacing: 12) {
+                            Button {
+                                if music.isPlaying {
+                                    AppleMusicController.shared.pauseIfManaged()
+                                } else {
+                                    AppleMusicController.shared.resumeIfManaged()
+                                }
+                            } label: {
+                                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
+                                    .font(.system(size: 16, weight: .bold))
+                                    .foregroundStyle(OptionsTheme.text)
+                                    .padding(10)
+                                    .background(
+                                        Circle().fill(OptionsTheme.chipFill)
+                                            .overlay(Circle().stroke(OptionsTheme.separator, lineWidth: 1))
+                                    )
+                                    .accessibilityLabel(music.isPlaying ? "Pause music" : "Play music")
+                            }
+                            .buttonStyle(.plain)
+
+                            Button {
+                                AppleMusicController.shared.skipToPrevious()
+                            } label: {
+                                Image(systemName: "backward.fill")
+                                    .font(.system(size: 14, weight: .bold))
+                                    .foregroundStyle(OptionsTheme.text)
+                                    .padding(8)
+                                    .background(
+                                        Circle().fill(OptionsTheme.subtleFill)
+                                            .overlay(Circle().stroke(OptionsTheme.separator, lineWidth: 1))
+                                    )
+                                    .accessibilityLabel("Previous track")
+                            }
+                            .buttonStyle(.plain)
+
+                            Button {
+                                AppleMusicController.shared.skipToNext()
+                            } label: {
+                                Image(systemName: "forward.fill")
+                                    .font(.system(size: 14, weight: .bold))
+                                    .foregroundStyle(OptionsTheme.text)
+                                    .padding(8)
+                                    .background(
+                                        Circle().fill(OptionsTheme.subtleFill)
+                                            .overlay(Circle().stroke(OptionsTheme.separator, lineWidth: 1))
+                                    )
+                                    .accessibilityLabel("Next track")
+                            }
+                            .buttonStyle(.plain)
+
+                            Spacer(minLength: 0)
+                        }
+
+                        Text("Pick a song to play")
+                            .font(.subheadline.weight(.semibold))
+                            .foregroundColor(OptionsTheme.text)
+
+                        if !appleMusic.catalogMatches.isEmpty {
+                            ScrollView(.horizontal, showsIndicators: false) {
+                                HStack(spacing: 10) {
+                                    ForEach(appleMusic.catalogMatches, id: \.storeID) { song in
+                                        Button {
+                                            if let id = currentAssetID {
+                                                Task { await VideoAudioOverrides.shared.setSongReference(for: id, reference: SongReference.appleMusic(storeID: song.storeID, title: song.title, artist: song.artist)) }
+                                            }
+                                            AppleMusicController.shared.play(storeID: song.storeID)
+                                        } label: {
+                                            HStack(alignment: .center, spacing: 10) {
+                                                let size: CGFloat = 44
+                                                AsyncImage(url: song.artworkURL) { phase in
+                                                    switch phase {
+                                                    case .success(let image):
+                                                        image.resizable()
+                                                            .scaledToFill()
+                                                            .frame(width: size, height: size)
+                                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
+                                                    case .empty:
+                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
+                                                            .fill(OptionsTheme.placeholderFill)
+                                                            .frame(width: size, height: size)
+                                                    case .failure:
+                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
+                                                            .fill(OptionsTheme.placeholderFill)
+                                                            .frame(width: size, height: size)
+                                                            .overlay(
+                                                                Image(systemName: "music.note")
+                                                                    .foregroundStyle(OptionsTheme.secondaryText)
+                                                            )
+                                                    @unknown default:
+                                                        EmptyView()
+                                                    }
+                                                }
+                                                VStack(alignment: .leading, spacing: 2) {
+                                                    Text(song.title)
+                                                        .foregroundColor(OptionsTheme.text)
+                                                        .lineLimit(1)
+                                                        .font(.footnote.weight(.semibold))
+                                                    Text(song.artist)
+                                                        .foregroundColor(OptionsTheme.secondaryText)
+                                                        .lineLimit(1)
+                                                        .font(.caption2)
+                                                }
+                                            }
+                                            .frame(width: 220, alignment: .leading)
+                                            .padding(10)
+                                            .background(
+                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
+                                                    .fill(OptionsTheme.chipFill)
+                                                    .overlay(
+                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
+                                                            .stroke(OptionsTheme.separator, lineWidth: 1)
+                                                    )
+                                            )
+                                        }
+                                        .buttonStyle(.plain)
+                                    }
+                                }
+                            }
+                        }
+
+                        Group {
+                            switch appleMusic.authorization {
+                            case .authorized:
+                                if appleMusic.isLoading {
+                                    HStack(spacing: 8) {
+                                        ProgressView()
+                                        Text("Loading your recent songs…")
+                                            .foregroundColor(OptionsTheme.secondaryText)
+                                            .font(.footnote)
+                                    }
+                                } else if appleMusic.lastAdded.isEmpty {
+                                    if appleMusic.catalogMatches.isEmpty {
+                                        Text("No recent songs found in your library.")
+                                            .foregroundColor(OptionsTheme.secondaryText)
+                                            .font(.footnote)
+                                    }
+                                } else {
+                                    HStack(spacing: 10) {
+                                        ForEach(appleMusic.lastAdded, id: \.persistentID) { item in
+                                            Button {
+                                                if let id = currentAssetID {
+                                                    let storeID: String? = nil
+                                                    Task { await VideoAudioOverrides.shared.setSongOverride(for: id, storeID: storeID) }
+                                                }
+                                                appleMusic.play(item)
+                                            } label: {
+                                                HStack(alignment: .center, spacing: 10) {
+                                                    let size: CGFloat = 44
+                                                    if let img = appleMusic.artwork(for: item, size: CGSize(width: size * 2, height: size * 2)) {
+                                                        Image(uiImage: img)
+                                                            .resizable()
+                                                            .scaledToFill()
+                                                            .frame(width: size, height: size)
+                                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
+                                                    } else {
+                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
+                                                            .fill(OptionsTheme.placeholderFill)
+                                                            .frame(width: size, height: size)
+                                                            .overlay(
+                                                                Image(systemName: "music.note")
+                                                                    .foregroundStyle(OptionsTheme.secondaryText)
+                                                            )
+                                                    }
+                                                    VStack(alignment: .leading, spacing: 2) {
+                                                        Text(item.title ?? "Unknown Title")
+                                                            .foregroundColor(OptionsTheme.text)
+                                                            .lineLimit(1)
+                                                            .font(.footnote.weight(.semibold))
+                                                        Text(item.artist ?? "Unknown Artist")
+                                                            .foregroundColor(OptionsTheme.secondaryText)
+                                                            .lineLimit(1)
+                                                            .font(.caption2)
+                                                    }
+                                                }
+                                                .frame(width: 220, alignment: .leading)
+                                                .padding(10)
+                                                .background(
+                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
+                                                        .fill(OptionsTheme.chipFill)
+                                                        .overlay(
+                                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
+                                                                .stroke(OptionsTheme.separator, lineWidth: 1)
+                                                        )
+                                                )
+                                            }
+                                            .buttonStyle(.plain)
+                                        }
+                                    }
+                                    .modifier(_HorizontalScrollWrap())
+                                }
+
+                            case .notDetermined:
+                                Button {
+                                    appleMusic.requestAccessAndLoad()
+                                } label: {
+                                    Label("Allow Apple Music Access", systemImage: "music.note.list")
+                                }
+                                .buttonStyle(.borderedProminent)
+
+                            case .denied, .restricted:
+                                if appleMusic.catalogMatches.isEmpty {
+                                    Button {
+                                        if let url = URL(string: UIApplication.openSettingsURLString) {
+                                            UIApplication.shared.open(url)
+                                        }
+                                    } label: {
+                                        Label("Open Settings to Allow Apple Music", systemImage: "gearshape")
+                                    }
+                                    .buttonStyle(.bordered)
+                                }
+                            @unknown default:
+                                EmptyView()
+                            }
+                        }
+                    }
+                    .padding(.top, 6)
+
+                    VStack(alignment: .leading, spacing: 10) {
+                        Text("Video volume")
+                            .font(.subheadline.weight(.semibold))
+                            .foregroundColor(OptionsTheme.text)
+                        HStack(spacing: 12) {
+                            Slider(value: Binding(
+                                get: {
+                                    if let _ = currentAssetID, let local = perVideoVolume {
+                                        return Double(local)
+                                    } else {
+                                        return Double(videoVolume.userVolume)
+                                    }
+                                },
+                                set: { newVal in
+                                    let v = Float(newVal)
+                                    if let id = currentAssetID {
+                                        perVideoVolume = v
+                                        Task { await VideoAudioOverrides.shared.setVolumeOverride(for: id, volume: v) }
+                                    } else {
+                                        videoVolume.userVolume = v
+                                    }
+                                }
+                            ), in: 0.0...1.0)
+                            .tint(.accentColor)
+                            .accessibilityLabel("Video volume")
+
+                            let effective: Float = {
+                                let base: Float
+                                if let _ = currentAssetID, let local = perVideoVolume {
+                                    base = local
+                                } else {
+                                    base = videoVolume.userVolume
+                                }
+                                if music.isPlaying {
+                                    return min(base, videoVolume.duckingCapWhileMusic)
+                                }
+                                return base
+                            }()
+                            Text(String(format: "%d%%", Int(round(Double(effective) * 100))))
+                                .foregroundColor(OptionsTheme.secondaryText)
+                                .font(.footnote.monospacedDigit())
+                                .frame(width: 44, alignment: .trailing)
+                        }
+                        if music.isPlaying {
+                            Text("Capped while music is playing.")
+                                .font(.caption2)
+                                .foregroundColor(OptionsTheme.secondaryText)
+                        }
+                    }
+                    .padding(.top, 10)
+
+                    VStack(alignment: .leading, spacing: 10) {
+                        Text("Actions")
+                            .font(.subheadline.weight(.semibold))
+                            .foregroundColor(OptionsTheme.text)
+                        HStack(spacing: 12) {
+                            if currentAssetID != nil {
+                                Button {
+                                    onShare()
+                                } label: {
+                                    Label("Share", systemImage: "square.and.arrow.up")
+                                        .font(.footnote.weight(.semibold))
+                                        .foregroundStyle(OptionsTheme.text)
+                                        .padding(.horizontal, 12)
+                                        .padding(.vertical, 8)
+                                        .background(
+                                            Capsule().fill(OptionsTheme.chipFill)
+                                                .overlay(Capsule().stroke(OptionsTheme.separator, lineWidth: 1))
+                                        )
+                                }
+                                .buttonStyle(.plain)
+                                .accessibilityLabel("Share current video")
+                            }
+                            Button {
+                                onOpenSettings()
+                            } label: {
+                                Label("Settings", systemImage: "gearshape")
+                                    .font(.footnote.weight(.semibold))
+                                    .foregroundStyle(OptionsTheme.text)
+                                    .padding(.horizontal, 12)
+                                    .padding(.vertical, 8)
+                                    .background(
+                                        Capsule().fill(OptionsTheme.subtleFill)
+                                            .overlay(Capsule().stroke(OptionsTheme.separator, lineWidth: 1))
+                                    )
+                            }
+                            .buttonStyle(.plain)
+                            .accessibilityLabel("Open settings")
+                        }
+                    }
+                    .padding(.top, 12)
+                }
+                .padding(.horizontal, 16)
+                .padding(.bottom, 16 + bottomInset)
+                .frame(maxWidth: .infinity, alignment: .leading)
+                .background(
+                    RoundedRectangle(cornerRadius: 22, style: .continuous)
+                        .fill(OptionsTheme.background)
+                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), stroke: false)
+                        .ignoresSafeArea(edges: .bottom)
+                )
+                .background(
+                    GeometryReader { gp in
+                        Color.clear
+                            .onAppear { panelHeight = gp.size.height }
+                            .onChange(of: gp.size) { newSize in
+                                panelHeight = newSize.height
+                            }
+                    }
+                )
+                .offset(y: yOffset)
+                .opacity(reveal)
+                .contentShape(Rectangle())
+                .gesture(
+                    DragGesture(minimumDistance: 6, coordinateSpace: .local)
+                        .onChanged { value in
+                            guard value.translation.height > 0 else { return }
+                            if !isClosingDrag {
+                                isClosingDrag = true
+                                options.beginCloseInteraction()
+                            }
+                            options.updateCloseDrag(dy: value.translation.height, distance: travel)
+                        }
+                        .onEnded { value in
+                            guard isClosingDrag else { return }
+                            options.endClose(velocityDown: value.velocity.y)
+                            isClosingDrag = false
+                        }
+                )
+            }
+        }
+        .allowsHitTesting(options.progress > 0.01)
+        .onAppear {
+            appleMusic.bootstrap()
+            AppleMusicController.shared.prewarm()
+            _ = MusicPlaybackMonitor.shared
+            if let id = currentAssetID {
+                Task { perVideoVolume = await VideoAudioOverrides.shared.volumeOverride(for: id) ?? videoVolume.userVolume }
+            } else {
+                perVideoVolume = nil
+            }
+        }
+        .onChange(of: currentAssetID) { newID in
+            if let id = newID {
+                Task {
+                    let v = await VideoAudioOverrides.shared.volumeOverride(for: id)
+                    await MainActor.run {
+                        perVideoVolume = v ?? videoVolume.userVolume
+                    }
+                }
+            } else {
+                perVideoVolume = nil
+            }
+        }
+    }
+}
+
+struct OptionsOpenHotspot: View {
+    @ObservedObject var options: OptionsCoordinator
+
+    private let hotspotSize = CGSize(width: 64, height: 180)
+    private let hotspotLeadingOffset: CGFloat = 88
+    private let hotspotBottomOffset: CGFloat = 36
+
+    @State private var isInteracting = false
+    @State private var pulse = false
+
+    var body: some View {
+        GeometryReader { proxy in
+            let distance = openDistance(for: proxy.size)
+            let reveal = clamp01(options.progress)
+            let highlightOpacity = options.isPresented ? 0 : max(0, 1 - reveal * 2.5)
+
+            ZStack {
+                RoundedRectangle(cornerRadius: 14, style: .continuous)
+                    .stroke(OptionsTheme.separator, lineWidth: 1.5)
+                    .background(
+                        RoundedRectangle(cornerRadius: 14, style: .continuous)
+                            .fill(OptionsTheme.subtleFill)
+                    )
+                    .overlay {
+                        VStack(spacing: 4) {
+                            Image(systemName: "chevron.up")
+                                .font(.system(size: 12, weight: .semibold))
+                            Text("Drag up")
+                                .font(.caption2.weight(.semibold))
+                        }
+                        .foregroundStyle(OptionsTheme.secondaryText)
+                        .padding(.vertical, 8)
+                    }
+                    .frame(width: hotspotSize.width, height: hotspotSize.height)
+                    .opacity(highlightOpacity)
+                    .scaleEffect(pulse ? 1.03 : 1.0)
+                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
+
+                Rectangle()
+                    .fill(Color.clear)
+                    .frame(width: hotspotSize.width, height: hotspotSize.height)
+                    .contentShape(Rectangle())
+                    .gesture(
+                        DragGesture(minimumDistance: 2, coordinateSpace: .local)
+                            .onChanged { value in
+                                if !isInteracting, value.translation.height < 0 {
+                                    isInteracting = true
+                                    options.beginOpenInteraction()
+                                }
+                                guard isInteracting else { return }
+                                options.updateOpenDrag(dy: value.translation.height, distance: distance)
+                            }
+                            .onEnded { value in
+                                let vyUp = -value.velocity.y
+                                options.endOpen(velocityUp: vyUp)
+                                isInteracting = false
+                            }
+                    )
+                    .accessibilityHidden(true)
+            }
+            .position(
+                x: hotspotLeadingOffset + hotspotSize.width / 2,
+                y: proxy.size.height - proxy.safeAreaInsets.bottom - hotspotBottomOffset - hotspotSize.height / 2
+            )
+        }
+        .onAppear { pulse = true }
+        .allowsHitTesting(!options.isPresented)
+    }
+}
+
+struct OptionsDragHandle: View {
+    @ObservedObject var options: OptionsCoordinator
+    var openDistance: CGFloat? = nil
+    @State private var isInteracting = false
+    @State private var openDistanceCache: CGFloat = 360
+
+    private let handleSize = CGSize(width: 26, height: 82)
+    private let touchPadding = CGSize(width: 20, height: 18)
+
+    var body: some View {
+        ZStack {
+            Capsule()
+                .fill(Color.black.opacity(0.28))
+                .frame(width: handleSize.width, height: handleSize.height)
+                .liquidGlass(in: Capsule())
+                .overlay(
+                    Capsule().stroke(OptionsTheme.separator, lineWidth: 1)
+                )
+                .shadow(color: Color.black.opacity(0.25 * clamp01(options.progress)), radius: 10 * clamp01(options.progress), x: 0, y: 6 * clamp01(options.progress))
+        }
+        .frame(width: handleSize.width, height: handleSize.height)
+        .contentShape(Rectangle())
+        .padding(.horizontal, touchPadding.width)
+        .padding(.vertical, touchPadding.height)
+        .gesture(
+            DragGesture(minimumDistance: 2, coordinateSpace: .global)
+                .onChanged { value in
+                    if !isInteracting, value.translation.height < 0 {
+                        isInteracting = true
+                        options.beginOpenInteraction()
+                    }
+                    guard isInteracting else { return }
+                    options.updateOpenDrag(dy: value.translation.height, distance: openDistanceCache)
+                }
+                .onEnded { value in
+                    let vyUp = -value.velocity.y
+                    options.endOpen(velocityUp: vyUp)
+                    isInteracting = false
+                }
+        )
+        .allowsHitTesting(!options.isPresented)
+        .accessibilityLabel("Open panel")
+        .onAppear {
+            if let d = openDistance {
+                openDistanceCache = d
+            } else {
+                openDistanceCache = min(max(UIScreen.main.bounds.size.height * 0.22, 280), 420)
+            }
+        }
+        .onChange(of: openDistance) { newVal in
+            if let d = newVal {
+                openDistanceCache = d
+            }
+        }
+    }
+}
+
+// Helpers
+
+private func clamp01(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
+
+private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
+
+private func targetPinnedHeight(for size: CGSize) -> CGFloat {
+    let base = size.height * 0.32
+    return min(max(base, 220), 360)
+}
+
+private func openDistance(for size: CGSize) -> CGFloat {
+    min(max(size.height * 0.22, 280), 420)
+}
+
+private extension DragGesture.Value {
+    var velocity: CGPoint {
+        let dt: CGFloat = 0.016
+        let dx = (predictedEndLocation.x - location.x) / dt
+        let dy = (predictedEndLocation.y - location.y) / dt
+        return CGPoint(x: dx, y: dy)
+    }
+}
+
+private struct _HorizontalScrollWrap: ViewModifier {
+    func body(content: Content) -> some View {
+        ScrollView(.horizontal, showsIndicators: false) {
+            HStack(spacing: 10) {
+                content
+            }
+        }
+    }
+}
+
+// Native glass close button with large hit target to match glass patterns.
+private struct GlassCloseButton: View {
+    var action: () -> Void
+    var body: some View {
+        Button(action: action) {
+            Image(systemName: "xmark")
+                .font(.system(size: 18, weight: .semibold))
+                .foregroundStyle(OptionsTheme.text)
+                .frame(width: 44, height: 44)
+                .background(
+                    Circle()
+                        .fill(Color.white.opacity(0.08))
+                        .liquidGlass(in: Circle(), stroke: false)
+                )
+                .contentShape(Circle())
+        }
+        .buttonStyle(.plain)
+        .accessibilityLabel("Close")
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/PagedCollectionView.swift b/Video Feed Test/PagedCollectionView.swift
new file mode 100644
index 0000000..e1c5143
--- /dev/null
+++ b/Video Feed Test/PagedCollectionView.swift	
@@ -0,0 +1,359 @@
+import SwiftUI
+import UIKit
+
+struct PagedCollectionView<Item, Content: View>: UIViewControllerRepresentable {
+    let items: [Item]
+    @Binding var index: Int
+    let id: (Item) -> String
+    let onPrefetch: (IndexSet, CGSize) -> Void
+    let onCancelPrefetch: (IndexSet, CGSize) -> Void
+    let isPageReady: (Int) -> Bool
+    let content: (Int, Item, Bool) -> Content
+
+    let onScrollInteracting: (Bool) -> Void
+
+    func makeUIViewController(context: Context) -> Controller {
+        let layout = UICollectionViewFlowLayout()
+        layout.scrollDirection = .vertical
+        layout.minimumLineSpacing = 0
+        layout.minimumInteritemSpacing = 0
+        
+        let vc = Controller(collectionViewLayout: layout)
+        vc.collectionView.isPagingEnabled = true
+        vc.collectionView.isPrefetchingEnabled = true
+        vc.collectionView.showsVerticalScrollIndicator = false
+        vc.collectionView.backgroundColor = .black
+        vc.collectionView.dataSource = vc
+        vc.collectionView.delegate = vc
+        vc.collectionView.prefetchDataSource = vc
+        vc.collectionView.register(Controller.Cell.self, forCellWithReuseIdentifier: "Cell")
+        vc.indexBinding = self.$index
+        vc.items = items
+        vc.idProvider = id
+        vc.onPrefetch = onPrefetch
+        vc.onCancelPrefetch = onCancelPrefetch
+        vc.isPageReady = isPageReady
+        vc.contentBuilder = { idx, item, isActive in AnyView(content(idx, item, isActive)) }
+        vc.captureIDs()
+        vc.onScrollInteracting = onScrollInteracting
+        return vc
+    }
+    
+    func updateUIViewController(_ uiViewController: Controller, context: Context) {
+        uiViewController.indexBinding = self.$index
+        uiViewController.contentBuilder = { idx, item, isActive in AnyView(content(idx, item, isActive)) }
+        uiViewController.idProvider = id
+        uiViewController.onPrefetch = onPrefetch
+        uiViewController.onCancelPrefetch = onCancelPrefetch
+        uiViewController.isPageReady = isPageReady
+        uiViewController.onScrollInteracting = onScrollInteracting
+        uiViewController.applyUpdates(items: items, index: index)
+    }
+    
+    final class Controller: UICollectionViewController, UICollectionViewDataSourcePrefetching, UICollectionViewDelegateFlowLayout {
+        var indexBinding: Binding<Int>!
+        var items: [Item] = []
+        var idProvider: ((Item) -> String)!
+        var contentBuilder: ((Int, Item, Bool) -> AnyView)!
+        var onPrefetch: ((IndexSet, CGSize) -> Void)!
+        var onCancelPrefetch: ((IndexSet, CGSize) -> Void)!
+        var isPageReady: ((Int) -> Bool)!
+        var onScrollInteracting: ((Bool) -> Void)!
+        
+        private var didInitialScroll = false
+        private var lastIDs: [String] = []
+        private var prefetchedIndices: Set<Int> = []
+        private let gateFraction: CGFloat = 0.2
+        private var gateActive = false
+        private lazy var gateSpinner: UIActivityIndicatorView = {
+            let s = UIActivityIndicatorView(style: .large)
+            s.hidesWhenStopped = true
+            s.color = .white
+            s.alpha = 0
+            return s
+        }()
+        private var gateConstraintsInstalled = false
+        
+        func captureIDs() {
+            lastIDs = items.map(idProvider)
+        }
+        
+        func applyUpdates(items: [Item], index: Int) {
+            let newIDs = items.map(idProvider)
+            let changed = newIDs != lastIDs
+            self.items = items
+            if changed {
+                lastIDs = newIDs
+                collectionView.collectionViewLayout.invalidateLayout()
+                collectionView.reloadData()
+                didInitialScroll = false
+                prefetchedIndices = []
+            }
+            if items.indices.contains(index) {
+                let currentPage = computedPage()
+                if currentPage != index {
+                    scrollTo(index, animated: false)
+                } else {
+                    refreshVisibleCellsActiveState()
+                    updatePrefetchWindow(for: index)
+                }
+            }
+        }
+        
+        override func viewDidLoad() {
+            super.viewDidLoad()
+            setupGateUI()
+            onScrollInteracting?(false)
+        }
+        
+        override func viewDidLayoutSubviews() {
+            super.viewDidLayoutSubviews()
+            (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = collectionView.bounds.size
+            if !didInitialScroll, items.indices.contains(indexBinding.wrappedValue) {
+                scrollTo(indexBinding.wrappedValue, animated: false)
+                didInitialScroll = true
+                updatePrefetchWindow(for: indexBinding.wrappedValue)
+            }
+            layoutGateUI()
+        }
+        
+        private func setupGateUI() {
+            guard gateSpinner.superview == nil else { return }
+            collectionView.addSubview(gateSpinner)
+            gateSpinner.translatesAutoresizingMaskIntoConstraints = false
+            gateConstraintsInstalled = false
+        }
+        
+        private func layoutGateUI() {
+            guard !gateConstraintsInstalled else { return }
+            gateConstraintsInstalled = true
+            NSLayoutConstraint.activate([
+                gateSpinner.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
+                gateSpinner.bottomAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.bottomAnchor, constant: -24)
+            ])
+        }
+        
+        private func showGateSpinner() {
+            gateActive = true
+            gateSpinner.startAnimating()
+            UIView.animate(withDuration: 0.15) {
+                self.gateSpinner.alpha = 1
+            }
+        }
+        
+        private func hideGateSpinner() {
+            gateActive = false
+            UIView.animate(withDuration: 0.15, animations: {
+                self.gateSpinner.alpha = 0
+            }, completion: { _ in
+                if !self.gateActive {
+                    self.gateSpinner.stopAnimating()
+                }
+            })
+        }
+        
+        private func scrollTo(_ index: Int, animated: Bool) {
+            guard items.indices.contains(index) else { return }
+            let offsetY = collectionView.bounds.height * CGFloat(index)
+            collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: animated)
+        }
+        
+        private func computedPage() -> Int {
+            guard collectionView.bounds.height > 0 else { return indexBinding.wrappedValue }
+            let page = Int(round(collectionView.contentOffset.y / collectionView.bounds.height))
+            return max(0, min(items.count - 1, page))
+        }
+        
+        override func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
+        override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
+            items.count
+        }
+        
+        override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
+            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! Cell
+            let item = items[indexPath.item]
+            let isActive = (indexBinding.wrappedValue == indexPath.item)
+            cell.setContent(contentBuilder(indexPath.item, item, isActive))
+            return cell
+        }
+        
+        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
+            let sorted = indexPaths.map(\.item).sorted()
+            let set = IndexSet(sorted)
+            let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale,
+                                height: collectionView.bounds.height * UIScreen.main.scale)
+            onPrefetch(set, sizePx)
+        }
+        
+        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
+            let sorted = indexPaths.map(\.item).sorted()
+            let set = IndexSet(sorted)
+            let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale,
+                                height: collectionView.bounds.height * UIScreen.main.scale)
+            onCancelPrefetch(set, sizePx)
+        }
+        
+        override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
+            if let cell = cell as? Cell, items.indices.contains(indexPath.item) {
+                let item = items[indexPath.item]
+                let isActive = (indexBinding.wrappedValue == indexPath.item)
+                cell.setContent(contentBuilder(indexPath.item, item, isActive))
+            }
+        }
+        
+        override func scrollViewDidScroll(_ scrollView: UIScrollView) {
+            guard collectionView.bounds.height > 0 else { return }
+
+            let target = computedPage()
+            if target != indexBinding.wrappedValue {
+                indexBinding.wrappedValue = target
+                Diagnostics.log("PagedCollection current index=\(target) [scroll]")
+                refreshVisibleCellsActiveState()
+                updatePrefetchWindow(for: target)
+            }
+
+            let h = collectionView.bounds.height
+            let current = indexBinding.wrappedValue
+            let baseY = h * CGFloat(current)
+            let y = scrollView.contentOffset.y
+            let delta = y - baseY
+            guard delta > 0 else {
+                hideGateSpinner()
+                return
+            }
+            var i = current + 1
+            while items.indices.contains(i), isPageReady(i) {
+                i += 1
+            }
+            guard items.indices.contains(i) else {
+                hideGateSpinner()
+                return
+            }
+            let readySpan = max(0, i - current - 1)
+            let cap = CGFloat(readySpan) * h + h * gateFraction
+            if delta > cap {
+                scrollView.contentOffset.y = baseY + cap
+                if scrollView.isDragging {
+                    showGateSpinner()
+                }
+            } else if !scrollView.isDragging {
+                hideGateSpinner()
+            }
+        }
+        
+        override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
+            onScrollInteracting?(true)
+        }
+        
+        override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
+            commitPageChange()
+            hideGateSpinner()
+            onScrollInteracting?(false)
+        }
+        
+        override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
+            if !decelerate {
+                commitPageChange()
+                hideGateSpinner()
+                onScrollInteracting?(false)
+            }
+        }
+        
+        override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
+            commitPageChange()
+            hideGateSpinner()
+            onScrollInteracting?(false)
+        }
+        
+        private func commitPageChange() {
+            let target = computedPage()
+            guard indexBinding.wrappedValue != target else {
+                refreshVisibleCellsActiveState()
+                updatePrefetchWindow(for: target)
+                return
+            }
+            indexBinding.wrappedValue = target
+            Diagnostics.log("PagedCollection current index=\(target)")
+            refreshVisibleCellsActiveState()
+            updatePrefetchWindow(for: target)
+        }
+
+        private func updatePrefetchWindow(for page: Int) {
+            guard !items.isEmpty else {
+                prefetchedIndices = []
+                return
+            }
+            let desired = desiredWindow(for: page)
+            let adds = desired.subtracting(prefetchedIndices)
+            let removes = prefetchedIndices.subtracting(desired)
+
+            let addOrder = adds.sorted()
+            let removeOrder = removes.sorted()
+
+            let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale,
+                                height: collectionView.bounds.height * UIScreen.main.scale)
+            if !addOrder.isEmpty {
+                Diagnostics.log("PagedCollection prefetch add indices=\(addOrder)")
+                onPrefetch(IndexSet(addOrder), sizePx)
+            }
+            if !removeOrder.isEmpty {
+                Diagnostics.log("PagedCollection prefetch cancel indices=\(removeOrder)")
+                onCancelPrefetch(IndexSet(removeOrder), sizePx)
+            }
+
+            prefetchedIndices = desired
+        }
+
+        private func desiredWindow(for index: Int) -> Set<Int> {
+            let candidates = [index - 1, index, index + 1, index + 2, index + 3, index + 4,  index + 5, index + 6,  index + 7, index + 8]
+            let valid = candidates.filter { $0 >= 0 && $0 < items.count }
+            return Set(valid)
+        }
+        
+        private func refreshVisibleCellsActiveState() {
+            for indexPath in collectionView.indexPathsForVisibleItems {
+                guard let cell = collectionView.cellForItem(at: indexPath) as? Cell,
+                      items.indices.contains(indexPath.item) else { continue }
+                let item = items[indexPath.item]
+                let isActive = (indexBinding.wrappedValue == indexPath.item)
+                cell.setContent(contentBuilder(indexPath.item, item, isActive))
+            }
+        }
+        
+        final class Cell: UICollectionViewCell {
+            private var hostingController: UIHostingController<AnyView>?
+            
+            override init(frame: CGRect) {
+                super.init(frame: frame)
+                backgroundColor = .black
+            }
+            
+            required init?(coder: NSCoder) {
+                super.init(coder: coder)
+                backgroundColor = .black
+            }
+            
+            func setContent(_ view: AnyView) {
+                if let hostingController {
+                    hostingController.rootView = view
+                } else {
+                    let hc = UIHostingController(rootView: view)
+                    hostingController = hc
+                    hc.view.backgroundColor = .clear
+                    hc.view.translatesAutoresizingMaskIntoConstraints = false
+                    contentView.addSubview(hc.view)
+                    NSLayoutConstraint.activate([
+                        hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
+                        hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
+                        hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
+                        hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
+                    ])
+                }
+            }
+        }
+        
+        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
+            collectionView.bounds.size
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/PerformanceMonitor.swift b/Video Feed Test/PerformanceMonitor.swift
new file mode 100644
index 0000000..42ac880
--- /dev/null
+++ b/Video Feed Test/PerformanceMonitor.swift	
@@ -0,0 +1,172 @@
+import Foundation
+import Combine
+import Network
+import os
+import UIKit
+
+@MainActor
+final class PerformanceMonitor: ObservableObject {
+    static let shared = PerformanceMonitor()
+
+    struct Snapshot: Sendable {
+        let timestamp: Date
+        let fps: Double
+        let memoryFootprintMB: Double?
+        let thermalState: ProcessInfo.ThermalState
+        let isLowPowerModeEnabled: Bool
+        let batteryLevel: Double?
+        let batteryState: UIDevice.BatteryState
+        let networkStatus: NWPath.Status
+        let isCellular: Bool
+        let isConstrained: Bool
+        let isExpensive: Bool
+        let cpuSystemBusyPercent: Double?
+    }
+
+    @Published private(set) var latest: Snapshot?
+
+    private let pathMonitor = NWPathMonitor()
+    private let pathQueue = DispatchQueue(label: "perf.path.monitor")
+    private var path: NWPath?
+    private var samplingTask: Task<Void, Never>?
+    private var logCounter = 0
+
+    private init() {}
+
+    func start() {
+        guard samplingTask == nil else { return }
+
+        UIDevice.current.isBatteryMonitoringEnabled = true
+        FPSMonitor.shared.start()
+
+        pathMonitor.pathUpdateHandler = { [weak self] p in
+            Task { @MainActor [weak self] in
+                self?.path = p
+            }
+        }
+        pathMonitor.start(queue: pathQueue)
+
+        samplingTask = Task.detached { [weak self] in
+            await self?.runSampler()
+        }
+    }
+
+    func stop() {
+        samplingTask?.cancel()
+        samplingTask = nil
+        pathMonitor.cancel()
+        FPSMonitor.shared.stop()
+    }
+
+    private func post(_ snap: Snapshot) {
+        latest = snap
+    }
+
+    private func networkSnapshot() -> (NWPath.Status, Bool, Bool, Bool) {
+        let p = path
+        let status = p?.status ?? .requiresConnection
+        let isCellular = p?.usesInterfaceType(.cellular) ?? false
+        let isConstrained = p?.isConstrained ?? false
+        let isExpensive = p?.isExpensive ?? false
+        return (status, isCellular, isConstrained, isExpensive)
+    }
+
+    private func batterySnapshot() -> (Double?, UIDevice.BatteryState) {
+        let lvl = UIDevice.current.batteryLevel
+        let level = lvl >= 0 ? Double(lvl) : nil
+        return (level, UIDevice.current.batteryState)
+    }
+
+    private func buildSnapshot(fps: Double, memMB: Double?, cpuBusyPct: Double?) -> Snapshot {
+        let (status, isCellular, isConstrained, isExpensive) = networkSnapshot()
+        let (batteryLevel, batteryState) = batterySnapshot()
+        return Snapshot(
+            timestamp: Date(),
+            fps: fps,
+            memoryFootprintMB: memMB,
+            thermalState: ProcessInfo.processInfo.thermalState,
+            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
+            batteryLevel: batteryLevel,
+            batteryState: batteryState,
+            networkStatus: status,
+            isCellular: isCellular,
+            isConstrained: isConstrained,
+            isExpensive: isExpensive,
+            cpuSystemBusyPercent: cpuBusyPct
+        )
+    }
+
+    private func logIfNeeded(_ s: Snapshot) {
+        logCounter &+= 1
+        if logCounter % 5 == 0 {
+            let mem = s.memoryFootprintMB.map { String(format: "%.1f", $0) } ?? "n/a"
+            let cpu = s.cpuSystemBusyPercent.map { String(format: "%.0f%%", $0) } ?? "n/a"
+            Diagnostics.log("Perf: fps=\(String(format: "%.1f", s.fps)) mem=\(mem)MB cpu=\(cpu) therm=\(s.thermalState.rawValue) lowPwr=\(s.isLowPowerModeEnabled) net=\(String(describing: s.networkStatus)) cell=\(s.isCellular) exp=\(s.isExpensive) constr=\(s.isConstrained)")
+        }
+        if s.thermalState == .serious || s.thermalState == .critical {
+            Diagnostics.log("Perf WARNING: thermal=\(s.thermalState.rawValue)")
+        }
+    }
+
+    private func runSampler() async {
+        var prevCPU: host_cpu_load_info_data_t?
+        while !Task.isCancelled {
+            try? await Task.sleep(for: .seconds(1))
+
+            if Task.isCancelled { break }
+
+            let memBytes = Self.memoryFootprintBytes()
+            let memMB = memBytes.map { Double($0) / (1024.0 * 1024.0) }
+
+            let cpuBusy = Self.systemCPUBusyPercent(previous: &prevCPU)
+
+            let fps = await MainActor.run { FPSMonitor.shared.fps }
+
+            let snap = await MainActor.run { buildSnapshot(fps: fps, memMB: memMB, cpuBusyPct: cpuBusy) }
+            await MainActor.run {
+                post(snap)
+                logIfNeeded(snap)
+            }
+        }
+    }
+
+    private static func memoryFootprintBytes() -> UInt64? {
+        var info = task_vm_info_data_t()
+        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
+        let kerr = withUnsafeMutablePointer(to: &info) {
+            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
+                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
+            }
+        }
+        if kerr == KERN_SUCCESS {
+            return UInt64(info.phys_footprint)
+        } else {
+            return nil
+        }
+    }
+
+    private static func systemCPUBusyPercent(previous prev: inout host_cpu_load_info_data_t?) -> Double? {
+        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
+        var info = host_cpu_load_info_data_t()
+        let result = withUnsafeMutablePointer(to: &info) {
+            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
+                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
+            }
+        }
+        guard result == KERN_SUCCESS else { return nil }
+        defer { prev = info }
+
+        guard let p = prev else { return nil }
+
+        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
+        let sys  = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
+        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
+        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)
+
+        let total = user + sys + idle + nice
+        guard total > 0 else { return nil }
+
+        let busy = (user + sys + nice) / total
+        return busy * 100.0
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/PhotoCarouselView.swift b/Video Feed Test/PhotoCarouselView.swift
new file mode 100644
index 0000000..be3c473
--- /dev/null
+++ b/Video Feed Test/PhotoCarouselView.swift	
@@ -0,0 +1,113 @@
+import SwiftUI
+import Photos
+import UIKit
+
+struct PhotoCarouselPostView: View {
+    let assets: [PHAsset]
+    @State private var page: Int = 0
+    
+    var body: some View {
+        ZStack {
+            TabView(selection: $page) {
+                ForEach(Array(assets.enumerated()), id: \.1.localIdentifier) { idx, asset in
+                    PhotoSlideView(asset: asset)
+                        .tag(idx)
+                }
+            }
+            .tabViewStyle(.page(indexDisplayMode: .never))
+            
+            VStack {
+                Spacer()
+                if assets.count > 1 {
+                    HStack(spacing: 8) {
+                        ForEach(0..<assets.count, id: \.self) { i in
+                            Circle()
+                                .fill(i == page ? Color.white : Color.white.opacity(0.35))
+                                .frame(width: i == page ? 8 : 6, height: i == page ? 8 : 6)
+                        }
+                    }
+                    .padding(.bottom, 28)
+                }
+            }
+        }
+        .background(Color.black)
+        .onAppear {
+            Diagnostics.log("PhotoCarousel appear count=\(assets.count) first=\(assets.first?.localIdentifier ?? "n/a")")
+        }
+    }
+}
+
+private struct PhotoSlideView: View {
+    let asset: PHAsset
+    @State private var image: UIImage?
+    @State private var task: Task<Void, Never>?
+    
+    var body: some View {
+        GeometryReader { geo in
+            let horizontalPadding: CGFloat = 16
+            let maxHeightFraction: CGFloat = 0.70
+            let corner: CGFloat = 14
+            let maxW = max(0, geo.size.width - horizontalPadding * 2)
+            let maxH = max(0, geo.size.height * maxHeightFraction)
+            
+            ZStack {
+                if let image {
+                    VStack {
+                        Image(uiImage: image)
+                            .resizable()
+                            .scaledToFit()
+                            .frame(maxWidth: maxW, maxHeight: maxH)
+                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
+                            .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)
+                    }
+                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
+                    .padding(.horizontal, horizontalPadding)
+                    .accessibilityHidden(true)
+                } else {
+                    VStack {
+                        RoundedRectangle(cornerRadius: corner, style: .continuous)
+                            .fill(Color.white.opacity(0.06))
+                            .frame(maxWidth: maxW, maxHeight: maxH)
+                            .overlay(
+                                ProgressView()
+                                    .progressViewStyle(.circular)
+                                    .tint(.white)
+                            )
+                    }
+                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
+                    .padding(.horizontal, horizontalPadding)
+                }
+            }
+            .frame(maxWidth: .infinity, maxHeight: .infinity)
+            .contentShape(Rectangle())
+            .onAppear {
+                let scale = UIScreen.main.scale
+                let viewportPx = CGSize(width: maxW * scale, height: maxH * scale)
+                let clampedPx = CGSize(
+                    width: min(viewportPx.width, CGFloat(asset.pixelWidth)),
+                    height: min(viewportPx.height, CGFloat(asset.pixelHeight))
+                )
+                startLoading(targetSize: clampedPx)
+            }
+            .onDisappear {
+                cancelLoading()
+            }
+        }
+    }
+    
+    private func startLoading(targetSize: CGSize) {
+        cancelLoading()
+        task = Task { @MainActor in
+            let stream = ImagePrefetcher.shared.progressiveImage(for: asset, targetSize: targetSize)
+            for await (img, _) in stream {
+                if Task.isCancelled { break }
+                self.image = img
+            }
+        }
+    }
+    
+    private func cancelLoading() {
+        task?.cancel()
+        task = nil
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/PlaybackPositionStore.swift b/Video Feed Test/PlaybackPositionStore.swift
new file mode 100644
index 0000000..dc70a30
--- /dev/null
+++ b/Video Feed Test/PlaybackPositionStore.swift	
@@ -0,0 +1,52 @@
+import Foundation
+import AVFoundation
+
+actor PlaybackPositionStore {
+    static let shared = PlaybackPositionStore()
+
+    struct Entry {
+        var seconds: Double
+        var durationSeconds: Double
+        var updatedAt: Date
+    }
+
+    private var map: [String: Entry] = [:]
+    private let maxEntries = 400
+
+    func record(id: String, time: CMTime, duration: CMTime) {
+        let now = Date()
+        let dur = duration.seconds.isFinite ? max(duration.seconds, 0) : 0
+        var sec = time.seconds.isFinite ? max(time.seconds, 0) : 0
+        if dur > 0 {
+            sec = min(sec, max(dur - 0.1, 0)) // avoid pinning at exact end
+        }
+        map[id] = Entry(seconds: sec, durationSeconds: dur, updatedAt: now)
+        trimIfNeeded()
+    }
+
+    func position(for id: String, duration: CMTime) -> CMTime? {
+        guard let e = map[id] else { return nil }
+        let dur = duration.seconds.isFinite ? duration.seconds : e.durationSeconds
+        guard dur > 0 else {
+            return e.seconds > 0.5 ? CMTime(seconds: e.seconds, preferredTimescale: 600) : nil
+        }
+        // If the saved position is near the start, ignore; near the end, clamp to zero.
+        if e.seconds < 0.5 { return nil }
+        if e.seconds >= dur - 0.25 { return CMTime.zero }
+        return CMTime(seconds: e.seconds, preferredTimescale: 600)
+    }
+
+    func clear(id: String) {
+        map.removeValue(forKey: id)
+    }
+
+    private func trimIfNeeded() {
+        if map.count <= maxEntries { return }
+        // Remove oldest entries
+        let sorted = map.sorted { $0.value.updatedAt < $1.value.updatedAt }
+        let toDrop = sorted.prefix(map.count - maxEntries)
+        for (k, _) in toDrop {
+            map.removeValue(forKey: k)
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/PlaybackRegistry.swift b/Video Feed Test/PlaybackRegistry.swift
new file mode 100644
index 0000000..ec65dd7
--- /dev/null
+++ b/Video Feed Test/PlaybackRegistry.swift	
@@ -0,0 +1,23 @@
+import Foundation
+import AVFoundation
+
+@MainActor
+final class PlaybackRegistry {
+    static let shared = PlaybackRegistry()
+
+    private let players = NSHashTable<AVPlayer>.weakObjects()
+
+    func register(_ player: AVPlayer) {
+        players.add(player)
+    }
+
+    func unregister(_ player: AVPlayer) {
+        players.remove(player)
+    }
+
+    func willPlay(_ player: AVPlayer) {
+        for p in players.allObjects where p !== player {
+            p.pause()
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/PlayerItemPrefetcher.swift b/Video Feed Test/PlayerItemPrefetcher.swift
new file mode 100644
index 0000000..36ddba5
--- /dev/null
+++ b/Video Feed Test/PlayerItemPrefetcher.swift	
@@ -0,0 +1,150 @@
+import Foundation
+import Photos
+import AVFoundation
+
+actor PlayerItemPrefetchStore {
+    private let cache = NSCache<NSString, AVPlayerItem>()
+    private var inFlight: [String: PHImageRequestID] = [:]
+    private var waiters: [String: [UUID: CheckedContinuation<AVPlayerItem?, Never>]] = [:]
+    
+    init() {
+        cache.countLimit = 24
+    }
+    
+    func prefetch(_ assets: [PHAsset]) async {
+        guard !assets.isEmpty else { return }
+        for asset in assets {
+            let id = asset.localIdentifier
+            if cache.object(forKey: id as NSString) != nil { continue }
+            if inFlight[id] != nil { continue }
+            
+            let options = PHVideoRequestOptions()
+            options.deliveryMode = .mediumQualityFormat
+            options.isNetworkAccessAllowed = true
+            options.progressHandler = { progress, _, _, _ in
+                Task { @MainActor in
+                    DownloadTracker.shared.updateProgress(for: id, phase: .playerItem, progress: progress)
+                }
+            }
+            
+            let reqID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, info in
+                Task { [weak self] in
+                    await self?.handleResult(id: id, item: item, info: info)
+                }
+            }
+            inFlight[id] = reqID
+            await MainActor.run {
+                Diagnostics.log("PlayerItemPrefetcher started id=\(id) reqID=\(reqID)")
+            }
+        }
+    }
+    
+    func cancel(_ assets: [PHAsset]) async {
+        guard !assets.isEmpty else { return }
+        let manager = PHImageManager.default()
+        for asset in assets {
+            let id = asset.localIdentifier
+            if let req = inFlight.removeValue(forKey: id) {
+                manager.cancelImageRequest(req)
+                await MainActor.run {
+                    Diagnostics.log("PlayerItemPrefetcher cancelled id=\(id) reqID=\(req)")
+                }
+            }
+            // Wake waiters with nil
+            if var dict = waiters.removeValue(forKey: id) {
+                for (_, cont) in dict { cont.resume(returning: nil) }
+                dict.removeAll()
+            }
+            // Drop cached item to free memory
+            cache.removeObject(forKey: id as NSString)
+        }
+    }
+    
+    // Returns a prefetched item if present or waits up to timeout for an in-flight request.
+    // On success, "takes" the item from cache so it won't be reused concurrently.
+    func item(for id: String, timeout: Duration) async -> AVPlayerItem? {
+        if let cached = cache.object(forKey: id as NSString) {
+            cache.removeObject(forKey: id as NSString)
+            return cached
+        }
+        guard inFlight[id] != nil else {
+            return nil
+        }
+        
+        let waiterID = UUID()
+        return await withTaskCancellationHandler {
+            Task { await self.cancelWaiter(for: id, waiterID: waiterID) }
+        } operation: {
+            await withCheckedContinuation { (cont: CheckedContinuation<AVPlayerItem?, Never>) in
+                Task {
+                    await registerWaiter(for: id, waiterID: waiterID, continuation: cont)
+                    Task {
+                        try? await Task.sleep(for: timeout)
+                        await timeoutWaiter(for: id, waiterID: waiterID)
+                    }
+                }
+            }
+        }
+    }
+    
+    private func registerWaiter(for id: String, waiterID: UUID, continuation: CheckedContinuation<AVPlayerItem?, Never>) {
+        var dict = waiters[id] ?? [:]
+        dict[waiterID] = continuation
+        waiters[id] = dict
+    }
+    
+    private func timeoutWaiter(for id: String, waiterID: UUID) {
+        guard var dict = waiters[id] else { return }
+        if let cont = dict.removeValue(forKey: waiterID) {
+            waiters[id] = dict.isEmpty ? nil : dict
+            cont.resume(returning: nil)
+        }
+    }
+    
+    private func cancelWaiter(for id: String, waiterID: UUID) {
+        guard var dict = waiters[id] else { return }
+        if let cont = dict.removeValue(forKey: waiterID) {
+            waiters[id] = dict.isEmpty ? nil : dict
+            cont.resume(returning: nil)
+        }
+    }
+    
+    private func handleResult(id: String, item: AVPlayerItem?, info: [AnyHashable: Any]?) async {
+        inFlight.removeValue(forKey: id)
+        
+        // If there are waiters, deliver directly and do not cache to avoid double-consumption.
+        if var dict = waiters.removeValue(forKey: id) {
+            for (_, cont) in dict {
+                cont.resume(returning: item)
+            }
+            dict.removeAll()
+        } else if let item {
+            cache.setObject(item, forKey: id as NSString)
+        }
+        
+        await MainActor.run {
+            PhotoKitDiagnostics.logResultInfo(prefix: "PlayerItemPrefetcher result", info: info)
+            if item != nil {
+                DownloadTracker.shared.updateProgress(for: id, phase: .playerItem, progress: 1.0)
+            }
+        }
+    }
+}
+
+@MainActor
+final class PlayerItemPrefetcher {
+    static let shared = PlayerItemPrefetcher()
+    private let store = PlayerItemPrefetchStore()
+    
+    func prefetch(_ assets: [PHAsset]) {
+        Task { await store.prefetch(assets) }
+    }
+    
+    func cancel(_ assets: [PHAsset]) {
+        Task { await store.cancel(assets) }
+    }
+    
+    func item(for id: String, timeout: Duration) async -> AVPlayerItem? {
+        await store.item(for: id, timeout: timeout)
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/PlayerLayerView.swift b/Video Feed Test/PlayerLayerView.swift
new file mode 100644
index 0000000..f9982b0
--- /dev/null
+++ b/Video Feed Test/PlayerLayerView.swift	
@@ -0,0 +1,30 @@
+import SwiftUI
+import AVFoundation
+import UIKit
+
+final class PlayerLayerView: UIView {
+    override class var layerClass: AnyClass { AVPlayerLayer.self }
+    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
+}
+
+struct PlayerLayerContainer: UIViewRepresentable {
+    let player: AVPlayer
+    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
+    
+    func makeUIView(context: Context) -> PlayerLayerView {
+        let v = PlayerLayerView()
+        v.backgroundColor = .black
+        v.playerLayer.player = player
+        v.playerLayer.videoGravity = videoGravity
+        return v
+    }
+    
+    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
+        if uiView.playerLayer.player !== player {
+            uiView.playerLayer.player = player
+        }
+        if uiView.playerLayer.videoGravity != videoGravity {
+            uiView.playerLayer.videoGravity = videoGravity
+        }
+    }
+}
diff --git a/Video Feed Test/Scripts/generate-dev-token.js b/Video Feed Test/Scripts/generate-dev-token.js
new file mode 100644
index 0000000..74f0d8b
--- /dev/null
+++ b/Video Feed Test/Scripts/generate-dev-token.js	
@@ -0,0 +1,62 @@
+/**
+ * Apple Music Developer Token generator (ES256)
+ *
+ * Usage (env vars recommended):
+ *   TEAM_ID=AAAAA KEY_ID=BBBBB P8=/absolute/path/AuthKey_BBBBB.p8 TTL_DAYS=30 node generate-dev-token.js
+ *
+ * Or edit the constants below (env vars still override):
+ *   node generate-dev-token.js
+ *
+ * Verifying the token:
+ *   curl -H "Authorization: Bearer <TOKEN>" \
+ *     "https://api.music.apple.com/v1/catalog/us/search?term=beatles&types=songs&limit=1"
+ */
+
+const fs = require('fs');
+const jwt = require('jsonwebtoken');
+
+// Optional inline defaults (override with env vars)
+const DEFAULTS = {
+  TEAM_ID: 'YOUR_TEAM_ID',
+  KEY_ID: 'YOUR_KEY_ID',
+  P8: '/absolute/path/to/AuthKey_KEYID.p8',
+  TTL_DAYS: 30
+};
+
+const TEAM_ID = process.env.TEAM_ID || DEFAULTS.TEAM_ID;
+const KEY_ID = process.env.KEY_ID || DEFAULTS.KEY_ID;
+const PRIVATE_KEY_P8_PATH = process.env.P8 || DEFAULTS.P8;
+const TTL_DAYS = Number(process.env.TTL_DAYS || DEFAULTS.TTL_DAYS);
+
+if (!TEAM_ID || TEAM_ID === 'YOUR_TEAM_ID') {
+  console.error('ERROR: TEAM_ID is not set. Set TEAM_ID env var or edit DEFAULTS.TEAM_ID.');
+  process.exit(1);
+}
+if (!KEY_ID || KEY_ID === 'YOUR_KEY_ID') {
+  console.error('ERROR: KEY_ID is not set. Set KEY_ID env var or edit DEFAULTS.KEY_ID.');
+  process.exit(1);
+}
+if (!PRIVATE_KEY_P8_PATH || PRIVATE_KEY_P8_PATH.startsWith('/absolute/path')) {
+  console.error('ERROR: P8 path is not set. Set P8 env var or edit DEFAULTS.P8 with an absolute path.');
+  process.exit(1);
+}
+if (!fs.existsSync(PRIVATE_KEY_P8_PATH)) {
+  console.error(`ERROR: .p8 file not found at ${PRIVATE_KEY_P8_PATH}`);
+  process.exit(1);
+}
+
+const now = Math.floor(Date.now() / 1000);
+const exp = now + (TTL_DAYS * 24 * 60 * 60); // Max 6 months total
+
+const privateKey = fs.readFileSync(PRIVATE_KEY_P8_PATH, 'utf8');
+
+const token = jwt.sign(
+  { iss: TEAM_ID, iat: now, exp },
+  privateKey,
+  { algorithm: 'ES256', header: { alg: 'ES256', kid: KEY_ID } }
+);
+
+console.log(token);
+console.error(`Generated token valid for ${TTL_DAYS} day(s). Expires at: ${new Date(exp * 1000).toISOString()}`);
+console.error('Verify with:');
+console.error('curl -H "Authorization: Bearer <TOKEN>" "https://api.music.apple.com/v1/catalog/us/search?term=beatles&types=songs&limit=1"');
\ No newline at end of file
diff --git a/Video Feed Test/SettingsView.swift b/Video Feed Test/SettingsView.swift
new file mode 100644
index 0000000..a18c97f
--- /dev/null
+++ b/Video Feed Test/SettingsView.swift	
@@ -0,0 +1,94 @@
+import SwiftUI
+import StoreKit
+
+struct SettingsView: View {
+    @EnvironmentObject private var settings: AppSettings
+    @ObservedObject var appleMusic: MusicLibraryModel
+    
+    var body: some View {
+        NavigationView {
+            Form {
+                Section("Overlay") {
+                    Toggle("Show download overlay", isOn: $settings.showDownloadOverlay)
+                }
+
+                Section("Media") {
+                    NavigationLink {
+                        CurrentMonthGridView()
+                    } label: {
+                        Label("This Month (Grid)", systemImage: "calendar")
+                    }
+                }
+
+                Section("YouTube Likes") {
+                    if appleMusic.isGoogleConnected {
+                        if appleMusic.isGoogleSyncing {
+                            HStack(spacing: 8) {
+                                ProgressView()
+                                Text("Syncing…")
+                            }
+                        } else {
+                            HStack {
+                                Button {
+                                    appleMusic.retryGoogleSync()
+                                } label: {
+                                    Label("Sync Now", systemImage: "arrow.clockwise.circle")
+                                }
+                                Spacer()
+                                Button(role: .destructive) {
+                                    appleMusic.disconnectGoogle()
+                                } label: {
+                                    Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
+                                }
+                            }
+                            if let last = appleMusic.lastGoogleSyncAt {
+                                Text("Connected to Google. Last synced \(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())).")
+                                    .font(.footnote)
+                                    .foregroundStyle(.secondary)
+                            } else {
+                                Text("Connected to Google.")
+                                    .font(.footnote)
+                                    .foregroundStyle(.secondary)
+                            }
+                        }
+                        if let msg = appleMusic.googleStatusMessage, !msg.isEmpty {
+                            Text(msg).font(.footnote).foregroundStyle(.secondary)
+                        }
+                    } else {
+                        if appleMusic.isGoogleSyncing {
+                            HStack(spacing: 8) {
+                                ProgressView()
+                                Text("Connecting…")
+                            }
+                        } else {
+                            Button {
+                                appleMusic.connectGoogle()
+                            } label: {
+                                Label("Connect Google Account", systemImage: "g.circle")
+                            }
+                        }
+                        if let msg = appleMusic.googleStatusMessage, !msg.isEmpty {
+                            Text(msg).font(.footnote).foregroundStyle(.secondary)
+                        }
+                    }
+                }
+
+                Section("Trash") {
+                    NavigationLink {
+                        DeletedVideosView()
+                    } label: {
+                        HStack {
+                            Label("Deleted videos", systemImage: "trash")
+                            Spacer()
+                            DeletedCountBadge()
+                        }
+                    }
+                }
+            }
+            .navigationTitle("Settings")
+            .task {
+                appleMusic.bootstrap()
+            }
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/ShareSheet.swift b/Video Feed Test/ShareSheet.swift
new file mode 100644
index 0000000..a05c71b
--- /dev/null
+++ b/Video Feed Test/ShareSheet.swift	
@@ -0,0 +1,81 @@
+import SwiftUI
+import UIKit
+
+@MainActor
+struct ShareSheetPresenter: UIViewControllerRepresentable {
+    @Binding var isPresented: Bool
+    let activityItems: [Any]
+    let applicationActivities: [UIActivity]?
+    let excludedActivityTypes: [UIActivity.ActivityType]?
+    let detents: [UISheetPresentationController.Detent]
+    let completion: UIActivityViewController.CompletionWithItemsHandler?
+
+    final class Coordinator {
+        var controller: UIActivityViewController?
+    }
+
+    func makeCoordinator() -> Coordinator { Coordinator() }
+
+    func makeUIViewController(context: Context) -> UIViewController {
+        let host = UIViewController()
+        host.view.isHidden = true
+        return host
+    }
+
+    func updateUIViewController(_ host: UIViewController, context: Context) {
+        if isPresented, context.coordinator.controller == nil, !activityItems.isEmpty {
+            let vc = UIActivityViewController(activityItems: activityItems,
+                                              applicationActivities: applicationActivities)
+            vc.excludedActivityTypes = excludedActivityTypes
+
+            if let sheet = vc.sheetPresentationController {
+                sheet.detents = detents
+                sheet.prefersEdgeAttachedInCompactHeight = true
+                sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
+                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
+            }
+
+            vc.completionWithItemsHandler = { activityType, completed, items, error in
+                completion?(activityType, completed, items, error)
+                self.isPresented = false
+                context.coordinator.controller = nil
+            }
+
+            if let pop = vc.popoverPresentationController {
+                pop.sourceView = host.view
+                pop.sourceRect = CGRect(x: host.view.bounds.midX,
+                                        y: host.view.bounds.maxY,
+                                        width: 1, height: 1)
+                pop.permittedArrowDirections = []
+            }
+
+            host.present(vc, animated: true)
+            context.coordinator.controller = vc
+        } else if !isPresented, let presented = context.coordinator.controller {
+            presented.dismiss(animated: true)
+            context.coordinator.controller = nil
+        }
+    }
+}
+
+extension View {
+    func systemShareSheet(
+        isPresented: Binding<Bool>,
+        items: [Any],
+        applicationActivities: [UIActivity]? = nil,
+        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
+        detents: [UISheetPresentationController.Detent] = [.medium(), .large()],
+        onComplete: UIActivityViewController.CompletionWithItemsHandler? = nil
+    ) -> some View {
+        background(
+            ShareSheetPresenter(
+                isPresented: isPresented,
+                activityItems: items,
+                applicationActivities: applicationActivities,
+                excludedActivityTypes: excludedActivityTypes,
+                detents: detents,
+                completion: onComplete
+            )
+        )
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/Sharing/PHAsset+Export.swift b/Video Feed Test/Sharing/PHAsset+Export.swift
new file mode 100644
index 0000000..dad3cbb
--- /dev/null
+++ b/Video Feed Test/Sharing/PHAsset+Export.swift	
@@ -0,0 +1,100 @@
+import Photos
+import AVFoundation
+import UIKit
+
+extension PHAsset {
+    static func exportVideoToTempURL(_ asset: PHAsset) async throws -> URL {
+        if asset.mediaType != .video {
+            throw NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "Asset is not a video"])
+        }
+
+        let avAsset: AVAsset? = await withCheckedContinuation { (cont: CheckedContinuation<AVAsset?, Never>) in
+            let opts = PHVideoRequestOptions()
+            opts.deliveryMode = .highQualityFormat
+            opts.isNetworkAccessAllowed = true
+            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { a, _, _ in
+                cont.resume(returning: a)
+            }
+        }
+        guard let avAsset else {
+            throw NSError(domain: "Export", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to load AVAsset"])
+        }
+
+        let presets = AVAssetExportSession.exportPresets(compatibleWith: avAsset)
+        let preset = presets.contains(AVAssetExportPresetPassthrough) ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
+        guard let export = AVAssetExportSession(asset: avAsset, presetName: preset) else {
+            throw NSError(domain: "Export", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"])
+        }
+
+        let fm = FileManager.default
+        let tmp = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
+        if fm.fileExists(atPath: tmp.path) {
+            try? fm.removeItem(at: tmp)
+        }
+        export.outputURL = tmp
+        if export.supportedFileTypes.contains(.mp4) {
+            export.outputFileType = .mp4
+        } else if export.supportedFileTypes.contains(.mov) {
+            export.outputFileType = .mov
+        } else {
+            export.outputFileType = export.supportedFileTypes.first
+        }
+        export.shouldOptimizeForNetworkUse = true
+        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
+            export.exportAsynchronously {
+                switch export.status {
+                case .completed:
+                    cont.resume(returning: tmp)
+                case .failed:
+                    cont.resume(throwing: export.error ?? NSError(domain: "Export", code: -5, userInfo: [NSLocalizedDescriptionKey: "Export failed"]))
+                case .cancelled:
+                    cont.resume(throwing: NSError(domain: "Export", code: -6, userInfo: [NSLocalizedDescriptionKey: "Export cancelled"]))
+                default:
+                    cont.resume(throwing: NSError(domain: "Export", code: -7, userInfo: [NSLocalizedDescriptionKey: "Export unknown state"]))
+                }
+            }
+        }
+    }
+
+    private static func sanitizeFilename(_ name: String) -> String {
+        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
+        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
+        return cleaned.isEmpty ? "\(UUID().uuidString).mov" : cleaned
+    }
+}
+
+extension PHAsset {
+    static func firstFrameImage(for asset: PHAsset, maxDimension: CGFloat) async -> UIImage? {
+        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
+            let opts = PHVideoRequestOptions()
+            opts.deliveryMode = .highQualityFormat
+            opts.isNetworkAccessAllowed = true
+            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
+                guard let avAsset else {
+                    cont.resume(returning: nil)
+                    return
+                }
+                let gen = AVAssetImageGenerator(asset: avAsset)
+                gen.appliesPreferredTrackTransform = true
+                gen.requestedTimeToleranceBefore = .zero
+                gen.requestedTimeToleranceAfter = .zero
+                gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
+                let cg = try? gen.copyCGImage(at: .zero, actualTime: nil)
+                cont.resume(returning: cg.map { UIImage(cgImage: $0) })
+            }
+        }
+    }
+
+    static func firstFrameImage(fromVideoAt url: URL, maxDimension: CGFloat) -> UIImage? {
+        let asset = AVAsset(url: url)
+        let gen = AVAssetImageGenerator(asset: asset)
+        gen.appliesPreferredTrackTransform = true
+        gen.requestedTimeToleranceBefore = .zero
+        gen.requestedTimeToleranceAfter = .zero
+        gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
+        if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
+            return UIImage(cgImage: cg)
+        }
+        return nil
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/Sharing/VideoShareItemSource.swift b/Video Feed Test/Sharing/VideoShareItemSource.swift
new file mode 100644
index 0000000..1aea56e
--- /dev/null
+++ b/Video Feed Test/Sharing/VideoShareItemSource.swift	
@@ -0,0 +1,34 @@
+import UIKit
+import LinkPresentation
+
+final class VideoShareItemSource: NSObject, UIActivityItemSource {
+    private let url: URL
+    private let title: String?
+    private let previewImage: UIImage?
+
+    init(url: URL, title: String?, previewImage: UIImage?) {
+        self.url = url
+        self.title = title
+        self.previewImage = previewImage
+        super.init()
+    }
+
+    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
+        return url
+    }
+
+    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
+        return url
+    }
+
+    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
+        let meta = LPLinkMetadata()
+        if let title { meta.title = title }
+        if let image = previewImage {
+            meta.iconProvider = NSItemProvider(object: image)
+            meta.imageProvider = NSItemProvider(object: image)
+        }
+        meta.originalURL = url
+        return meta
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/SingleAssetPlayer.swift b/Video Feed Test/SingleAssetPlayer.swift
new file mode 100644
index 0000000..0142184
--- /dev/null
+++ b/Video Feed Test/SingleAssetPlayer.swift	
@@ -0,0 +1,386 @@
+import Foundation
+import SwiftUI
+import AVFoundation
+import Photos
+import QuartzCore
+import UIKit
+import Combine
+import MediaPlayer
+
+@MainActor
+final class SingleAssetPlayer: ObservableObject {
+    let player = AVPlayer()
+    
+    private var pendingRequestID: PHImageRequestID = PHInvalidImageRequestID
+    private var endObserver: NSObjectProtocol?
+    private var statusObserver: NSKeyValueObservation?
+    private var likelyToKeepUpObserver: NSKeyValueObservation?
+    private var appActiveObserver: NSObjectProtocol?
+    private var appInactiveObserver: NSObjectProtocol?
+    private var timeObserver: Any?
+    @Published var hasPresentedFirstFrame: Bool = false
+
+    private var loadTask: Task<Void, Never>?
+    private var currentAssetID: String?
+    private var isActive: Bool = false
+
+    private var diagProbe: PlayerProbe?
+    private var diagStart: CFTimeInterval = 0
+
+    private var volumeUserCancellable: AnyCancellable?
+    private var musicCancellable: AnyCancellable?
+    private var overrideChangedObserver: NSObjectProtocol?
+    private var appliedSongID: String?
+    private var songOverrideTask: Task<Void, Never>?
+
+    init() {
+        player.automaticallyWaitsToMinimizeStalling = true
+
+        PlaybackRegistry.shared.register(player)
+        VideoVolumeManager.shared.apply(to: player)
+
+        volumeUserCancellable = VideoVolumeManager.shared.$userVolume
+            .sink { [weak self] _ in
+                self?.recomputeVolume()
+            }
+        musicCancellable = MusicPlaybackMonitor.shared.$isPlaying
+            .sink { [weak self] _ in
+                self?.recomputeVolume()
+            }
+
+        appActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
+            self?.handleAppDidBecomeActive()
+        }
+        appInactiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
+            self?.handleAppWillResignActive()
+        }
+        overrideChangedObserver = NotificationCenter.default.addObserver(forName: .videoAudioOverrideChanged, object: nil, queue: .main) { [weak self] note in
+            guard let self, let id = note.userInfo?["id"] as? String else { return }
+            if id == self.currentAssetID {
+                self.recomputeVolume()
+                self.applySongIfAny()
+            }
+        }
+    }
+
+    deinit {
+        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }
+        if let appInactiveObserver { NotificationCenter.default.removeObserver(appInactiveObserver) }
+        if let overrideChangedObserver { NotificationCenter.default.removeObserver(overrideChangedObserver) }
+        let p = player
+        Task { @MainActor in
+            PlaybackRegistry.shared.unregister(p)
+        }
+        volumeUserCancellable?.cancel()
+        volumeUserCancellable = nil
+        musicCancellable?.cancel()
+        musicCancellable = nil
+        songOverrideTask?.cancel()
+        songOverrideTask = nil
+    }
+    
+    func setAsset(_ asset: PHAsset) {
+        guard currentAssetID != asset.localIdentifier else { return }
+        cancel()
+        currentAssetID = asset.localIdentifier
+        hasPresentedFirstFrame = false
+        appliedSongID = nil
+        
+        Diagnostics.log("TikTokCell configure: \(asset.diagSummary)")
+        PlayerLeakDetector.shared.snapshotActive(log: true)
+        diagProbe = PlayerProbe(player: player, context: "TikTokCell", assetID: asset.localIdentifier)
+        diagStart = CACurrentMediaTime()
+
+        recomputeVolume()
+
+        loadTask = Task { @MainActor [weak self] in
+            guard let self else { return }
+            await self.loadAsset(asset)
+        }
+    }
+
+    func setActive(_ active: Bool) {
+        if !active { persistPlaybackPosition() }
+        isActive = active
+        if active {
+            PlaybackRegistry.shared.willPlay(player)
+        }
+        applySongIfAny()
+        updatePlaybackForCurrentState()
+    }
+
+    func togglePlay() {
+        if player.timeControlStatus == .playing {
+            player.pause()
+            AppleMusicController.shared.pauseIfManaged()
+        } else {
+            PlaybackRegistry.shared.willPlay(player)
+            player.play()
+            AppleMusicController.shared.resumeIfManaged()
+        }
+    }
+    
+    func cancel() {
+        persistPlaybackPosition()
+
+        loadTask?.cancel()
+        loadTask = nil
+
+        songOverrideTask?.cancel()
+        songOverrideTask = nil
+
+        if pendingRequestID != PHInvalidImageRequestID {
+            PHImageManager.default().cancelImageRequest(pendingRequestID)
+            pendingRequestID = PHInvalidImageRequestID
+        }
+        if let endObserver {
+            NotificationCenter.default.removeObserver(endObserver)
+            self.endObserver = nil
+        }
+        statusObserver = nil
+        likelyToKeepUpObserver = nil
+        if let timeObserver {
+            player.removeTimeObserver(timeObserver)
+            self.timeObserver = nil
+        }
+        hasPresentedFirstFrame = false
+        player.replaceCurrentItem(with: nil)
+        diagProbe = nil
+        currentAssetID = nil
+        Diagnostics.log("TikTokCell cancel")
+    }
+
+    private func persistPlaybackPosition() {
+        guard let id = currentAssetID, let item = player.currentItem else { return }
+        let time = player.currentTime()
+        let duration = item.duration
+        Task { await PlaybackPositionStore.shared.record(id: id, time: time, duration: duration) }
+    }
+
+    private func handleAppDidBecomeActive() {
+        guard isActive else { return }
+        updatePlaybackForCurrentState()
+    }
+
+    private func handleAppWillResignActive() {
+        persistPlaybackPosition()
+        player.pause()
+        AppleMusicController.shared.pauseIfManaged()
+    }
+
+    private func attachObservers(to item: AVPlayerItem) {
+        if let endObserver {
+            NotificationCenter.default.removeObserver(endObserver)
+            self.endObserver = nil
+        }
+        statusObserver = nil
+        likelyToKeepUpObserver = nil
+        
+        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
+            guard let self else { return }
+            self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
+                if self.isActive {
+                    PlaybackRegistry.shared.willPlay(self.player)
+                    self.player.play()
+                } else {
+                    self.player.pause()
+                }
+            }
+        }
+        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
+            guard let self else { return }
+            if item.status == .failed {
+                self.player.replaceCurrentItem(with: nil)
+            } else if item.status == .readyToPlay {
+                if let id = self.currentAssetID {
+                    DownloadTracker.shared.markPlaybackReady(id: id)
+                    NotificationCenter.default.post(name: .videoPlaybackItemReady, object: nil, userInfo: ["id": id])
+                }
+                Task { @MainActor [weak self] in
+                    guard let self else { return }
+                    if let id = self.currentAssetID, let pos = await PlaybackPositionStore.shared.position(for: id, duration: item.duration) {
+                        self.player.seek(to: pos, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
+                            self.updatePlaybackForCurrentState()
+                        }
+                    } else {
+                        self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
+                            self.updatePlaybackForCurrentState()
+                        }
+                    }
+                }
+            }
+        }
+        likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .initial]) { [weak self] _, _ in
+            self?.updatePlaybackForCurrentState()
+        }
+    }
+
+    private func updatePlaybackForCurrentState() {
+        guard let item = player.currentItem else { return }
+        if item.status != .readyToPlay {
+            return
+        }
+        if isActive {
+            if item.isPlaybackLikelyToKeepUp {
+                PlaybackRegistry.shared.willPlay(player)
+                player.play()
+            } else {
+                player.pause()
+            }
+        } else {
+            player.pause()
+        }
+    }
+
+    private func applyItem(_ item: AVPlayerItem) {
+        attachObservers(to: item)
+        player.replaceCurrentItem(with: item)
+        item.preferredForwardBufferDuration = 2.0
+        if let timeObserver {
+            player.removeTimeObserver(timeObserver)
+            self.timeObserver = nil
+        }
+        hasPresentedFirstFrame = false
+        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
+            guard let self else { return }
+            if !self.hasPresentedFirstFrame, t.seconds > 0 {
+                self.hasPresentedFirstFrame = true
+                if let timeObserver = self.timeObserver {
+                    self.player.removeTimeObserver(timeObserver)
+                    self.timeObserver = nil
+                }
+            }
+        }
+    }
+
+    private func loadAsset(_ asset: PHAsset) async {
+        if let warm = await VideoPrefetcher.shared.asset(for: asset.localIdentifier, timeout: .milliseconds(450)) {
+            diagProbe?.startPhase("TikTok_UsePrefetchedAsset")
+            let item = AVPlayerItem(asset: warm)
+            diagProbe?.attach(item: item)
+            applyItem(item)
+            diagProbe?.endPhase("TikTok_UsePrefetchedAsset")
+            return
+        }
+
+        let options = PHVideoRequestOptions()
+        options.deliveryMode = .mediumQualityFormat
+        options.isNetworkAccessAllowed = true
+        options.progressHandler = { progress, _, _, _ in
+            Task { @MainActor in
+                DownloadTracker.shared.updateProgress(for: asset.localIdentifier, phase: .playerItem, progress: progress)
+            }
+        }
+
+        diagProbe?.startPhase("TikTok_RequestPlayerItem")
+        let (item, info) = await requestPlayerItemAsync(for: asset, options: options)
+        let dt = CACurrentMediaTime() - self.diagStart
+        Diagnostics.log("TikTokCell requestPlayerItem finished in \(String(format: "%.3f", dt))s")
+        PhotoKitDiagnostics.logResultInfo(prefix: "TikTokCell request info", info: info)
+        diagProbe?.endPhase("TikTok_RequestPlayerItem")
+
+        guard !Task.isCancelled else { return }
+        if let item {
+            diagProbe?.attach(item: item)
+            applyItem(item)
+        } else {
+            self.player.replaceCurrentItem(with: nil)
+        }
+    }
+
+    private func requestPlayerItemAsync(for asset: PHAsset, options: PHVideoRequestOptions) async -> (AVPlayerItem?, [AnyHashable: Any]?) {
+        await withTaskCancellationHandler(operation: {
+            await withCheckedContinuation { (cont: CheckedContinuation<(AVPlayerItem?, [AnyHashable: Any]?), Never>) in
+                let reqID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, info in
+                    cont.resume(returning: (item, info))
+                }
+                self.pendingRequestID = reqID
+            }
+        }, onCancel: {
+            Task { @MainActor in
+                if self.pendingRequestID != PHInvalidImageRequestID {
+                    PHImageManager.default().cancelImageRequest(self.pendingRequestID)
+                    self.pendingRequestID = PHInvalidImageRequestID
+                }
+            }
+        })
+    }
+
+    private func recomputeVolume() {
+        let baseVolumeTask = Task { () -> Float in
+            if let id = self.currentAssetID, let per = await VideoAudioOverrides.shared.volumeOverride(for: id) {
+                return per
+            }
+            return VideoVolumeManager.shared.userVolume
+        }
+        Task { @MainActor [weak self] in
+            guard let self else { return }
+            let base = await baseVolumeTask.value
+            let effective: Float
+            if MusicPlaybackMonitor.shared.isPlaying {
+                effective = min(base, VideoVolumeManager.shared.duckingCapWhileMusic)
+            } else {
+                effective = base
+            }
+            self.player.volume = effective
+        }
+    }
+
+    private func applySongIfAny() {
+        songOverrideTask?.cancel()
+        songOverrideTask = nil
+
+        guard isActive else {
+            if AppleMusicController.shared.hasActiveManagedPlayback {
+                AppleMusicController.shared.pauseIfManaged()
+            }
+            return
+        }
+
+        guard let id = currentAssetID else {
+            if AppleMusicController.shared.hasActiveManagedPlayback {
+                AppleMusicController.shared.pauseIfManaged()
+                AppleMusicController.shared.stopManaging()
+            }
+            appliedSongID = nil
+            return
+        }
+
+        let requestID = id
+        songOverrideTask = Task { [weak self] in
+            guard let self else { return }
+            let ref = await VideoAudioOverrides.shared.songReference(for: requestID)
+            guard !Task.isCancelled else { return }
+            await MainActor.run { [self] in
+                guard self.isActive, self.currentAssetID == requestID else { return }
+                self.updateAppleMusicPlayback(reference: ref)
+            }
+        }
+    }
+
+    @MainActor
+    private func updateAppleMusicPlayback(reference: SongReference?) {
+        if let reference {
+            if let storeID = reference.appleMusicStoreID, appliedSongID == storeID {
+                Diagnostics.log("UpdateAM same storeID=\(storeID) -> resumeIfManaged; nowPlaying=\(AppleMusicController.shared.managedNowPlayingStoreID() ?? "nil")")
+                if AppleMusicController.shared.hasActiveManagedPlayback {
+                    AppleMusicController.shared.resumeIfManaged()
+                } else {
+                    AppleMusicController.shared.play(reference: reference)
+                }
+            } else {
+                Diagnostics.log("UpdateAM play reference=\(reference.debugKey)")
+                AppleMusicController.shared.play(reference: reference)
+                appliedSongID = reference.appleMusicStoreID
+                Diagnostics.log("UpdateAM after play nowPlaying=\(AppleMusicController.shared.managedNowPlayingStoreID() ?? "nil")")
+            }
+        } else {
+            if AppleMusicController.shared.hasActiveManagedPlayback {
+                Diagnostics.log("UpdateAM no reference -> pause/stop")
+                AppleMusicController.shared.pauseIfManaged()
+                AppleMusicController.shared.stopManaging()
+            }
+            appliedSongID = nil
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/SongMatcher.swift b/Video Feed Test/SongMatcher.swift
new file mode 100644
index 0000000..2daf1a7
--- /dev/null
+++ b/Video Feed Test/SongMatcher.swift	
@@ -0,0 +1,103 @@
+import Foundation
+import MediaPlayer
+
+actor SongMatcher {
+    static let shared = SongMatcher()
+
+    func match(tracks: [YouTubeTrack], limit: Int = 3) async throws -> [MPMediaItem] {
+        var results: [(MPMediaItem, Double)] = []
+
+        for track in tracks {
+            if let best = Self.findBestMatch(track: track) {
+                results.append(best)
+            }
+        }
+
+        let sorted = results
+            .sorted { $0.1 > $1.1 }
+            .map { $0.0 }
+
+        var unique: [MPMediaItem] = []
+        var seen = Set<MPMediaEntityPersistentID>()
+        for item in sorted {
+            if !seen.contains(item.persistentID) {
+                unique.append(item)
+                seen.insert(item.persistentID)
+            }
+            if unique.count >= limit { break }
+        }
+        return unique
+    }
+
+    private static func findBestMatch(track: YouTubeTrack) -> (MPMediaItem, Double)? {
+        let title = normalize(track.title)
+        let artist = normalize(track.artist)
+
+        var preds: [MPMediaPropertyPredicate] = []
+        if !title.isEmpty {
+            preds.append(MPMediaPropertyPredicate(value: track.title, forProperty: MPMediaItemPropertyTitle, comparisonType: .contains))
+        }
+        if !artist.isEmpty {
+            preds.append(MPMediaPropertyPredicate(value: track.artist, forProperty: MPMediaItemPropertyArtist, comparisonType: .contains))
+        }
+
+        let query = MPMediaQuery.songs()
+        for p in preds {
+            query.addFilterPredicate(p)
+        }
+
+        guard let items = query.items, !items.isEmpty else { return nil }
+
+        var bestItem: MPMediaItem?
+        var bestScore: Double = 0
+
+        for item in items {
+            let iTitle = normalize(item.title ?? "")
+            let iArtist = normalize(item.artist ?? "")
+            let titleScore = jaccard(wordsA: words(from: title), wordsB: words(from: iTitle))
+            let artistScore = jaccard(wordsA: words(from: artist), wordsB: words(from: iArtist))
+            var score = 0.7 * titleScore + 0.3 * artistScore
+
+            if let d = track.duration, d > 1, item.playbackDuration > 1 {
+                let delta = abs(d - item.playbackDuration)
+                if delta <= 3 { score += 0.2 }
+                else if delta <= 8 { score += 0.1 }
+                else if delta > 20 { score -= 0.2 }
+            }
+
+            if score > bestScore {
+                bestScore = score
+                bestItem = item
+            }
+        }
+
+        if let bestItem, bestScore >= 0.45 {
+            return (bestItem, bestScore)
+        }
+        return nil
+    }
+
+    private static func normalize(_ s: String) -> String {
+        var out = s.lowercased()
+        let removals = ["(official video)", "(official audio)", "(lyrics)", "[official video]", "[official audio]", "[lyrics]"]
+        removals.forEach { out = out.replacingOccurrences(of: $0, with: "") }
+        out = out.replacingOccurrences(of: "’", with: "'")
+        out = out.replacingOccurrences(of: "“", with: "\"")
+        out = out.replacingOccurrences(of: "”", with: "\"")
+        out = out.replacingOccurrences(of: "&", with: "and")
+        out = out.replacingOccurrences(of: "-", with: " ")
+        out = out.replacingOccurrences(of: "_", with: " ")
+        return out.trimmingCharacters(in: .whitespacesAndNewlines)
+    }
+
+    private static func words(from s: String) -> Set<String> {
+        Set(s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 })
+    }
+
+    private static func jaccard(wordsA: Set<String>, wordsB: Set<String>) -> Double {
+        if wordsA.isEmpty || wordsB.isEmpty { return 0 }
+        let inter = wordsA.intersection(wordsB).count
+        let uni = wordsA.union(wordsB).count
+        return Double(inter) / Double(uni)
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/SongReference.swift b/Video Feed Test/SongReference.swift
new file mode 100644
index 0000000..f439be7
--- /dev/null
+++ b/Video Feed Test/SongReference.swift	
@@ -0,0 +1,31 @@
+import Foundation
+
+enum SongServiceKind: String, Codable, Sendable {
+    case appleMusic
+    case spotify
+    case youtubeMusic
+}
+
+struct SongReference: Codable, Equatable, Hashable, Sendable {
+    var service: SongServiceKind
+    var universalISRC: String?
+    var appleMusicStoreID: String?
+    var spotifyID: String?
+    var title: String?
+    var artist: String?
+
+    static func appleMusic(storeID: String, title: String? = nil, artist: String? = nil, isrc: String? = nil) -> SongReference {
+        SongReference(service: .appleMusic, universalISRC: isrc, appleMusicStoreID: storeID, spotifyID: nil, title: title, artist: artist)
+    }
+
+    var debugKey: String {
+        switch service {
+        case .appleMusic:
+            return "apple:\(appleMusicStoreID ?? "nil")|isrc:\(universalISRC ?? "nil")"
+        case .spotify:
+            return "spotify:\(spotifyID ?? "nil")|isrc:\(universalISRC ?? "nil")"
+        case .youtubeMusic:
+            return "ytm|isrc:\(universalISRC ?? "nil")"
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/TikTokFeedView.swift b/Video Feed Test/TikTokFeedView.swift
new file mode 100644
index 0000000..f815d85
--- /dev/null
+++ b/Video Feed Test/TikTokFeedView.swift	
@@ -0,0 +1,647 @@
+import SwiftUI
+import Photos
+import UIKit
+
+struct TikTokFeedView: View {
+    @Environment(\.dismiss) private var dismiss
+    @StateObject private var viewModel: TikTokFeedViewModel
+    @State private var index: Int = 0
+    @Environment(\.scenePhase) private var scenePhase
+    @State private var didSetInitialIndex = false
+    @State private var readyVideoIDs: Set<String> = []
+    @State private var isSharing = false
+    @State private var shareItems: [Any] = []
+    @State private var isPreparingShare = false
+    @State private var shareTempURLs: [URL] = []
+    @State private var pendingShareURL: URL?
+    @State private var showSettings = false
+
+    @StateObject private var options = OptionsCoordinator()
+    @State private var isPagingInteracting = false
+
+    @StateObject private var appleMusic = MusicLibraryModel()
+    @State private var showDateActions = false
+    @State private var isQuickPanelExpanded = false
+    @Namespace private var quickGlassNS
+
+    init(mode: TikTokFeedViewModel.FeedMode) {
+        _viewModel = StateObject(wrappedValue: TikTokFeedViewModel(mode: mode))
+    }
+    
+    var body: some View {
+        ZStack {
+            if viewModel.authorization == .denied || viewModel.authorization == .restricted {
+                deniedView
+            } else if viewModel.isLoading {
+                ProgressView().scaleEffect(1.2)
+            } else if viewModel.items.isEmpty {
+                emptyView
+            } else {
+                PagedCollectionView(items: viewModel.items,
+                                    index: $index,
+                                    id: { $0.id },
+                                    onPrefetch: handlePrefetch(indices:size:),
+                                    onCancelPrefetch: handleCancelPrefetch(indices:size:),
+                                    isPageReady: { idx in
+                    guard viewModel.items.indices.contains(idx) else { return true }
+                    switch viewModel.items[idx].kind {
+                    case .video(let a):
+                        return readyVideoIDs.contains(a.localIdentifier)
+                    case .photoCarousel:
+                        return true
+                    }
+                },
+                                    content: { i, item, isActive in
+                    switch item.kind {
+                    case .video(let asset):
+                        AnyView(
+                            TikTokPlayerView(
+                                asset: asset,
+                                isActive: isActive,
+                                pinnedMode: options.progress > 0.001,
+                                noCropMode: true
+                            )
+                            .id(item.id)
+                            .optionsPinnedTopTransform(progress: options.progress)
+                            .animation(options.isInteracting ? nil : .interpolatingSpring(stiffness: 220, damping: 28), value: options.progress)
+                        )
+                    case .photoCarousel(let assets):
+                        if FeatureFlags.enablePhotoPosts {
+                            AnyView(
+                                PhotoCarouselPostView(assets: assets)
+                                    .id(item.id)
+                            )
+                        } else {
+                            AnyView(
+                                EmptyView()
+                                    .id(item.id)
+                            )
+                        }
+                    }
+                },
+                                    onScrollInteracting: { interacting in
+                    isPagingInteracting = interacting
+                })
+                .ignoresSafeArea()
+                .overlay(alignment: .top) {
+                    OptionsSheet(
+                        options: options,
+                        appleMusic: appleMusic,
+                        currentAssetID: currentVideoAsset()?.localIdentifier,
+                        onDelete: { deleteCurrentVideo() },
+                        onShare: { prepareShare() },
+                        onOpenSettings: { showSettings = true }
+                    )
+                    .zIndex(2)
+                }
+                .safeAreaInset(edge: .bottom) {
+                    HStack(alignment: .bottom) {
+                       
+                        if !isQuickPanelExpanded {
+                            VStack(alignment: .leading, spacing: 6) {
+                                if let rel = relativeLabelForCurrentItem() {
+                                    Text(rel)
+                                        .font(.caption.bold())
+                                        .foregroundStyle(.white)
+                                        .padding(.horizontal, 10)
+                                        .padding(.vertical, 6)
+                                        .liquidGlass(in: Capsule())
+                                        .background(
+                                            Capsule().fill(Color.black.opacity(0.10))
+                                                .frame(maxWidth: .infinity)
+                                        )
+                                        .padding(.leading, 12)
+                                        .accessibilityHidden(true)
+                                }
+                                
+                                if let label = dateLabelForCurrentItem() {
+                                    Text(label)
+                                        .font(.caption.bold())
+                                        .foregroundStyle(.white)
+                                        .padding(.horizontal, 10)
+                                        .padding(.vertical, 6)
+                                        .liquidGlass(in: Capsule())
+                                        .background(
+                                            Capsule().fill(Color.black.opacity(0.10))
+                                                .frame(maxWidth: .infinity)
+                                        )
+                                        .padding(.leading, 12)
+                                        .accessibilityHidden(true)
+                                }
+                            }
+                            .contentShape(Rectangle())
+                            .onTapGesture {
+                                showDateActions = true
+                            }
+                            .animation(nil, value: index)
+                        }
+
+                        Spacer()
+
+                        VStack(spacing: 10) {
+                            if !isQuickPanelExpanded {
+                                OptionsDragHandle(
+                                    options: options,
+                                    openDistance: min(max(UIScreen.main.bounds.size.height * 0.22, 280), 420)
+                                )
+                                .animation(nil, value: index)
+                            }
+
+                            if !isQuickPanelExpanded {
+                                Button {
+                                    var t = Transaction()
+                                    t.animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
+                                    withTransaction(t) {
+                                        isQuickPanelExpanded = true
+                                    }
+                                } label: {
+                                    let collapsedCorner: CGFloat = 24
+                                    ZStack {
+                                        RoundedRectangle(cornerRadius: collapsedCorner, style: .continuous)
+                                            .fill(Color.black.opacity(0.28))
+                                            .liquidGlass(in: RoundedRectangle(cornerRadius: collapsedCorner, style: .continuous), stroke: false)
+                                            .matchedGeometryEffect(id: "quickGlassBG", in: quickGlassNS)
+                                        Image(systemName: "ellipsis")
+                                            .font(.system(size: 18, weight: .bold))
+                                            .foregroundStyle(.white)
+                                    }
+                                    .frame(width: 48, height: 48)
+                                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
+                                }
+                                .buttonStyle(.plain)
+                                .accessibilityLabel("Open panel")
+                            }
+                        }
+                    }
+                    .padding(.horizontal)
+                    .padding(.bottom, 8)
+                }
+            }
+        } 
+        .onAppear { 
+            viewModel.onAppear()
+            NotificationCenter.default.addObserver(forName: .videoPrefetcherDidCacheAsset, object: nil, queue: .main) { note in
+                if let id = note.userInfo?["id"] as? String {
+                    readyVideoIDs.insert(id)
+                }
+            }
+            NotificationCenter.default.addObserver(forName: .videoPlaybackItemReady, object: nil, queue: .main) { note in
+                if let id = note.userInfo?["id"] as? String {
+                    readyVideoIDs.insert(id)
+                }
+            }
+        }
+        .onDisappear {
+            viewModel.configureAudioSession(active: false)
+            NotificationCenter.default.removeObserver(self, name: .videoPrefetcherDidCacheAsset, object: nil)
+            NotificationCenter.default.removeObserver(self, name: .videoPlaybackItemReady, object: nil)
+        }
+        .onChange(of: viewModel.items.map(\.id)) { _ in
+            let currentVideoIDs = Set(viewModel.items.compactMap { item in
+                if case .video(let a) = item.kind { return a.localIdentifier }
+                return nil
+            })
+            readyVideoIDs.formIntersection(currentVideoIDs)
+
+            guard !didSetInitialIndex, !viewModel.items.isEmpty else {
+                if !viewModel.items.isEmpty {
+                    let sizePts = UIScreen.main.bounds.size
+                    prefetchWindow(around: index, sizePx: sizePts)
+                }
+                return
+            }
+            let startIndex = viewModel.initialIndexInWindow ?? 0
+            index = max(0, min(viewModel.items.count - 1, startIndex))
+            didSetInitialIndex = true
+            Diagnostics.log("TikTokFeed initial local start index=\(index)")
+            let sizePts = UIScreen.main.bounds.size
+            prefetchWindow(around: index, sizePx: sizePts)
+        }
+        .onChange(of: scenePhase) { phase in
+            Diagnostics.log("TikTokFeedView scenePhase=\(String(describing: phase))")
+            if phase == .active, let url = pendingShareURL {
+                Diagnostics.log("Share: presenting deferred sheet url=\(url.lastPathComponent)")
+                shareItems = [url]
+                shareTempURLs = [url]
+                isSharing = true
+                pendingShareURL = nil
+            }
+        }
+        .onChange(of: index) { newIndex in
+            let items = viewModel.items
+            if items.indices.contains(newIndex) {
+                if case .video(let asset) = items[newIndex].kind {
+                    CurrentPlayback.shared.currentAssetID = asset.localIdentifier
+                } else {
+                    CurrentPlayback.shared.currentAssetID = nil
+                }
+            }
+            viewModel.loadMoreIfNeeded(currentIndex: newIndex)
+            let sizePts = UIScreen.main.bounds.size
+            prefetchWindow(around: newIndex, sizePx: sizePts)
+            preheatActiveCarouselIfAny(at: newIndex)
+        }
+        .systemShareSheet(isPresented: $isSharing, items: shareItems) { _, _, _, _ in
+            for url in shareTempURLs {
+                try? FileManager.default.removeItem(at: url)
+            }
+            shareTempURLs.removeAll()
+            shareItems.removeAll()
+        }
+        .sheet(isPresented: $showSettings) {
+            SettingsView(appleMusic: appleMusic)
+        }
+        .confirmationDialog("Go to", isPresented: $showDateActions, titleVisibility: .visible) {
+            Button("Newest") {
+                didSetInitialIndex = false
+                viewModel.startFromBeginning()
+            }
+            Button("Random place") {
+                didSetInitialIndex = false
+                viewModel.loadRandomWindow()
+            }
+            Button("1 year ago") {
+                didSetInitialIndex = false
+                viewModel.jumpToOneYearAgo()
+            }
+            Button("Cancel", role: .cancel) { }
+        }
+        .overlay {
+            if isQuickPanelExpanded {
+                GeometryReader { proxy in
+                    ZStack(alignment: .bottomTrailing) {
+                        Color.black.opacity(0.20)
+                            .ignoresSafeArea()
+                            .allowsHitTesting(false)
+
+                        let panelWidth = min(proxy.size.width - 24, 380)
+                        let panelHeight = min(max(proxy.size.height * 0.32, 240), 420)
+                        let expandedCorner: CGFloat = 22
+
+                        VStack(spacing: 0) {
+                            QuickPanelContent()
+                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
+                                .padding(16)
+                                .transition(.opacity)
+                        }
+                        .frame(width: panelWidth, height: panelHeight)
+                        .background(
+                            RoundedRectangle(cornerRadius: expandedCorner, style: .continuous)
+                                .fill(Color(red: 0.07, green: 0.08, blue: 0.09).opacity(0.36))
+                                .liquidGlass(in: RoundedRectangle(cornerRadius: expandedCorner, style: .continuous), stroke: false)
+                                .matchedGeometryEffect(id: "quickGlassBG", in: quickGlassNS)
+                        )
+                        .contentShape(RoundedRectangle(cornerRadius: expandedCorner, style: .continuous))
+                        .onTapGesture {
+                            var t = Transaction()
+                            t.animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
+                            withTransaction(t) {
+                                isQuickPanelExpanded = false
+                            }
+                        }
+                        .padding(.trailing, 12)
+                        .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
+                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
+                    }
+                }
+                .transition(.opacity)
+                .zIndex(3)
+            }
+        }
+    }
+
+    private func handlePrefetch(indices: IndexSet, size: CGSize) {
+        guard !viewModel.items.isEmpty else { return }
+        var videoAssets: [PHAsset] = []
+        var photoAssetsFlat: [PHAsset] = []
+        let sorted = indices.sorted()
+        for i in sorted {
+            guard viewModel.items.indices.contains(i) else { continue }
+            switch viewModel.items[i].kind {
+            case .video(let a):
+                videoAssets.append(a)
+            case .photoCarousel(let list):
+                if FeatureFlags.enablePhotoPosts {
+                    photoAssetsFlat.append(contentsOf: list)
+                }
+            }
+        }
+        if !videoAssets.isEmpty {
+            Diagnostics.log("MixedFeed prefetch videos count=\(videoAssets.count) indices=\(sorted)")
+            VideoPrefetcher.shared.prefetch(videoAssets)
+        }
+        if FeatureFlags.enablePhotoPosts, !photoAssetsFlat.isEmpty {
+            let viewportPx = UIScreen.main.nativeBounds.size
+            let photoPx = photoTargetSizePx(for: viewportPx)
+
+            var primary: [PHAsset] = []
+            var secondary: [PHAsset] = []
+            var seen = Set<String>()
+
+            if let firstCarouselIndex = sorted.first(where: { idx in
+                guard viewModel.items.indices.contains(idx) else { return false }
+                if case .photoCarousel = viewModel.items[idx].kind { return true }
+                return false
+            }) {
+                if case .photoCarousel(let firstList) = viewModel.items[firstCarouselIndex].kind {
+                    for a in firstList where seen.insert(a.localIdentifier).inserted {
+                        primary.append(a)
+                    }
+                }
+            }
+            for i in sorted {
+                guard viewModel.items.indices.contains(i) else { continue }
+                if case .photoCarousel(let list) = viewModel.items[i].kind {
+                    for a in list where seen.insert(a.localIdentifier).inserted {
+                        secondary.append(a)
+                    }
+                }
+            }
+
+            let primaryCap = 18
+            let totalCap = 48
+            if primary.count > primaryCap { primary = Array(primary.prefix(primaryCap)) }
+            var remainderBudget = max(0, totalCap - primary.count)
+            if secondary.count > remainderBudget { secondary = Array(secondary.prefix(remainderBudget)) }
+
+            if !primary.isEmpty {
+                Diagnostics.log("MixedFeed preheat photos PRIMARY count=\(primary.count) indices=\(sorted) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
+                ImagePrefetcher.shared.preheat(primary, targetSize: photoPx)
+
+                let deepCount = min(6, primary.count)
+                if deepCount > 0 {
+                    let deepPx = scaledSize(photoPx, factor: 1.6)
+                    let deep = Array(primary.prefix(deepCount))
+                    Diagnostics.log("MixedFeed preheat photos PRIMARY-DEEP count=\(deep.count) photoTargetSize=\(Int(deepPx.width))x\(Int(deepPx.height))")
+                    ImagePrefetcher.shared.preheat(deep, targetSize: deepPx)
+                }
+            }
+            if !secondary.isEmpty {
+                Diagnostics.log("MixedFeed preheat photos SECONDARY count=\(secondary.count) indices=\(sorted) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
+                ImagePrefetcher.shared.preheat(secondary, targetSize: photoPx)
+            }
+        }
+    }
+    
+    private func handleCancelPrefetch(indices: IndexSet, size: CGSize) {
+        guard !viewModel.items.isEmpty else { return }
+        var videoAssets: [PHAsset] = []
+        var photoAssets: [PHAsset] = []
+        for i in indices {
+            guard viewModel.items.indices.contains(i) else { continue }
+            switch viewModel.items[i].kind {
+            case .video(let a):
+                videoAssets.append(a)
+            case .photoCarousel(let list):
+                if FeatureFlags.enablePhotoPosts {
+                    photoAssets.append(contentsOf: list)
+                }
+            }
+        }
+        if !videoAssets.isEmpty {
+            Diagnostics.log("MixedFeed cancel prefetch videos count=\(videoAssets.count) indices=\(Array(indices))")
+            VideoPrefetcher.shared.cancel(videoAssets)
+        }
+        if FeatureFlags.enablePhotoPosts, !photoAssets.isEmpty {
+            let viewportPx = UIScreen.main.nativeBounds.size
+            let photoPx = photoTargetSizePx(for: viewportPx)
+            Diagnostics.log("MixedFeed stop preheating photos count=\(photoAssets.count) indices=\(Array(indices)) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
+            ImagePrefetcher.shared.stopPreheating(photoAssets, targetSize: photoPx)
+        }
+    }
+    
+    private func prefetchWindow(around index: Int, sizePx: CGSize) {
+        let lookahead = 10
+        let start = max(0, index)
+        let end = min(viewModel.items.count, index + 1 + lookahead)
+        guard start < end else { return }
+        let candidates = Array(start..<end)
+        handlePrefetch(indices: IndexSet(candidates), size: sizePx)
+    }
+
+    private func preheatActiveCarouselIfAny(at index: Int) {
+        if !FeatureFlags.enablePhotoPosts { return }
+        guard viewModel.items.indices.contains(index) else { return }
+        guard case .photoCarousel(let list) = viewModel.items[index].kind else { return }
+        guard !list.isEmpty else { return }
+        let viewportPx = UIScreen.main.nativeBounds.size
+        let photoPx = photoTargetSizePx(for: viewportPx)
+        Diagnostics.log("MixedFeed preheat ACTIVE carousel count=\(list.count) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
+        ImagePrefetcher.shared.preheat(list, targetSize: photoPx)
+        let deepCount = min(6, list.count)
+        if deepCount > 0 {
+            let deepPx = scaledSize(photoPx, factor: 1.6)
+            let deep = Array(list.prefix(deepCount))
+            Diagnostics.log("MixedFeed preheat ACTIVE-DEEP count=\(deep.count) photoTargetSize=\(Int(deepPx.width))x\(Int(deepPx.height))")
+            ImagePrefetcher.shared.preheat(deep, targetSize: deepPx)
+        }
+    }
+    
+    private func photoTargetSizePx(for viewportPx: CGSize) -> CGSize {
+        let isLandscape = viewportPx.width > viewportPx.height
+        let columns: CGFloat = isLandscape ? 4 : 3
+        let cell = floor(min(viewportPx.width, viewportPx.height) / columns)
+        let edge = max(160, min(cell, 512))
+        return CGSize(width: edge, height: edge)
+    }
+
+    private func scaledSize(_ size: CGSize, factor: CGFloat) -> CGSize {
+        CGSize(width: floor(size.width * factor), height: floor(size.height * factor))
+    }
+    
+    private var deniedView: some View {
+        VStack(spacing: 16) {
+            Spacer()
+            Image(systemName: "photo.on.rectangle.angled")
+                .font(.system(size: 56))
+                .foregroundStyle(.secondary)
+            Text("Photos access needed")
+                .font(.headline)
+            Text("To browse your recent videos and photos, allow Photos access in Settings.")
+                .font(.subheadline)
+                .multilineTextAlignment(.center)
+                .foregroundStyle(.secondary)
+                .padding(.horizontal)
+            HStack(spacing: 16) {
+                Button("Open Settings") {
+                    if let url = URL(string: UIApplication.openSettingsURLString) {
+                        UIApplication.shared.open(url)
+                    }
+                }
+                .buttonStyle(.borderedProminent)
+                
+                Button("Close") {
+                    dismiss()
+                }
+                .buttonStyle(.bordered)
+            }
+            Spacer()
+        }
+        .padding()
+    }
+    
+    private var emptyView: some View {
+        VStack(spacing: 16) {
+            Spacer()
+            Image(systemName: "film")
+                .font(.system(size: 56))
+                .foregroundStyle(.secondary)
+            Text("No media found")
+                .font(.headline)
+            Text("Record or import some videos or photos to your Photos library.")
+                .font(.subheadline)
+                .multilineTextAlignment(.center)
+                .foregroundStyle(.secondary)
+                .padding(.horizontal)
+            Button("Close") {
+                dismiss()
+            }
+            .buttonStyle(.bordered)
+            Spacer()
+        }
+        .padding()
+    }
+    
+    private func currentVideoAsset() -> PHAsset? {
+        guard viewModel.items.indices.contains(index) else { return nil }
+        if case .video(let a) = viewModel.items[index].kind {
+            return a
+        }
+        return nil
+    }
+    
+    private func dateLabelForCurrentItem() -> String? {
+        guard viewModel.items.indices.contains(index) else { return nil }
+        switch viewModel.items[index].kind {
+        case .video(let a):
+            if let d = a.creationDate {
+                return Self.dateFormatter.string(from: d)
+            }
+            return nil
+        case .photoCarousel(let assets):
+            let dates = assets.compactMap(\.creationDate)
+            guard let minD = dates.min() else { return nil }
+            guard let maxD = dates.max() else { return Self.dateFormatter.string(from: minD) }
+            if Calendar.current.isDate(minD, inSameDayAs: maxD) {
+                return Self.dateFormatter.string(from: minD)
+            } else {
+                let minStr = Self.dateFormatter.string(from: minD)
+                let maxStr = Self.dateFormatter.string(from: maxD)
+                return "\(minStr) – \(maxStr)"
+            }
+        }
+    }
+
+    private func relativeLabelForCurrentItem() -> String? {
+        guard viewModel.items.indices.contains(index) else { return nil }
+        let now = Date()
+        switch viewModel.items[index].kind {
+        case .video(let a):
+            if let d = a.creationDate {
+                return Self.relativeFormatter.localizedString(for: d, relativeTo: now)
+            }
+            return nil
+        case .photoCarousel(let assets):
+            let dates = assets.compactMap(\.creationDate)
+            guard let maxD = dates.max() else { return nil }
+            return Self.relativeFormatter.localizedString(for: maxD, relativeTo: now)
+        }
+    }
+    
+    private static let dateFormatter: DateFormatter = {
+        let df = DateFormatter()
+        df.dateStyle = .medium
+        df.timeStyle = .none
+        return df
+    }()
+
+    private static let relativeFormatter: RelativeDateTimeFormatter = {
+        let rf = RelativeDateTimeFormatter()
+        rf.unitsStyle = .full
+        return rf
+    }()
+    
+    private func prepareShare() {
+        guard !isPreparingShare, let asset = currentVideoAsset() else { return }
+        isPreparingShare = true
+        Diagnostics.log("Share: start export id=\(asset.localIdentifier)")
+        UIImpactFeedbackGenerator(style: .light).impactOccurred()
+        Task(priority: .userInitiated) {
+            do {
+                let url = try await PHAsset.exportVideoToTempURL(asset)
+                Diagnostics.log("Share: export finished url=\(url.lastPathComponent)")
+                if UIApplication.shared.applicationState == .active {
+                    await MainActor.run {
+                        shareItems = [url]
+                        shareTempURLs = [url]
+                        isSharing = true
+                        isPreparingShare = false
+                    }
+                } else {
+                    await MainActor.run {
+                        pendingShareURL = url
+                        isPreparingShare = false
+                        Diagnostics.log("Share: deferred presentation (app not active)")
+                    }
+                }
+            } catch {
+                await MainActor.run {
+                    isPreparingShare = false
+                }
+                Diagnostics.log("Share: export failed error=\(String(describing: error))")
+            }
+        }
+    }
+
+    private func deleteCurrentVideo() {
+        guard let asset = currentVideoAsset() else { return }
+        let id = asset.localIdentifier
+        Diagnostics.log("Delete video: hide id=\(id)")
+        Task { @MainActor in
+            await DeletedVideosStore.shared.hide(id: id)
+            await PlaybackPositionStore.shared.clear(id: id)
+            VideoPrefetcher.shared.removeCached(for: [id])
+            if let idx = viewModel.items.firstIndex(where: { item in
+                if case .video(let a) = item.kind { return a.localIdentifier == id }
+                return false
+            }) {
+                viewModel.items.remove(at: idx)
+                if index >= viewModel.items.count {
+                    index = max(0, viewModel.items.count - 1)
+                }
+            }
+        }
+    }
+
+    private func shareURL(for asset: PHAsset) async -> URL? {
+        do {
+            let url = try await PHAsset.exportVideoToTempURL(asset)
+            return url
+        } catch {
+            return nil
+        }
+    }
+
+    private struct QuickPanelContent: View {
+        var body: some View {
+            VStack(alignment: .leading, spacing: 12) {
+                HStack(spacing: 8) {
+                    Image(systemName: "sparkles")
+                        .font(.system(size: 16, weight: .semibold))
+                        .foregroundStyle(.white.opacity(0.9))
+                    Text("Quick Panel")
+                        .font(.subheadline.weight(.semibold))
+                        .foregroundStyle(.white)
+                    Spacer()
+                }
+                RoundedRectangle(cornerRadius: 12, style: .continuous)
+                    .fill(Color.white.opacity(0.06))
+                    .frame(height: 44)
+                RoundedRectangle(cornerRadius: 12, style: .continuous)
+                    .fill(Color.white.opacity(0.06))
+                    .frame(height: 44)
+                Spacer(minLength: 0)
+            }
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/TikTokFeedViewModel.swift b/Video Feed Test/TikTokFeedViewModel.swift
new file mode 100644
index 0000000..fdd2a1b
--- /dev/null
+++ b/Video Feed Test/TikTokFeedViewModel.swift	
@@ -0,0 +1,386 @@
+import Foundation
+import SwiftUI
+import Photos
+import AVFoundation
+import Combine
+
+@MainActor
+final class TikTokFeedViewModel: ObservableObject {
+    enum FeedMode {
+        case start
+        case explore
+    }
+    
+    @Published var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
+    @Published var items: [FeedItem] = []
+    @Published var isLoading: Bool = false
+    @Published var initialIndexInWindow: Int?
+
+    private let mode: FeedMode
+
+    private var fetchVideos: PHFetchResult<PHAsset>?
+    private let pageSizeVideos = 50
+    private let pageSizePhotos = 60
+    private let prefetchThreshold = 8
+
+    private let interleaveEvery = 5
+    private let carouselMin = 3
+    private let carouselMax = 6
+    
+    private var videoCursor = 0
+    private var videosSinceLastCarousel = 0
+    private var usedPhotoIDs: Set<String> = []
+    
+    init(mode: FeedMode) {
+        self.mode = mode
+    }
+    
+    func onAppear() {
+        requestAuthorizationAndLoad()
+        Diagnostics.log("TikTokFeed onAppear")
+        PlayerLeakDetector.shared.snapshotActive(log: true)
+        configureAudioSession(active: true)
+        NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { [weak self] _ in
+            self?.handleDeletedVideosChanged()
+        }
+    }
+
+    deinit {
+        NotificationCenter.default.removeObserver(self, name: .deletedVideosChanged, object: nil)
+    }
+    
+    private func requestAuthorizationAndLoad() {
+        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
+        authorization = status
+        
+        guard status != .notDetermined else {
+            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
+                Task { @MainActor [weak self] in
+                    self?.authorization = newStatus
+                    if newStatus == .authorized || newStatus == .limited {
+                        self?.loadWindow()
+                    }
+                }
+            }
+            return
+        }
+        
+        if status == .authorized || status == .limited {
+            loadWindow()
+        }
+    }
+    
+    func reload() {
+        loadWindow()
+    }
+
+    func startFromBeginning() {
+        loadStartWindow()
+    }
+    
+    private func loadWindow() {
+        switch mode {
+        case .start:
+            loadStartWindow()
+        case .explore:
+            loadRandomWindow()
+        }
+    }
+
+    private func filterHidden(_ videos: [PHAsset]) -> [PHAsset] {
+        let hidden = DeletedVideosStore.snapshot()
+        if hidden.isEmpty { return videos }
+        return videos.filter { !hidden.contains($0.localIdentifier) }
+    }
+    
+    private func commonFetchSetup() {
+        let videoOpts = PHFetchOptions()
+        videoOpts.predicate = NSPredicate(format: "mediaType == %d AND duration >= 1.0", PHAssetMediaType.video.rawValue)
+        videoOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
+        fetchVideos = PHAsset.fetchAssets(with: videoOpts)
+        
+        videoCursor = 0
+        videosSinceLastCarousel = 0
+        usedPhotoIDs.removeAll()
+    }
+    
+    private func loadStartWindow() {
+        isLoading = true
+        commonFetchSetup()
+        
+        guard let vResult = fetchVideos, vResult.count > 0 else {
+            items = []
+            isLoading = false
+            initialIndexInWindow = nil
+            Diagnostics.log("StartWindow: no video assets")
+            return
+        }
+        
+        let vEnd = min(pageSizeVideos, vResult.count)
+        let vSliceBase = vResult.objects(at: IndexSet(integersIn: 0..<vEnd))
+        let vSlice = filterHidden(vSliceBase)
+        
+        let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
+        let carousels = makeCarousels(from: pSlice)
+        let (itemsBuilt, _, videosTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: 0)
+        
+        items = itemsBuilt
+        initialIndexInWindow = 0
+        isLoading = false
+        
+        videoCursor = vEnd
+        videosSinceLastCarousel = videosTailCount
+        markPhotosUsed(from: itemsBuilt)
+        
+        let firstID: String = {
+            if let first = itemsBuilt.first {
+                switch first.kind {
+                case .video(let a): return a.localIdentifier
+                case .photoCarousel(let arr): return arr.first?.localIdentifier ?? "n/a"
+                }
+            }
+            return "n/a"
+        }()
+        Diagnostics.log("StartWindow: videosTotal=\(vResult.count) vWindow=\(vSlice.count) carousels=\(carousels.count) first=\(firstID)")
+    }
+    
+    func loadRandomWindow() {
+        isLoading = true
+        commonFetchSetup()
+        guard let vResult = fetchVideos, vResult.count > 0 else {
+            items = []
+            isLoading = false
+            initialIndexInWindow = nil
+            Diagnostics.log("RandomWindow: no video assets")
+            return
+        }
+        let vCount = vResult.count
+        let windowSize = min(pageSizeVideos, vCount)
+        let globalRandom = Int.random(in: 0..<vCount)
+        let half = windowSize / 2
+        var start = max(0, globalRandom - half)
+        if start + windowSize > vCount {
+            start = max(0, vCount - windowSize)
+        }
+        let end = min(vCount, start + windowSize)
+        let vSliceBase = vResult.objects(at: IndexSet(integersIn: start..<end))
+        let vSlice = filterHidden(vSliceBase)
+        
+        let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
+        let carousels = makeCarousels(from: pSlice)
+        let (itemsBuilt, _, videosTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: 0)
+        
+        items = itemsBuilt
+        initialIndexInWindow = 0
+        isLoading = false
+        
+        videoCursor = end
+        videosSinceLastCarousel = videosTailCount
+        markPhotosUsed(from: itemsBuilt)
+        
+        let chosenID: String = {
+            if let first = itemsBuilt.first {
+                switch first.kind {
+                case .video(let a): return a.localIdentifier
+                case .photoCarousel(let arr): return arr.first?.localIdentifier ?? "n/a"
+                }
+            }
+            return "n/a"
+        }()
+        Diagnostics.log("RandomWindow: totalVideos=\(vCount) window=[\(start)..<\(end)] first id=\(chosenID) carousels=\(carousels.count)")
+    }
+
+    func loadWindow(around targetDate: Date) {
+        isLoading = true
+        commonFetchSetup()
+        guard let vResult = fetchVideos, vResult.count > 0 else {
+            items = []
+            isLoading = false
+            initialIndexInWindow = nil
+            Diagnostics.log("DateWindow: no video assets")
+            return
+        }
+        let vCount = vResult.count
+        var foundIndex = 0
+        for i in 0..<vCount {
+            if let d = vResult.object(at: i).creationDate, d <= targetDate {
+                foundIndex = i
+                break
+            }
+        }
+        let windowSize = min(pageSizeVideos, vCount)
+        let half = windowSize / 2
+        var start = max(0, foundIndex - half)
+        if start + windowSize > vCount {
+            start = max(0, vCount - windowSize)
+        }
+        let end = min(vCount, start + windowSize)
+        let vSliceBase = vResult.objects(at: IndexSet(integersIn: start..<end))
+        let vSlice = filterHidden(vSliceBase)
+        let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
+        let carousels = makeCarousels(from: pSlice)
+        let (itemsBuilt, _, videosTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: 0)
+
+        let clampedIndex = min(max(foundIndex, start), end - 1)
+        let selectedID = vResult.object(at: clampedIndex).localIdentifier
+        let initialLocalIndex: Int = {
+            for (idx, it) in itemsBuilt.enumerated() {
+                if case .video(let a) = it.kind, a.localIdentifier == selectedID {
+                    return idx
+                }
+            }
+            return 0
+        }()
+
+        items = itemsBuilt
+        initialIndexInWindow = initialLocalIndex
+        isLoading = false
+
+        videoCursor = end
+        videosSinceLastCarousel = videosTailCount
+        markPhotosUsed(from: itemsBuilt)
+
+        Diagnostics.log("DateWindow: target=\(targetDate) window=[\(start)..<\(end)] initialLocalIndex=\(initialLocalIndex)")
+    }
+
+    func jumpToOneYearAgo() {
+        if let date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) {
+            loadWindow(around: date)
+        } else {
+            loadRandomWindow()
+        }
+    }
+
+    func loadMoreIfNeeded(currentIndex: Int) {
+        guard let vResult = fetchVideos,
+              items.indices.contains(currentIndex),
+              currentIndex >= items.count - prefetchThreshold else { return }
+
+        let vCount = vResult.count
+        guard videoCursor < vCount else { return }
+        
+        let nextVEnd = min(vCount, videoCursor + pageSizeVideos)
+        let vSliceBase = vResult.objects(at: IndexSet(integersIn: videoCursor..<nextVEnd))
+        let vSlice = filterHidden(vSliceBase)
+        
+        let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
+        let carousels = makeCarousels(from: pSlice)
+        
+        let (appended, _, videosTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: videosSinceLastCarousel)
+        items.append(contentsOf: appended)
+        
+        markPhotosUsed(from: appended)
+        videosSinceLastCarousel = videosTailCount
+        Diagnostics.log("StartWindow: appended videos=[\(videoCursor)..<\(nextVEnd)] carouselsAdded=\(carousels.count) totalItems=\(items.count)")
+        videoCursor = nextVEnd
+    }
+    
+    func configureAudioSession(active: Bool) {
+        let session = AVAudioSession.sharedInstance()
+        do {
+            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
+            try session.setActive(active, options: [])
+        } catch {
+        }
+    }
+
+    private func handleDeletedVideosChanged() {
+        guard !items.isEmpty else { return }
+        let hidden = DeletedVideosStore.snapshot()
+        let before = items.count
+        items.removeAll { item in
+            if case .video(let a) = item.kind {
+                return hidden.contains(a.localIdentifier)
+            }
+            return false
+        }
+        if items.count != before {
+            Diagnostics.log("Feed pruned hidden videos count=\(before - items.count)")
+        }
+    }
+    
+    private func makeCarousels(from photos: [PHAsset]) -> [[PHAsset]] {
+        if !FeatureFlags.enablePhotoPosts { return [] }
+        guard !photos.isEmpty else { return [] }
+        var res: [[PHAsset]] = []
+        var i = 0
+        while i < photos.count {
+            let n = min(Int.random(in: carouselMin...carouselMax), photos.count - i)
+            let group = Array(photos[i..<(i + n)])
+            res.append(group)
+            i += n
+        }
+        return res
+    }
+    
+    private func interleave(videos: [PHAsset], carousels: [[PHAsset]], startVideoStride: Int) -> (items: [FeedItem], usedPhotos: Int, videosTailCount: Int) {
+        var out: [FeedItem] = []
+        var usedPhotos = 0
+        var cIdx = 0
+        var stride = startVideoStride
+        
+        for v in videos {
+            out.append(.video(v))
+            stride += 1
+            if FeatureFlags.enablePhotoPosts, stride >= interleaveEvery, cIdx < carousels.count {
+                let c = carousels[cIdx]
+                out.append(.carousel(c))
+                usedPhotos += c.count
+                cIdx += 1
+                stride = 0
+            }
+        }
+        return (out, usedPhotos, stride)
+    }
+    
+    private func photosAround(for videos: [PHAsset], limit: Int) -> [PHAsset] {
+        if !FeatureFlags.enablePhotoPosts { return [] }
+        let dates = videos.compactMap(\.creationDate)
+        guard let minVideoDate = dates.min(), let maxVideoDate = dates.max() else {
+            Diagnostics.log("PhotosAround: no video creation dates, skipping")
+            return []
+        }
+        let first = photosBetween(minDate: minVideoDate, maxDate: maxVideoDate, limit: limit, toleranceDays: 7)
+        if !first.isEmpty { return first }
+        let widened = photosBetween(minDate: minVideoDate, maxDate: maxVideoDate, limit: limit, toleranceDays: 30)
+        return widened
+    }
+    
+    private func photosBetween(minDate: Date, maxDate: Date, limit: Int, toleranceDays: Int) -> [PHAsset] {
+        if !FeatureFlags.enablePhotoPosts { return [] }
+        let tol: TimeInterval = Double(toleranceDays) * 24 * 60 * 60
+        let lower = minDate.addingTimeInterval(-tol)
+        let upper = maxDate.addingTimeInterval(tol)
+        
+        let opts = PHFetchOptions()
+        let screenshotMask = PHAssetMediaSubtype.photoScreenshot.rawValue
+        opts.predicate = NSPredicate(
+            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@ AND ((mediaSubtypes & %d) == 0)",
+            PHAssetMediaType.image.rawValue, lower as NSDate, upper as NSDate, screenshotMask
+        )
+        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
+        let result = PHAsset.fetchAssets(with: opts)
+        let count = Swift.min(limit, result.count)
+        guard count > 0 else {
+            Diagnostics.log("PhotosBetween: 0 results tolDays=\(toleranceDays) range=[\(lower) .. \(upper)]")
+            return []
+        }
+        let slice = result.objects(at: IndexSet(integersIn: 0..<count))
+        let filtered = slice.filter {
+            !usedPhotoIDs.contains($0.localIdentifier) && !$0.mediaSubtypes.contains(.photoScreenshot)
+        }
+        Diagnostics.log("PhotosBetween: fetched=\(slice.count) filteredUnique=\(filtered.count) tolDays=\(toleranceDays)")
+        return filtered
+    }
+    
+    private func markPhotosUsed(from feedItems: [FeedItem]) {
+        if !FeatureFlags.enablePhotoPosts { return }
+        for item in feedItems {
+            if case .photoCarousel(let arr) = item.kind {
+                for a in arr {
+                    usedPhotoIDs.insert(a.localIdentifier)
+                }
+            }
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/TikTokPlayerView.swift b/Video Feed Test/TikTokPlayerView.swift
new file mode 100644
index 0000000..ce7511e
--- /dev/null
+++ b/Video Feed Test/TikTokPlayerView.swift	
@@ -0,0 +1,145 @@
+import SwiftUI
+import AVFoundation
+import Photos
+import UIKit
+
+struct TikTokPlayerView: View {
+    let asset: PHAsset
+    let isActive: Bool
+    let pinnedMode: Bool
+    let noCropMode: Bool
+    @StateObject private var controller = SingleAssetPlayer()
+
+    @State private var placeholderImage: UIImage?
+    @State private var placeholderRequestID: PHImageRequestID = PHInvalidImageRequestID
+    @State private var showPlaceholder: Bool = true
+    @State private var placeholderTask: Task<Void, Never>?
+
+    private var isPortrait: Bool {
+        asset.pixelHeight >= asset.pixelWidth
+    }
+    private var playerVideoGravity: AVLayerVideoGravity {
+//        if noCropMode {
+//            return .resizeAspect
+//        }
+        return .resizeAspectFill
+    }
+
+    var body: some View {
+        ZStack {
+            PlayerLayerContainer(player: controller.player, videoGravity: playerVideoGravity)
+                .ignoresSafeArea()
+//            if showPlaceholder {
+//                Group {
+//                    if let img = placeholderImage {
+//                        if noCropMode {
+//                            Image(uiImage: img)
+//                                .resizable()
+//                                .scaledToFit()
+//                                .background(Color.black)
+//                                .ignoresSafeArea()
+//                        } else {
+//                            Image(uiImage: img)
+//                                .resizable()
+//                                .scaledToFill()
+//                                .ignoresSafeArea()
+//                        }
+//                    } else {
+//                        ProgressView()
+//                            .tint(.white)
+//                            .scaleEffect(1.2)
+//                    }
+//                }
+//            }
+        }
+        .contentShape(Rectangle())
+        .onTapGesture {
+            if isActive {
+                controller.togglePlay()
+            }
+        }
+        .onAppear {
+            Diagnostics.log("TikTokPlayerView onAppear for asset=\(asset.localIdentifier) isActive=\(isActive)")
+            showPlaceholder = true
+            requestPlaceholder()
+            controller.setAsset(asset)
+            controller.setActive(isActive)
+            if isActive {
+                CurrentPlayback.shared.currentAssetID = asset.localIdentifier
+            }
+        }
+        .onDisappear {
+            Diagnostics.log("TikTokPlayerView onDisappear for asset=\(asset.localIdentifier)")
+            cancelPlaceholderRequest()
+            controller.cancel()
+        }
+        .onChange(of: isActive) { newValue in
+            Diagnostics.log("TikTokPlayerView isActive changed asset=\(asset.localIdentifier) -> \(newValue)")
+            controller.setActive(newValue)
+            if newValue {
+                CurrentPlayback.shared.currentAssetID = asset.localIdentifier
+            }
+        }
+        .onChange(of: controller.hasPresentedFirstFrame) { hasFirst in
+            if hasFirst {
+                withAnimation(.easeOut(duration: 0.2)) {
+                    showPlaceholder = false
+                }
+                cancelPlaceholderRequest()
+            }
+        }
+    }
+
+    private func requestPlaceholder() {
+        cancelPlaceholderRequest()
+        placeholderTask = Task { @MainActor in
+            var producedExactFirstFrame = false
+            if let av = await VideoPrefetcher.shared.assetIfCached(asset.localIdentifier) {
+                let gen = AVAssetImageGenerator(asset: av)
+                gen.appliesPreferredTrackTransform = true
+                gen.requestedTimeToleranceBefore = .zero
+                gen.requestedTimeToleranceAfter = .zero
+                let maxDim = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
+                gen.maximumSize = CGSize(width: maxDim, height: maxDim)
+                if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
+                    self.placeholderImage = UIImage(cgImage: cg)
+                    producedExactFirstFrame = true
+                }
+            }
+
+            if producedExactFirstFrame {
+                return
+            }
+
+            let screenPx = UIScreen.main.nativeBounds.size
+            let upscalePx = CGSize(width: floor(screenPx.width * 1.25), height: floor(screenPx.height * 1.25))
+            let targetPx = CGSize(width: min(upscalePx.width, CGFloat(asset.pixelWidth)),
+                                  height: min(upscalePx.height, CGFloat(asset.pixelHeight)))
+            let opts = PHImageRequestOptions()
+            opts.deliveryMode = .opportunistic
+            opts.resizeMode = .exact
+            opts.isSynchronous = false
+            opts.isNetworkAccessAllowed = true
+            self.placeholderRequestID = PHImageManager.default().requestImage(for: asset,
+                                                                              targetSize: targetPx,
+                                                                              contentMode: .aspectFill,
+                                                                              options: opts) { image, info in
+                if let image {
+                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
+                    if !isDegraded {
+                        self.placeholderImage = image
+                    }
+                }
+            }
+        }
+    }
+
+    private func cancelPlaceholderRequest() {
+        if placeholderRequestID != PHInvalidImageRequestID {
+            PHImageManager.default().cancelImageRequest(placeholderRequestID)
+            placeholderRequestID = PHInvalidImageRequestID
+        }
+        placeholderTask?.cancel()
+        placeholderTask = nil
+    }
+}
diff --git a/Video Feed Test/VideoAudioOverrides.swift b/Video Feed Test/VideoAudioOverrides.swift
new file mode 100644
index 0000000..1bd39db
--- /dev/null
+++ b/Video Feed Test/VideoAudioOverrides.swift	
@@ -0,0 +1,113 @@
+import Foundation
+
+struct VideoAudioOverride: Codable, Equatable {
+    var volume: Float?
+    var song: SongReference?
+    var updatedAt: Date
+    var appleMusicStoreID: String?
+}
+
+extension Notification.Name {
+    static let videoAudioOverrideChanged = Notification.Name("VideoAudioOverrideChanged")
+}
+
+actor VideoAudioOverrides {
+    static let shared = VideoAudioOverrides()
+
+    private var map: [String: VideoAudioOverride] = [:]
+    private let defaultsKey = "video.audio.overrides.v1"
+    private let maxEntries = 800
+
+    init() {
+        load()
+    }
+
+    func volumeOverride(for id: String?) -> Float? {
+        guard let id, let e = map[id] else { return nil }
+        return e.volume
+    }
+
+    func songReference(for id: String?) -> SongReference? {
+        guard let id, let e = map[id] else { return nil }
+        return e.song
+    }
+
+    func songOverride(for id: String?) -> String? {
+        guard let id, let e = map[id] else { return nil }
+        if let s = e.song?.appleMusicStoreID { return s }
+        return e.appleMusicStoreID
+    }
+
+    func setVolumeOverride(for id: String, volume: Float?) {
+        var v = min(max(volume ?? 0, 0), 1)
+        if volume == nil {
+            v = 0
+        }
+        var entry = map[id] ?? VideoAudioOverride(volume: nil, song: nil, updatedAt: Date(), appleMusicStoreID: nil)
+        entry.volume = volume
+        entry.updatedAt = Date()
+        map[id] = entry
+        trimIfNeeded()
+        save()
+        notifyChanged(id: id)
+    }
+
+    func setSongReference(for id: String, reference: SongReference?) {
+        var entry = map[id] ?? VideoAudioOverride(volume: nil, song: nil, updatedAt: Date(), appleMusicStoreID: nil)
+        entry.song = reference
+        entry.updatedAt = Date()
+        entry.appleMusicStoreID = nil
+        map[id] = entry
+        trimIfNeeded()
+        save()
+        notifyChanged(id: id)
+    }
+
+    func setSongOverride(for id: String, storeID: String?) {
+        if let storeID {
+            setSongReference(for: id, reference: SongReference.appleMusic(storeID: storeID))
+        } else {
+            setSongReference(for: id, reference: nil)
+        }
+    }
+
+    private func notifyChanged(id: String) {
+        Task { @MainActor in
+            NotificationCenter.default.post(name: .videoAudioOverrideChanged, object: nil, userInfo: ["id": id])
+        }
+    }
+
+    private func save() {
+        do {
+            let data = try JSONEncoder().encode(map)
+            UserDefaults.standard.set(data, forKey: defaultsKey)
+        } catch {
+        }
+    }
+
+    private func load() {
+        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
+        do {
+            let loaded = try JSONDecoder().decode([String: VideoAudioOverride].self, from: data)
+            var migrated: [String: VideoAudioOverride] = [:]
+            for (k, var v) in loaded {
+                if v.song == nil, let legacy = v.appleMusicStoreID, !legacy.isEmpty {
+                    v.song = SongReference.appleMusic(storeID: legacy)
+                    v.appleMusicStoreID = nil
+                }
+                migrated[k] = v
+            }
+            map = migrated
+        } catch {
+            map = [:]
+        }
+    }
+
+    private func trimIfNeeded() {
+        if map.count <= maxEntries { return }
+        let sorted = map.sorted { $0.value.updatedAt < $1.value.updatedAt }
+        for (k, _) in sorted.prefix(map.count - maxEntries) {
+            map.removeValue(forKey: k)
+        }
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/VideoPrefetcher.swift b/Video Feed Test/VideoPrefetcher.swift
new file mode 100644
index 0000000..9c9ba47
--- /dev/null
+++ b/Video Feed Test/VideoPrefetcher.swift	
@@ -0,0 +1,187 @@
+import Foundation
+import Photos
+import AVFoundation
+
+actor VideoPrefetchStore {
+    private let cache = NSCache<NSString, AVAsset>()
+    private var inFlight: [String: PHImageRequestID] = [:]
+    private var waiters: [String: [UUID: CheckedContinuation<AVAsset?, Never>]] = [:]
+    private var backoffUntil: [String: Date] = [:]
+
+    init() {
+        cache.countLimit = 120
+    }
+
+    func assetIfCached(_ id: String) -> AVAsset? {
+        cache.object(forKey: id as NSString)
+    }
+
+    func prefetch(_ assets: [PHAsset]) async {
+        for asset in assets {
+            let id = asset.localIdentifier
+            if cache.object(forKey: id as NSString) != nil { continue }
+            if inFlight[id] != nil { continue }
+            if let until = backoffUntil[id], until > Date() {
+                await MainActor.run {
+                    let remaining = until.timeIntervalSinceNow
+                    Diagnostics.log("Prefetcher backoff id=\(id) remaining=\(String(format: "%.1f", max(0, remaining)))s")
+                }
+                continue
+            }
+
+            let options = PHVideoRequestOptions()
+            options.deliveryMode = .mediumQualityFormat
+            options.isNetworkAccessAllowed = true
+            options.progressHandler = { progress, _, _, _ in
+                Task { @MainActor in
+                    DownloadTracker.shared.updateProgress(for: id, phase: .prefetch, progress: progress)
+                }
+            }
+
+            let reqID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, info in
+                Task {
+                    await self?.handleResult(id: id, avAsset: avAsset, info: info)
+                }
+            }
+            inFlight[id] = reqID
+            await MainActor.run {
+                Diagnostics.log("Prefetcher started id=\(id) reqID=\(reqID)")
+            }
+        }
+    }
+
+    func cancel(_ assets: [PHAsset]) async {
+        guard !assets.isEmpty else { return }
+        let manager = PHImageManager.default()
+        for asset in assets {
+            let id = asset.localIdentifier
+            if let req = inFlight.removeValue(forKey: id) {
+                manager.cancelImageRequest(req)
+                await MainActor.run {
+                    Diagnostics.log("Prefetcher cancelled id=\(id) reqID=\(req)")
+                }
+                // Notify any waiters with nil (cancelled)
+                if var dict = waiters.removeValue(forKey: id) {
+                    for (_, cont) in dict {
+                        cont.resume(returning: nil)
+                    }
+                    dict.removeAll()
+                }
+            }
+        }
+    }
+
+    func removeCached(for ids: [String]) {
+        for id in ids {
+            cache.removeObject(forKey: id as NSString)
+        }
+    }
+
+    // Await a cached or in-flight asset up to a timeout. Returns nil on timeout/miss.
+    func asset(for id: String, timeout: Duration) async -> AVAsset? {
+        if let cached = cache.object(forKey: id as NSString) {
+            return cached
+        }
+        guard inFlight[id] != nil else {
+            return nil
+        }
+
+        let waiterID = UUID()
+        return await withTaskCancellationHandler {
+            Task { await self.cancelWaiter(for: id, waiterID: waiterID) }
+        } operation: {
+            await withCheckedContinuation { (cont: CheckedContinuation<AVAsset?, Never>) in
+                Task {
+                    await registerWaiter(for: id, waiterID: waiterID, continuation: cont)
+                    Task {
+                        try? await Task.sleep(for: timeout)
+                        await timeoutWaiter(for: id, waiterID: waiterID)
+                    }
+                }
+            }
+        }
+    }
+
+    private func registerWaiter(for id: String, waiterID: UUID, continuation: CheckedContinuation<AVAsset?, Never>) {
+        var dict = waiters[id] ?? [:]
+        dict[waiterID] = continuation
+        waiters[id] = dict
+    }
+
+    private func timeoutWaiter(for id: String, waiterID: UUID) {
+        guard var dict = waiters[id] else { return }
+        if let cont = dict.removeValue(forKey: waiterID) {
+            waiters[id] = dict.isEmpty ? nil : dict
+            cont.resume(returning: nil)
+        }
+    }
+
+    private func cancelWaiter(for id: String, waiterID: UUID) {
+        guard var dict = waiters[id] else { return }
+        if let cont = dict.removeValue(forKey: waiterID) {
+            waiters[id] = dict.isEmpty ? nil : dict
+            cont.resume(returning: nil)
+        }
+    }
+
+    private func handleResult(id: String, avAsset: AVAsset?, info: [AnyHashable: Any]?) async {
+        inFlight.removeValue(forKey: id)
+        if let avAsset {
+            cache.setObject(avAsset, forKey: id as NSString)
+            // CLEAR: success cancels backoff
+            backoffUntil[id] = nil
+            await MainActor.run {
+                Diagnostics.log("Prefetcher cached asset id=\(id)")
+                // Do not mark playback complete here; prefetch done != playback ready
+                DownloadTracker.shared.updateProgress(for: id, phase: .prefetch, progress: 1.0)
+                NotificationCenter.default.post(name: .videoPrefetcherDidCacheAsset, object: nil, userInfo: ["id": id])
+            }
+        } else {
+            // evaluate error
+            let nsErr = info?[PHImageErrorKey] as? NSError
+            let cancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true
+            let isTransientCloud = (nsErr?.domain == "CloudPhotoLibraryErrorDomain" && nsErr?.code == 1005)
+            if isTransientCloud {
+                backoffUntil[id] = Date().addingTimeInterval(10)
+            }
+            await MainActor.run {
+                PhotoKitDiagnostics.logResultInfo(prefix: "Prefetcher AVAsset nil", info: info)
+                if !cancelled && !isTransientCloud {
+                    DownloadTracker.shared.markFailed(id: id, note: nsErr?.localizedDescription)
+                }
+            }
+        }
+        if var dict = waiters.removeValue(forKey: id) {
+            for (_, cont) in dict {
+                cont.resume(returning: avAsset)
+            }
+            dict.removeAll()
+        }
+    }
+}
+
+@MainActor
+final class VideoPrefetcher {
+    static let shared = VideoPrefetcher()
+    private let store = VideoPrefetchStore()
+
+    func prefetch(_ assets: [PHAsset]) {
+        Task { await store.prefetch(assets) }
+    }
+
+    func cancel(_ assets: [PHAsset]) {
+        Task { await store.cancel(assets) }
+    }
+
+    func removeCached(for ids: [String]) {
+        Task { await store.removeCached(for: ids) }
+    }
+
+    func asset(for id: String, timeout: Duration) async -> AVAsset? {
+        await store.asset(for: id, timeout: timeout)
+    }
+
+    func assetIfCached(_ id: String) async -> AVAsset? {
+        await store.assetIfCached(id)
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/VideoVolumeManager.swift b/Video Feed Test/VideoVolumeManager.swift
new file mode 100644
index 0000000..8a7efd5
--- /dev/null
+++ b/Video Feed Test/VideoVolumeManager.swift	
@@ -0,0 +1,69 @@
+import Foundation
+import Combine
+import AVFoundation
+
+@MainActor
+final class VideoVolumeManager: ObservableObject {
+    static let shared = VideoVolumeManager()
+
+    @Published var userVolume: Float {
+        didSet {
+            if userVolume != oldValue {
+                UserDefaults.standard.set(userVolume, forKey: Self.kUserVolume)
+                recompute()
+            }
+        }
+    }
+
+    @Published private(set) var effectiveVolume: Float = 1.0
+    @Published private(set) var isMusicPlaying: Bool = false
+
+    private static let defaultUserVolume: Float = 0.03
+    private static let defaultUserVolumeWhileMusic: Float = 0.02
+
+    let duckingCapWhileMusic: Float = 0.3
+
+    private var cancellables = Set<AnyCancellable>()
+    private static let kUserVolume = "video.volume.user"
+
+    private static func clamp(_ value: Float) -> Float {
+        min(max(value, 0.0), 1.0)
+    }
+
+    private static func resolvedUserVolume(isMusicPlaying: Bool, storedVolume: Float?) -> Float {
+        if let storedVolume {
+            return clamp(storedVolume)
+        }
+        return isMusicPlaying ? defaultUserVolumeWhileMusic : defaultUserVolume
+    }
+
+    private init() {
+        let storedVolume = UserDefaults.standard.object(forKey: Self.kUserVolume) as? Float
+        let musicPlaying = MusicPlaybackMonitor.shared.isPlaying
+
+        self.userVolume = Self.resolvedUserVolume(isMusicPlaying: musicPlaying, storedVolume: storedVolume)
+        self.isMusicPlaying = musicPlaying
+
+        recompute()
+
+        MusicPlaybackMonitor.shared.$isPlaying
+            .sink { [weak self] playing in
+                guard let self else { return }
+                self.isMusicPlaying = playing
+                self.recompute()
+            }
+            .store(in: &cancellables)
+    }
+
+    private func recompute() {
+        if isMusicPlaying {
+            effectiveVolume = min(userVolume, duckingCapWhileMusic)
+        } else {
+            effectiveVolume = userVolume
+        }
+    }
+
+    func apply(to player: AVPlayer) {
+        player.volume = effectiveVolume
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/YouTubeAPI.swift b/Video Feed Test/YouTubeAPI.swift
new file mode 100644
index 0000000..9df6268
--- /dev/null
+++ b/Video Feed Test/YouTubeAPI.swift	
@@ -0,0 +1,249 @@
+import Foundation
+
+struct YouTubeTrack: Sendable {
+    let title: String
+    let artist: String
+    let duration: TimeInterval?
+}
+
+actor YouTubeAPI {
+    static let shared = YouTubeAPI()
+
+    enum APIError: LocalizedError {
+        case http(Int, String, String?)
+        case invalidResponse
+
+        var errorDescription: String? {
+            switch self {
+            case .http(let code, let message, let reason):
+                if let reason {
+                    return "YouTube API error \(code): \(message) (\(reason))"
+                } else {
+                    return "YouTube API error \(code): \(message)"
+                }
+            case .invalidResponse:
+                return "YouTube API invalid response"
+            }
+        }
+    }
+
+    func fetchRecentLikedTracks(limit: Int = 25) async throws -> [YouTubeTrack] {
+        let capped = min(max(limit, 1), 50)
+        Diagnostics.log("YouTubeAPI.fetchRecentLikedTracks: start limit=\(capped)")
+        do {
+            return try await fetchLikedViaMyRating(limit: capped)
+        } catch let APIError.http(code, _, _) where code == 400 || code == 403 || code == 404 {
+            Diagnostics.log("YouTubeAPI.fetchRecentLikedTracks: myRating fallback; code=\(code)")
+            return try await fetchLikedViaLikesPlaylist(limit: capped)
+        } catch {
+            Diagnostics.log("YouTubeAPI.fetchRecentLikedTracks: error \(error.localizedDescription)")
+            throw error
+        }
+    }
+
+    private func fetchLikedViaMyRating(limit: Int) async throws -> [YouTubeTrack] {
+        let token = try await GoogleAuth.shared.validAccessToken()
+        Diagnostics.log("YouTubeAPI.myRating: request maxResults=\(limit)")
+
+        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
+        comps.queryItems = [
+            .init(name: "part", value: "snippet,contentDetails"),
+            .init(name: "myRating", value: "like"),
+            .init(name: "maxResults", value: String(limit))
+        ]
+
+        var req = URLRequest(url: comps.url!)
+        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
+        req.setValue("application/json", forHTTPHeaderField: "Accept")
+
+        let (data, resp) = try await URLSession.shared.data(for: req)
+        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
+        guard status == 200 else {
+            let (message, reason) = Self.parseGoogleError(from: data)
+            Diagnostics.log("YouTubeAPI.myRating: http \(status) message=\(String(describing: message)) reason=\(String(describing: reason))")
+            throw APIError.http(status, message ?? "Failed to fetch likes", reason)
+        }
+
+        struct Response: Decodable {
+            struct Item: Decodable {
+                struct Snippet: Decodable { let title: String; let channelTitle: String }
+                struct ContentDetails: Decodable { let duration: String }
+                let snippet: Snippet
+                let contentDetails: ContentDetails
+            }
+            let items: [Item]
+        }
+
+        let decoded = try JSONDecoder().decode(Response.self, from: data)
+        return decoded.items.map { item in
+            let (song, artist) = Self.extractSongArtist(from: item.snippet.title, channel: item.snippet.channelTitle)
+            let dur = Self.parseISO8601Duration(item.contentDetails.duration)
+            return YouTubeTrack(title: song, artist: artist, duration: dur)
+        }
+    }
+
+    private func fetchLikedViaLikesPlaylist(limit: Int) async throws -> [YouTubeTrack] {
+        let token = try await GoogleAuth.shared.validAccessToken()
+        Diagnostics.log("YouTubeAPI.likesPlaylist: start")
+
+        // 1) Mine channel details
+        var channels = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
+        channels.queryItems = [
+            .init(name: "part", value: "contentDetails"),
+            .init(name: "mine", value: "true")
+        ]
+        var chReq = URLRequest(url: channels.url!)
+        chReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
+        chReq.setValue("application/json", forHTTPHeaderField: "Accept")
+
+        let (chData, chResp) = try await URLSession.shared.data(for: chReq)
+        let chStatus = (chResp as? HTTPURLResponse)?.statusCode ?? -1
+        guard chStatus == 200 else {
+            let (message, reason) = Self.parseGoogleError(from: chData)
+            Diagnostics.log("YouTubeAPI.likesPlaylist: channels http \(chStatus) message=\(String(describing: message)) reason=\(String(describing: reason))")
+            throw APIError.http(chStatus, message ?? "Failed to fetch channel", reason)
+        }
+        struct ChannelsResp: Decodable {
+            struct Item: Decodable {
+                struct ContentDetails: Decodable {
+                    struct Related: Decodable { let likes: String? }
+                    let relatedPlaylists: Related
+                }
+                let contentDetails: ContentDetails
+            }
+            let items: [Item]
+        }
+        let chDecoded = try JSONDecoder().decode(ChannelsResp.self, from: chData)
+        guard let likesPlaylistId = chDecoded.items.first?.contentDetails.relatedPlaylists.likes, !likesPlaylistId.isEmpty else {
+            throw APIError.invalidResponse
+        }
+
+        // 2) Playlist items to get recent liked video IDs
+        var pl = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
+        pl.queryItems = [
+            .init(name: "part", value: "snippet,contentDetails"),
+            .init(name: "playlistId", value: likesPlaylistId),
+            .init(name: "maxResults", value: String(limit))
+        ]
+        var plReq = URLRequest(url: pl.url!)
+        plReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
+        plReq.setValue("application/json", forHTTPHeaderField: "Accept")
+
+        let (plData, plResp) = try await URLSession.shared.data(for: plReq)
+        let plStatus = (plResp as? HTTPURLResponse)?.statusCode ?? -1
+        guard plStatus == 200 else {
+            let (message, reason) = Self.parseGoogleError(from: plData)
+            Diagnostics.log("YouTubeAPI.likesPlaylist: playlistItems http \(plStatus) message=\(String(describing: message)) reason=\(String(describing: reason))")
+            throw APIError.http(plStatus, message ?? "Failed to fetch liked playlist items", reason)
+        }
+        struct PLResp: Decodable {
+            struct Item: Decodable {
+                struct Snippet: Decodable { let title: String; let channelTitle: String }
+                struct ContentDetails: Decodable { let videoId: String }
+                let snippet: Snippet
+                let contentDetails: ContentDetails
+            }
+            let items: [Item]
+        }
+        let plDecoded = try JSONDecoder().decode(PLResp.self, from: plData)
+        let ids = plDecoded.items.map { $0.contentDetails.videoId }.filter { !$0.isEmpty }
+        guard !ids.isEmpty else { return [] }
+
+        // 3) Fetch video details for durations (batch up to 50 ids)
+        var vids = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
+        vids.queryItems = [
+            .init(name: "part", value: "snippet,contentDetails"),
+            .init(name: "id", value: ids.joined(separator: ",")),
+            .init(name: "maxResults", value: String(min(limit, ids.count)))
+        ]
+        var vReq = URLRequest(url: vids.url!)
+        vReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
+        vReq.setValue("application/json", forHTTPHeaderField: "Accept")
+
+        let (vData, vResp) = try await URLSession.shared.data(for: vReq)
+        let vStatus = (vResp as? HTTPURLResponse)?.statusCode ?? -1
+        guard vStatus == 200 else {
+            let (message, reason) = Self.parseGoogleError(from: vData)
+            Diagnostics.log("YouTubeAPI.likesPlaylist: videos http \(vStatus) message=\(String(describing: message)) reason=\(String(describing: reason))")
+            throw APIError.http(vStatus, message ?? "Failed to fetch video details", reason)
+        }
+        struct VResp: Decodable {
+            struct Item: Decodable {
+                struct Snippet: Decodable { let title: String; let channelTitle: String }
+                struct ContentDetails: Decodable { let duration: String }
+                let snippet: Snippet
+                let contentDetails: ContentDetails
+            }
+            let items: [Item]
+        }
+        let vDecoded = try JSONDecoder().decode(VResp.self, from: vData)
+        let tracks: [YouTubeTrack] = vDecoded.items.map { item in
+            let (song, artist) = Self.extractSongArtist(from: item.snippet.title, channel: item.snippet.channelTitle)
+            let dur = Self.parseISO8601Duration(item.contentDetails.duration)
+            return YouTubeTrack(title: song, artist: artist, duration: dur)
+        }
+        return Array(tracks.prefix(limit))
+    }
+
+    private static func parseGoogleError(from data: Data) -> (String?, String?) {
+        struct GError: Decodable {
+            struct Inner: Decodable { let code: Int?; let message: String?; let errors: [Detail]? }
+            struct Detail: Decodable { let reason: String?; let message: String? }
+            let error: Inner?
+        }
+        if let ge = try? JSONDecoder().decode(GError.self, from: data) {
+            let msg = ge.error?.message
+            let reason = ge.error?.errors?.first?.reason
+            return (msg, reason)
+        }
+        if let txt = String(data: data, encoding: .utf8), !txt.isEmpty {
+            return (txt, nil)
+        }
+        return (nil, nil)
+    }
+
+    private static func extractSongArtist(from title: String, channel: String) -> (String, String) {
+        let cleaned = title
+            .replacingOccurrences(of: "(Official Video)", with: "", options: .caseInsensitive)
+            .replacingOccurrences(of: "(Official Audio)", with: "", options: .caseInsensitive)
+            .replacingOccurrences(of: "(Lyrics)", with: "", options: .caseInsensitive)
+            .replacingOccurrences(of: "[Official Video]", with: "", options: .caseInsensitive)
+            .replacingOccurrences(of: "[Official Audio]", with: "", options: .caseInsensitive)
+            .replacingOccurrences(of: "[Lyrics]", with: "", options: .caseInsensitive)
+            .replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
+            .replacingOccurrences(of: "’", with: "'")
+            .replacingOccurrences(of: "“", with: "\"")
+            .replacingOccurrences(of: "”", with: "\"")
+            .trimmingCharacters(in: .whitespacesAndNewlines)
+
+        if let dash = cleaned.firstIndex(of: "-") {
+            let artist = cleaned[..<dash].trimmingCharacters(in: .whitespaces)
+            let song = cleaned[cleaned.index(after: dash)...].trimmingCharacters(in: .whitespaces)
+            return (song, artist)
+        }
+        return (cleaned, channel.replacingOccurrences(of: " - Topic", with: ""))
+    }
+
+    private static func parseISO8601Duration(_ str: String) -> TimeInterval? {
+        var hours = 0, minutes = 0, seconds = 0
+        let scanner = Scanner(string: str)
+        guard scanner.scanString("P", into: nil),
+              scanner.scanString("T", into: nil) else { return nil }
+        var value: NSString?
+        if scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "HMS"), into: &value) {
+            if scanner.scanString("H", into: nil) { hours = Int(value! as String) ?? 0 }
+            else if scanner.scanString("M", into: nil) { minutes = Int(value! as String) ?? 0 }
+            else if scanner.scanString("S", into: nil) { seconds = Int(value! as String) ?? 0 }
+        }
+        while !scanner.isAtEnd {
+            if scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "HMS"), into: &value) {
+                if scanner.scanString("H", into: nil) { hours = Int(value! as String) ?? 0 }
+                else if scanner.scanString("M", into: nil) { minutes = Int(value! as String) ?? 0 }
+                else if scanner.scanString("S", into: nil) { seconds = Int(value! as String) ?? 0 }
+            } else {
+                break
+            }
+        }
+        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
+    }
+}
\ No newline at end of file
diff --git a/Video Feed Test/[2] Psicologyst.swift b/Video Feed Test/[2] Psicologyst.swift
new file mode 100644
index 0000000..079bfef
--- /dev/null
+++ b/Video Feed Test/[2] Psicologyst.swift	
@@ -0,0 +1,33 @@
+//
+//  [2] Psicologyst.swift
+//  Video Feed Test
+//
+//  Created by Ricardo Lopez Novelo on 10/21/25.
+//
+
+/*
+ 
+ You are an AI Master Consultant with a unique triple specialty:
+ Psychology & Cognitive Science – especially memory, behavior, emotional intelligence, and human motivation.
+ Technology – including human-computer interaction, cognitive offloading, how digital tools shape thinking, and the philosophy of technological progress.
+ Philosophy – particularly epistemology, phenomenology, ethics, Stoicism, and modern existential thought.
+ Your role is to act as a guide, consultant, and thought partner who integrates these three domains into a unified perspective. Your mission is to help me:
+ Understand how the mind works and how humans process, forget, and transform information.
+ Analyze the psychological and philosophical impact of technology on human identity, society, attention, and memory.
+ Develop deeper self-awareness, clarity of thought, and stronger intellectual autonomy.
+ Explore ideas through a lens that is both rational and humanistic—never purely mechanical.
+ Tone & Style:
+ Speak with empathy, depth and clarity.
+ Be concise but profound.
+ Use metaphors and analogies when they clarify complex concepts.
+ Draw from real research (psychology, neuroscience, and philosophy) while staying practical.
+ Your Outputs Should:
+ Connect mind + tech + meaning.
+ Offer actionable insights, not just theory.
+ When appropriate, propose exercises, questions for reflection, or mental models.
+ Always aim to expand my perspective, not dominate it.
+ Constraints:
+ No superficial self-help clichés.
+ No tech-utopian or tech-doom extremism—hold a balanced, critical, enlightened view.
+ When discussing memory, tie together biology, cognition, and technological tools.
+ */
diff --git a/Video Feed Test/[3] Known Issues.swift b/Video Feed Test/[3] Known Issues.swift
new file mode 100644
index 0000000..7563ba9
--- /dev/null
+++ b/Video Feed Test/[3] Known Issues.swift	
@@ -0,0 +1,9 @@
+//
+//  [3] Known Issues.swift
+//  Video Feed Test
+//
+//  Created by Ricardo Lopez Novelo on 11/23/25.
+//
+/*
+ the next video size sometimes is not “ready” because after the video changed size because of the options sheet and the next item appear the next item look like its animating from the preious size to the size that is supposed to be, im being bague because it happens in both snecarios when the optionssheet is open the next video goes from small to big and then the options sheet is not there the next video goes from small to big,
+ */
diff --git a/Video Feed Test/[4] ReelsView.swift b/Video Feed Test/[4] ReelsView.swift
new file mode 100644
index 0000000..7046fe6
--- /dev/null
+++ b/Video Feed Test/[4] ReelsView.swift	
@@ -0,0 +1,34 @@
+//
+//  ContentView.swift
+//  Video Feed Test
+//
+//  Created by Ricardo Lopez Novelo on 10/1/25.
+//
+
+import SwiftUI
+
+struct ReelsView: View {
+    @EnvironmentObject private var settings: AppSettings
+    
+    var body: some View {
+        ZStack(alignment: .top) {
+            TikTokFeedView(mode: .start)
+
+            if settings.showDownloadOverlay {
+                DownloadOverlayView()
+                    .padding(.top, 6)
+                    .transition(.move(edge: .top).combined(with: .opacity))
+                    .zIndex(1)
+                    .onTapGesture(count: 2) {
+                        settings.showDownloadOverlay = false
+                    }
+            }
+        }
+        .statusBar(hidden: true)
+    }
+}
+
+#Preview {
+    ReelsView()
+        .environmentObject(AppSettings())
+}
