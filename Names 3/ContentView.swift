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
    @Query private var contacts: [Contact]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(contacts) { contact in
                    NavigationLink {
                        ContactDetailsView(contact: contact)
                    } label: {
                        Text(contact.name ?? "New Contact")
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Contact(timestamp: Date(), notes: [], photo: Data())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(contacts[index])
            }
        }
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
    @Bindable var contact: Contact
    
    @State var viewState = CGSize.zero
    @State private var showPhotosPicker = false
    @State private var showDatePicker = false
    @State private var showTagPicker = false
    
    @Query private var notes: [Note]
    
    @State private var noteText = ""
    @State private var stateNotes : [Note] = []
    
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
                                .cornerRadius(12)
                        }
                        .contentShape(.rect)
                        .frame(height: 300)
                        .clipped()
                    }
                    
                    VStack{
                        HStack(alignment: .top){
                            TextField(
                                "Name",
                                text: $contact.name ?? "",
                                prompt: Text("Name")
                                    .foregroundColor(image != UIImage() ? Color(.white.opacity(0.7)) : Color(uiColor: .placeholderText) ),
                                axis: .vertical
                            )
                            .font(.system(size: 36, weight: .bold))
                            .lineLimit(4)
                            .padding(.leading)
                            .foregroundColor(image != UIImage() ? .white : .primary )
                            
                            VStack(alignment: .trailing){
                                HStack{
                                    Image(systemName: "camera")
                                        .font(.system(size: 18))
                                        .padding(12)
                                        .foregroundColor(image != UIImage() ? .white : .blue )
                                        .background(.blue.opacity(0.08))
                                        .clipShape(Circle())
                                        .onTapGesture { showPhotosPicker = true }
                                        .padding(.leading, 4)
                                    
                                    Image(systemName: "person.2")
                                        .font(.system(size: 18))
                                        .padding(12)
                                        .foregroundColor(image != UIImage() ? .white : .purple)
                                        .background(.purple.opacity(0.08))
                                        .clipShape(Circle())
                                        .onTapGesture { showTagPicker = true }
                                        .padding(.leading, 4)
                                }
                            }
                            .padding(.trailing)
                        }
                        
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
                        .background( image != UIImage() ? .black.opacity(0.02) : .clear)
                        .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.5)) : AnyShapeStyle(Color(uiColor: .tertiarySystemBackground))  )
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
                
                .padding(image != UIImage() ? 16 : 0)
                
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
                .frame(width: g.size.width, height: g.size.height) // laverage geometry to make the list not collapse inside a scrollview
            }
            .containerRelativeFrame([.horizontal, .vertical])
            .background(Color(UIColor.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            // TODO: contentViewModel.createItemWithSameDate(as: viewModel.item, context: viewContext)
                        } label: {
                            Text("Duplicate")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showPhotosPicker) {
            CustomPhotosPicker(contact: contact)
        }
        .sheet(isPresented: $showDatePicker) {
            CustomDatePicker(contact: contact)
        }
        .sheet(isPresented: $showTagPicker) {
            CustomTagPicker(contact: contact)
        }
    }
}


struct CustomPhotosPicker: View {
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    
    @State private var allPhotos: [UIImage] = []
    
    var body: some View {
        NavigationStack {
            VStack {
                if allPhotos.isEmpty {
                    Text("No photos found")
                        .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(spacing: 3), count: 3), spacing: 3){
                            ForEach(allPhotos, id: \.self) { photo in
                                GeometryReader {
                                    let size = $0.size
                                    Image (uiImage: photo)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: size.width, height: size.height)
                                        .clipped()
                                }
                                .frame(height: 130)
                                .contentShape(.rect)
                                .onTapGesture {
                                    contact.photo = photo.heicData() ?? Data()
                                    dismiss()
                                }
                            }
                        }
                        .padding(.vertical, 15)
                    }
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar{
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: requestPhotoAccess)
            
        }
    }
    
    func requestPhotoAccess() {
        
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"]
        
        if isPreview == "1" { // Fetch sample photos for Preview
            for i in 1...9 {
                if let image = UIImage(named: "test-\(i)") {
                    allPhotos.append(image)
                }
            }
        } else{ // Request authorization and fetch real photos
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized || status == .limited {
                    fetchPhotos()
                } else {
                    print("Photo access denied or restricted.")
                }
            }
        }
    }
    
    func fetchPhotos() {
        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var photos: [UIImage] = []
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        
        assets.enumerateObjects { asset, _, _ in
            manager.requestImage(for: asset, targetSize: CGSize(width: 100, height: 100), contentMode: .aspectFill, options: requestOptions) { image, _ in
                if let image = image {
                    photos.append(image)
                }
            }
        }
        DispatchQueue.main.async {
            allPhotos = photos
        }
    }
    
}

struct CustomDatePicker: View {
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    
    @State private var date = Date()
    @State private var bool: Bool = false
    
    var body: some View {
        
        VStack{
            GroupBox{
                Toggle("Met long ago", isOn: $contact.isMetLongAgo)
                    .onChange(of: contact.isMetLongAgo) { _, _ in
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
    @Query private var tags: [Tag]
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    
    var body: some View{
        NavigationStack{
            ScrollView{
                ForEach(tags, id: \.self) { tag in
                    Text(tag.name)
                    //                TagRow(tag: tag, isSelected: viewModel.selectedTags.contains(tag)) {
                    //                    viewModel.toggleTagSelection(tag)
                    //                }
                }
                
                if !searchText.isEmpty {
                    Button{
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
            .containerRelativeFrame([.horizontal, .vertical])
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}

#Preview {
    ContentView().modelContainer(for: Contact.self, inMemory: true)
    
   //ModelContainerPreview(ModelContainer.sample) {ContactDetailsView(contact:.ross)}
}
