//
//  ContentView.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Query private var contacts: [Contact]
    @State private var parsedContacts: [Contact] = []
    
    // Group contacts by the day of their timestamp, AI
    var groups: [contactsGroup] {
        let calendar = Calendar.current

        // Group `contacts` by the start of the day
        let groupedContacts = Dictionary(grouping: contacts) { contact in
            calendar.startOfDay(for: contact.timestamp)
        }

        // Group `parsedContacts` by the start of the day
        let groupedParsedContacts = Dictionary(grouping: parsedContacts) { parsedContact in
            calendar.startOfDay(for: parsedContact.timestamp)
        }

        // Combine both grouped dictionaries
        let allDates = Set(groupedContacts.keys).union(groupedParsedContacts.keys)

        // Map combined dates to `contactsGroup`, ensuring items are sorted by creation time
        return allDates.map { date in
            let sortedContacts = (groupedContacts[date] ?? []).sorted { $0.timestamp < $1.timestamp }
            let sortedParsedContacts = (groupedParsedContacts[date] ?? []).sorted { $0.timestamp < $1.timestamp }

            return contactsGroup(
                date: date,
                contacts: sortedContacts,
                parsedContacts: sortedParsedContacts
            )
        }
        .sorted { $0.date < $1.date } // Sort groups by date
    }
    
    @State private var isAtBottom = false
    private let dragThreshold: CGFloat = 100
    @FocusState private var fieldIsFocused: Bool
    
    @State private var text = ""
    @State private var date = Date()

    @State private var showPhotosPicker = false
    
    @State private var name = ""
    @State private var hashtag = ""
    
    var dynamicBackground: Color {
        if fieldIsFocused {
            return colorScheme == .light ? .clear : .clear // Background for keyboard
        } else {
            return colorScheme == .light ? .clear : .clear // Default background
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
                            
                            // Can this section be inside the LazyVGrid? does that improve optimization or are we still getting it from scrollview?
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
                                                    
                                                    VStack {
                                                        Spacer()
                                                        Text(contact.name ?? "")
                                                            .font(.footnote)
                                                            .bold()
                                                            .foregroundColor(Color(uiColor: .label))
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
                                    ForEach(group.parsedContacts) { contact in
                                        Text(contact.name ?? "")
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                }
                // ScrollView modifiers
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: contacts) { oldValue, newValue in
                    proxy.scrollTo(contacts.last?.id) //When the count changes scroll to latest message
                }
            }
            .safeAreaInset(edge: .top){
                ZStack(alignment: .top) {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(UIColor.systemBackground).opacity(0.0), location: 0.0),
                            .init(color: Color(UIColor.systemBackground).opacity(0.3), location: 0.85)
                        ]),
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.85) // Customizable endpoint
                    )
//  Extension needed
//                    SmoothLinearGradient(
//                        from: Color(UIColor.systemBackground).opacity(0.0),
//                        to: Color(UIColor.systemBackground).opacity(0.3),
//                        startPoint: .top,
//                        endPoint: UnitPoint(x: 0.5, y: 0.85),
//                        curve: .easeInOut
//                    )
                    .ignoresSafeArea(.all)
                    .frame(height: 100)
                    //TransparentBlurUIView(removeAllFilters: true)
                    .ignoresSafeArea(.all)
                    .frame(height: 60)
                }
                .frame(height: 60)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 0){
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .padding(13)
                        .foregroundColor(.blue)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                        .onTapGesture { showPhotosPicker = true }
                    
                    DatePicker(selection: $date, in: ...Date(), displayedComponents: .date){}
                        .labelsHidden()
                        .padding(.trailing)
                    
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
                    
                }
                .padding(.bottom, 8)
                .padding(.horizontal)
                .background(dynamicBackground)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        
    }
    
    private func parseContacts() {
        let input = text
        // Split the input by commas for each contact entry
        let nameEntries = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var contacts: [Contact] = []
        var globalTags: [Tag] = []
        
        // First, find all unique hashtags across the entire input
        let allWords = input.split(separator: " ").map { String($0) }
        for word in allWords {
            if word.starts(with: "#") {
                let tagName = word.dropFirst().trimmingCharacters(in: .punctuationCharacters)
                if !tagName.isEmpty && !globalTags.contains(where: { $0.name == tagName }) {
                    globalTags.append(Tag(name: String(tagName)))
                }
            }
        }
        
        // Now parse each contact entry, attaching the global tags to each
        for entry in nameEntries {
            var nameComponents: [String] = []
            
            // Split each entry by spaces to find words (ignore hashtags here as they’re in globalTags)
            let words = entry.split(separator: " ").map { String($0) }
            
            for word in words {
                if !word.starts(with: "#") {
                    nameComponents.append(word)
                }
            }
            
            let name = nameComponents.joined(separator: " ")
            if !name.isEmpty {
                let contact = Contact(name: name, timestamp: date, notes: [], tags: globalTags, photo: Data())
                contacts.append(contact)
            }
        }
        
        parsedContacts = contacts
    }
    
    // Function to save parsed contacts
    func saveContacts(modelContext: ModelContext) {
        for contact in parsedContacts {
            modelContext.insert(contact)
        }
        
        // Clear text and parsed contacts after saving
        text = ""
        parsedContacts = []
    }

    private func addItem() {
        withAnimation {
            let newContact = Contact(timestamp: Date(), notes: [], photo: Data())

            modelContext.insert(newContact)
            
            // Check if there is already an entry for today
//            if let lastEntry = dates.last,
//               Calendar.current.isDateInToday(lastEntry.date) {
//                // Append the new contact to today's entry
//                lastEntry.contacts.append(newContact)
//            } else {
//                // Create a new entry for today and insert it into the model
//                let newDateEntry = contactsGroup(date: Calendar.current.startOfDay(for: Date()))
//                newDateEntry.contacts.append(newContact)
//                modelContext.insert(newDateEntry)
//            }
        }
    }

//    private func deleteItems(offsets: IndexSet) {
//        withAnimation {
//            for index in offsets {
//                modelContext.delete(contacts[index])
//            }
//        }
//    }
    
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
                                //.cornerRadius(12)
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
                                
                                //HStack{
                                Image(systemName: "camera")
                                    .font(.system(size: 18))
                                    .padding(12)
                                    .foregroundColor(image != UIImage() ? .blue.mix(with: .white, by: 0.3) : .blue )
                                    .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.blue.opacity(0.08))))
                                    .background(image != UIImage() ? .black.opacity(0.2) : .clear)
                                    .clipShape(Circle())
                                    .onTapGesture { showPhotosPicker = true }
                                    .padding(.leading, 4)
                                
                                Group{
                                    if !contact.tags.isEmpty {
                                        Text(contact.tags.compactMap { $0.name }.sorted().joined(separator: ", "))
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
                                
                                //}
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
                            //.background( image != UIImage() ? .black.opacity(0.02) : .clear)
                            //.background( image != UIImage() ? Color(uiColor: .tertiarySystemBackground) : Color(uiColor: .tertiarySystemBackground))
                            //.background(.ultraThinMaterial.opacity(0.9))
                            .background(
                                BlurView(style: .regular)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            
                            
                            .padding(.horizontal).padding(.top, 12)
                            .onTapGesture {
                                // TODO: viewModel.showImageSourceDialog = false
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        // TODO: make the drag gesture move the main note to a regular note
                                        viewState = value.translation
                                    }
                            )
                            
                            HStack{
                                Spacer()
                                Text(contact.timestamp, style: .date)
                                // TODO: \(contentViewModel.customFormattedDate(viewModel.item.dateMet, fallbackDate: Date()))
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
                                        // TODO: dateTitle = viewModel.formattedDate(viewModel.item.dateMet, isDateMetLongAgo: viewModel.item.isDateMetLongAgo)
                                    }
                            }
                        }
                    }
                    //.padding(image != UIImage() ? 16 : 0)
                    
                    Text("Notes")
                        .font(.body.smallCaps())
                        .fontWeight(.light)
                        .foregroundStyle(.secondary)
                        .padding(.leading)
                    
                    Button(action: {
                        let newNote = Note(content: "Test", creationDate: Date())
                        
                        contact.notes.append(newNote)
                        
                        //try? modelContext.save()
                        // TODO: viewModel.createNote()
                        // viewModel.objectWillChange.send()
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
                        ForEach(contact.notes.indices.reversed(), id:\.self) { index in
                            Section{
                                VStack {
                                    TextField("Note Content", text: $contact.notes[index].content, axis: .vertical)
                                        .lineLimit(2...)
                                    HStack {
                                        Spacer()
                                        Text(contact.notes[index].creationDate, style: .date)
                                            .font(.caption)
                                    }
                                }
                                //.padding(.horizontal).padding(.vertical, 14)
                                //.background(Color(uiColor: .tertiarySystemBackground))
                                //.clipShape(RoundedRectangle(cornerRadius: 12))
                                //.padding(.horizontal)
                                
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(contact.notes[index])
                                        // TODO: viewModel.deleteNote(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        // TODO: showDatePickerFor(note: note)
                                    } label: {
                                        Label("Edit Date", systemImage: "calendar")
                                    }
                                    .tint(.blue)
                                }
                            }
                            
                        }
                    }
                    .frame(width: g.size.width, height: g.size.height) // laverage geometry to make the list not collapse inside a scrollview
                }
                .padding(.top, image != UIImage() ? 0 : 8 )
                .ignoresSafeArea(image != UIImage() ? .all : [])
                //.containerRelativeFrame([.horizontal, .vertical])
                .background(Color(UIColor.systemGroupedBackground))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                // TODO: contentViewModel.createItemWithSameDate(as: viewModel.item, context: viewContext)
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
                                .foregroundStyle(image != UIImage() ? Color(.lightText) : .accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(image != UIImage() ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.clear)))
                                .cornerRadius(100)
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
                    //                Text("Crop View")
                    CropView(
                        image: image,
                        initialScale: CGFloat(contact.cropScale),
                        initialOffset: CGSize(width: CGFloat(contact.cropOffsetX), height: CGFloat(contact.cropOffsetY))
                    ) { croppedImage, scale, offset in
                        updateCroppingParameters(croppedImage: croppedImage, scale: scale, offset: offset)
                    }
                }
            }
            .onChange(of: selectedItem) {
                        Task {
                            if let loaded = try? await selectedItem?.loadTransferable(type: Data.self) {
                                contact.photo = loaded
                                showCropView = true
                            } else {
                                print("Failed")
                            }
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
    }
}


//struct CustomPhotosPicker: View {
//    @Bindable var contact: Contact
//    @Environment(\.dismiss) private var dismiss
//    
//    @State private var allPhotos: [UIImage] = []
//    @State private var loadingMorePhotos = false
//    @State private var photoBatchLimit = 50 // Number of photos to load per batch
//    @State private var lastFetchedIndex = 0 // Track the last fetched index
//    
//    var body: some View {
//        NavigationStack {
//            VStack {
//                if allPhotos.isEmpty {
//                    Text("No photos found")
//                        .padding()
//                } else {
//                    ScrollView {
//                        LazyVGrid(columns: Array(repeating: GridItem(spacing: 3), count: 3), spacing: 3) {
//                            ForEach(allPhotos.indices, id: \.self) { index in
//                                GeometryReader {
//                                    let size = $0.size
//                                    Image(uiImage: allPhotos[index])
//                                        .resizable()
//                                        .aspectRatio(contentMode: .fill)
//                                        .frame(width: size.width, height: size.height)
//                                        .clipped()
//                                }
//                                .frame(height: 130)
//                                .contentShape(.rect)
//                                .onTapGesture {
//                                    contact.photo = allPhotos[index].heicData() ?? Data()
//                                    dismiss()
//                                }
//                                // Load more photos when reaching the end of the current batch
//                                .onAppear {
//                                    if index == allPhotos.count - 1 && !loadingMorePhotos {
//                                        loadNextBatchOfPhotos()
//                                    }
//                                }
//                            }
//                        }
//                        .padding(.vertical, 15)
//                    }
//                }
//            }
//            .navigationTitle("Photos")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .topBarLeading) {
//                    Button("Cancel") {
//                        dismiss()
//                    }
//                }
//                ToolbarItem(placement: .topBarTrailing) {
//                    if !contact.photo.isEmpty {
//                        Button("Remove") {
//                            contact.photo = Data()
//                            dismiss()
//                        }
//                    }
//                }
//            }
//            .onAppear(perform: requestPhotoAccess)
//        }
//    }
//    
//    func requestPhotoAccess() {
//        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"]
//        
//        if isPreview == "1" { // Fetch sample photos for Preview
//            for i in 1...9 {
//                if let image = UIImage(named: "test-\(i)") {
//                    allPhotos.append(image)
//                }
//            }
//        } else { // Request authorization and fetch real photos
//            PHPhotoLibrary.requestAuthorization { status in
//                if status == .authorized || status == .limited {
//                    loadNextBatchOfPhotos()
//                } else {
//                    print("Photo access denied or restricted.")
//                }
//            }
//        }
//    }
//    
//    func loadNextBatchOfPhotos() {
//        guard !loadingMorePhotos else { return }
//        loadingMorePhotos = true
//
//        // Configure fetch options to sort by creation date in descending order
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
//        
//        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
//        let manager = PHImageManager.default()
//        let requestOptions = PHImageRequestOptions()
//        requestOptions.deliveryMode = .fastFormat
//        requestOptions.isSynchronous = false // Asynchronous loading
//        
//        // Calculate the range for the next batch of photos
//        let nextBatchRange = lastFetchedIndex..<(min(lastFetchedIndex + photoBatchLimit, assets.count))
//        
//        assets.enumerateObjects(at: IndexSet(integersIn: nextBatchRange), options: []) { asset, _, stop in
//            manager.requestImage(for: asset, targetSize: CGSize(width: 100, height: 100), contentMode: .aspectFill, options: requestOptions) { image, _ in
//                if let image = image {
//                    DispatchQueue.main.async {
//                        allPhotos.append(image)
//                    }
//                }
//            }
//        }
//        
//        lastFetchedIndex += photoBatchLimit // Update the last fetched index
//        loadingMorePhotos = false // Reset loading state
//    }
//}



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
                            //                    viewModel.item.dateMet = Date.distantPast
                            //                    viewModel.objectWillChange.send()
                        } else {
                            //                    viewModel.item.dateMet = storedDateMet
                            //                    viewModel.objectWillChange.send()
                            
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
                            let newTag = Tag(name: searchText)
                            modelContext.insert(newTag)
                            //try? modelContext.save()
                            //itemDetailViewModel.addTag(named: searchText)
                            //viewModel.fetchTags()
                            
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
                    ForEach(tags, id: \.self) { tag in
                        HStack{
                            Text(tag.name)
                            Spacer()
                            if contact.tags.contains(tag){
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !contact.tags.contains(tag){
                                print("not tag already added")
                                contact.tags.append(tag)
                            } else {
                                if let index = contact.tags.firstIndex(where: {$0.id == tag.id}) {
                                    contact.tags.remove(at: index)
                                }
                            }
    
                        }
                        //                TagRow(tag: tag, isSelected: viewModel.selectedTags.contains(tag)) {
                        //                    viewModel.toggleTagSelection(tag)
                        //                }
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
        ContentView().modelContainer(for: Contact.self, inMemory: true)
}

#Preview("Contact Detail") {
    ModelContainerPreview(ModelContainer.sample) {
        NavigationStack{
            ContactDetailsView(contact:.ross)
        }
    }
    // Preview line above wont allow to manipulate data in the current implmentation, theory is that data is being manipulated not in the correct codelcontainer/modelcontext
}


// Define a new struct named BlurView, which conforms to UIViewRepresentable. This allows SwiftUI to use UIViews.
struct BlurView: UIViewRepresentable {
    
    // Declare a property 'style' of type UIBlurEffect.Style to store the blur effect style.
    let style: UIBlurEffect.Style
    
    // Initializer for the BlurView, taking a UIBlurEffect.Style as a parameter and setting it to the 'style' property.
    init(style: UIBlurEffect.Style) {
        self.style = style
    }
    
    // Required method of UIViewRepresentable protocol. It creates and returns the UIVisualEffectView.
    func makeUIView(context: Context) -> UIVisualEffectView {
        // Create a UIBlurEffect with the specified 'style'.
        let blurEffect = UIBlurEffect(style: style)
        // Initialize a UIVisualEffectView with the blurEffect.
        let blurView = UIVisualEffectView(effect: blurEffect)
        // Return the configured blurView.
        return blurView
    }
    
    // Required method of UIViewRepresentable protocol. Here, it's empty as we don't need to update the view after creation.
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}


// navigationBarBackButtonHidden - swipe back gesture
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}
