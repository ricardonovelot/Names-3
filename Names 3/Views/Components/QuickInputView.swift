import SwiftUI
import SwiftData
import SmoothGradient
import Vision
import UIKit

enum QuickInputMode {
    case people
    case quickNotes
}

struct QuickInputView: View {
    @Environment(\.modelContext) private var modelContext

    // Mode and hooks
    let mode: QuickInputMode
    @Binding var parsedContacts: [Contact]
    @Binding var isQuickNotesActive: Bool
    @Binding var selectedContact: Contact?
    var onCameraTap: (() -> Void)? = nil
    var onQuickNoteAdded: (() -> Void)? = nil
    var onQuickNoteDetected: (() -> Void)? = nil
    var onQuickNoteCleared: (() -> Void)? = nil
    var onInlinePhotosTap: (() -> Void)? = nil
    var isInlinePhotosActive: (() -> Bool)? = nil

    // Optional quick note to link created entities to, and flag to allow/deny quick note creation
    var linkedQuickNote: QuickNote? = nil
    var allowQuickNoteCreation: Bool = true

    // Optional override for Return key handling (e.g., commit names in PhotoDetail)
    var onReturnOverride: (() -> Void)? = nil
    
    // Face carousel integration
    var faceDetectionViewModel: FaceDetectionViewModel? = nil
    var onFaceSelected: ((Int) -> Void)? = nil

    // People suggestions and selection
    @Query(filter: #Predicate<Contact> { $0.isArchived == false })
    private var contacts: [Contact]

    // Unified input state
    @State private var text: String = ""
    @FocusState private var fieldIsFocused: Bool
    @State private var bottomInputHeight: CGFloat = 0
    @State private var suggestionsHeight: CGFloat = 0
    @State private var faceCarouselHeight: CGFloat = 0
    @State private var isLoading = false

    // People-mode state
    @State private var filterString: String = ""
    @State private var suggestedContacts: [Contact] = []
    @State private var parseDebounceWork: DispatchWorkItem?
    @State private var quickNoteActive: Bool = false
    @State private var suppressNextClear: Bool = false
    @State private var showModePicker = false
    @State private var shouldShowCreateButton: Bool = false
    @State private var parsedTagNames: [String] = []

    // Photo processing state
    @State private var isProcessingPhoto = false
    @State private var lastPickedImage: UIImage?
    @State private var isCameraPickerPresented = false

    // Photo processing callbacks
    var onPhotoPicked: ((UIImage, Date?) -> Void)? = nil

    private func isQuickNoteCommand(_ input: String) -> Bool {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPattern = #"^(quick\s*note|quick)\b[\s:]*"#
        if s.range(of: prefixPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let anywhereQN = #"(?i)\bqn\b"#
        return s.range(of: anywhereQN, options: .regularExpression) != nil
    }

    private func stripQuickNotePrefix(from input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPattern = #"(?i)^(quick\s*note|quick)\b[\s:]*"#
        if let r = s.range(of: prefixPattern, options: .regularExpression) {
            s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let qnPattern = #"(?i)\bqn\b\s*[:;,]?"#
        s = s.replacingOccurrences(of: qnPattern, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    var body: some View {
        let controlSize: CGFloat = 64
        VStack(spacing: 0) {
            // Face carousel - shown above the input when faces are detected
            if let viewModel = faceDetectionViewModel, !viewModel.faces.isEmpty {
                PhotoFaceCarouselView(
                    viewModel: viewModel,
                    onFaceSelected: { index in
                        onFaceSelected?(index)
                    }
                )
                .frame(height: 120)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: FaceCarouselHeightKey.self, value: proxy.size.height)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            VStack {
                HStack(spacing: 6) {
                    InputBubble {
                        HStack(spacing: 8) {
                            if mode == .people, let token = selectedContact {
                                HStack(spacing: 6) {
                                    Text(token.name ?? "Unnamed")
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .fill(Color.blue.opacity(0.15))
                                }
                                .clipShape(Capsule())
                            }

                            ZStack(alignment: .topLeading) {
                                GrowingTextView(
                                    text: $text,
                                    isFirstResponder: Binding(
                                        get: { fieldIsFocused },
                                        set: { fieldIsFocused = $0 }
                                    ),
                                    minHeight: 22,
                                    maxHeight: 140,
                                    onDeleteWhenEmpty: {
                                        if text.isEmpty, selectedContact != nil {
                                            selectedContact = nil
                                            Task { @MainActor in
                                                try? await Task.sleep(for: .milliseconds(30))
                                                fieldIsFocused = true
                                            }
                                        }
                                    },
                                    onReturn: {
                                        if let override = onReturnOverride {
                                            resetTextAndPreview()
                                            override()
                                            return
                                        }
                                        if mode == .people && !suggestedContacts.isEmpty {
                                            selectExistingContact(suggestedContacts[0])
                                        } else {
                                            save()
                                        }
                                    }
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .onChange(of: text) { oldValue, newValue in
                                    NotificationCenter.default.post(name: .quickInputTextDidChange, object: nil, userInfo: ["text": newValue])

                                    if let last = newValue.last, last == "\n" {
                                        text.removeLast()
                                        if let override = onReturnOverride {
                                            resetTextAndPreview()
                                            override()
                                        } else {
                                            save()
                                        }
                                    } else {
                                        if mode == .people {
                                            parseDebounceWork?.cancel()
                                            let s = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if isQuickNoteCommand(s) && selectedContact == nil {
                                                parsePeopleInput()
                                            } else {
                                                let work = DispatchWorkItem {
                                                    parsePeopleInput()
                                                }
                                                parseDebounceWork = work
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
                                            }
                                        }
                                    }
                                }

                                if text.isEmpty {
                                    Text(mode == .people && selectedContact != nil ? "Add a note…" : "")
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 3)
                                        .padding(.top, 1)
                                        .allowsHitTesting(false)
                                }
                            }

                            if mode == .people {
                                Button {
                                    guard !isCameraPickerPresented else {
                                        print("⚠️ [QuickInput] Camera picker already presented, ignoring tap")
                                        return
                                    }
                                    isCameraPickerPresented = true
                                    onCameraTap?()
                                } label: {
                                    Image(systemName: "camera")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(isCameraPickerPresented)
                            }
                        }
                    }

                    if mode == .people {
                        Button {
                            let inlineSupported = (onInlinePhotosTap != nil) && (isInlinePhotosActive != nil)
                            let inlineActive = isInlinePhotosActive?() ?? false

                            if !inlineSupported {
                                if isQuickNotesActive {
                                    isQuickNotesActive = false
                                    onQuickNoteCleared?()
                                } else {
                                    isQuickNotesActive = true
                                    onQuickNoteDetected?()
                                }
                                return
                            }

                            if !isQuickNotesActive && !inlineActive {
                                isQuickNotesActive = true
                                onQuickNoteDetected?()
                            } else if isQuickNotesActive && !inlineActive {
                                isQuickNotesActive = false
                                onQuickNoteCleared?()
                                onInlinePhotosTap?()
                            } else if inlineActive {
                                if isQuickNotesActive {
                                    isQuickNotesActive = false
                                    onQuickNoteCleared?()
                                }
                                onInlinePhotosTap?()
                            }
                        } label: {
                            let inlineActive = isInlinePhotosActive?() ?? false
                            let inlineSupported = (onInlinePhotosTap != nil) && (isInlinePhotosActive != nil)
                            let symbolName = inlineSupported && inlineActive
                                ? "person"
                                : (isQuickNotesActive
                                   ? (inlineSupported ? "photo.on.rectangle" : "person")
                                   : "note.text")

                            Image(systemName: symbolName)
                                .font(.system(size: 24, weight: .medium))
                                .frame(width: controlSize, height: controlSize)
                                .liquidGlass(in: Circle())
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Cycle input mode")
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            if mode == .people, selectedContact == nil && !filterString.isEmpty && (!suggestedContacts.isEmpty || shouldShowCreateButton) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedContacts) { contact in
                            Button {
                                selectExistingContact(contact)
                            } label: {
                                HStack(spacing: 6) {
                                    if !contact.photo.isEmpty, let uiImage = UIImage(data: contact.photo) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 24, height: 24)
                                            .clipShape(Circle())
                                    } else {
                                        ZStack {
                                            RadialGradient(
                                                colors: [
                                                    Color(uiColor: .secondarySystemBackground),
                                                    Color(uiColor: .tertiarySystemBackground)
                                                ],
                                                center: .center,
                                                startRadius: 2,
                                                endRadius: 17
                                            )
                                            
                                            Color.clear
                                                .frame(width: 24, height: 24)
                                                .liquidGlass(in: Circle(), stroke: true)
                                        }
                                    }
                                    
                                    Text(contact.name ?? "Unnamed")
                                        .font(.subheadline)
                                }
                                .padding(.leading, 6)
                                .padding(.trailing, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Color.blue.gradient.quinary
                                )
                                .background(.ultraThinMaterial)
                                .foregroundStyle(.primary)
                                
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                        }
                        
                        if shouldShowCreateButton {
                            Button {
                                createNewContactFromFilterString()
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green.opacity(0.3))
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            Image(systemName: "plus")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.green)
                                        }
                                    
                                    Text("Create \"\(filterString)\"")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 6)
                                .padding(.trailing, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Color.green.gradient.quinary
                                )
                                .background(.ultraThinMaterial)
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: suggestedContacts.map(\.id))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldShowCreateButton)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44, maxHeight: 60, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: SuggestionsHeightKey.self, value: proxy.size.height)
                    }
                )
                .padding(.horizontal)
                .offset(y: -(suggestionsHeight + 8))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: !suggestedContacts.isEmpty || shouldShowCreateButton)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: BottomInputHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(BottomInputHeightKey.self) { height in
            DispatchQueue.main.async {
                bottomInputHeight = height
            }
        }
        .onPreferenceChange(SuggestionsHeightKey.self) { height in
            withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                suggestionsHeight = height
            }
        }
        .onPreferenceChange(FaceCarouselHeightKey.self) { height in
            withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                faceCarouselHeight = height
            }
        }
        .preference(key: TotalQuickInputHeightKey.self, value: bottomInputHeight + suggestionsHeight + faceCarouselHeight + 8)
        .onReceive(NotificationCenter.default.publisher(for: .quickInputRequestFocus)) { _ in
            print("🎯 [QuickInput] Received focus request notification")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                print("🎯 [QuickInput] Setting fieldIsFocused = true")
                fieldIsFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickInputResignFocus)) { _ in
            print("🎯 [QuickInput] Received resign focus notification")
            fieldIsFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickInputCameraDidPickPhoto)) { notification in
            isCameraPickerPresented = false
            
            if let userInfo = notification.userInfo,
               let image = userInfo["image"] as? UIImage,
               let date = userInfo["date"] as? Date? {
                handlePhotoPicked(image: image, date: date)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickInputCameraDidDismiss)) { _ in
            print("📸 [QuickInput] Camera picker dismissed without selection")
            isCameraPickerPresented = false
        }
    }

    private func save() {
        isLoading = true
        defer { isLoading = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = selectedContact, mode == .people {
            if let note = buildNoteFromText(for: existing, text: trimmed) {
                if existing.notes == nil { existing.notes = [] }
                existing.notes?.append(note)
                if let qn = linkedQuickNote {
                    note.quickNote = qn
                    if qn.linkedNotes == nil { qn.linkedNotes = [] }
                    qn.linkedNotes?.append(note)
                }
                do { try modelContext.save() } catch { print("Save failed: \(error)") }
            }
            text = ""
            resetTextAndPreview()
            return
        }

        if ((isQuickNoteCommand(trimmed) && allowQuickNoteCreation) || mode == .quickNotes) {
            if let qn = buildQuickNoteFromText(trimmed) {
                modelContext.insert(qn)
                do { try modelContext.save() } catch { print("Save failed: \(error)") }
                if mode == .people {
                    onQuickNoteAdded?()
                    suppressNextClear = true
                    quickNoteActive = true
                }
            }
            resetTextAndPreview()
            return
        }

        if mode == .people {
            // Use stored parsed tag names instead of re-extracting
            var globalTags: [Tag] = []
            
            for tagName in parsedTagNames {
                if let tag = Tag.fetchOrCreate(named: tagName, in: modelContext, seedDate: Date()) {
                    globalTags.append(tag)
                }
            }
            
            // Assign tags to all parsed contacts
            for contact in parsedContacts {
                contact.tags = globalTags
                modelContext.insert(contact)
            }
            
            if let qn = linkedQuickNote {
                if qn.linkedContacts == nil { qn.linkedContacts = [] }
                if qn.linkedNotes == nil { qn.linkedNotes = [] }
                for contact in parsedContacts {
                    qn.linkedContacts?.append(contact)
                    for n in contact.notes ?? [] {
                        n.quickNote = qn
                        qn.linkedNotes?.append(n)
                    }
                }
            }
            do { try modelContext.save() } catch { print("Save failed: \(error)") }
            resetTextAndPreview()
        }
    }

    private func resetTextAndPreview() {
        text = ""
        filterString = ""
        suggestedContacts = []
        shouldShowCreateButton = false
        parsedTagNames = []
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            parsedContacts = []
        }
    }

    private func parsePeopleInput() {
        var workingInput = text
        var trimmed = workingInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if quickNoteActive {
                if suppressNextClear {
                    suppressNextClear = false
                } else {
                    quickNoteActive = false
                    onQuickNoteCleared?()
                }
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                parsedContacts = []
            }
            filterString = ""
            suggestedContacts = []
            shouldShowCreateButton = false
            parsedTagNames = []
            return
        }

        let detected = isQuickNoteCommand(trimmed)
        if detected && selectedContact == nil {
            if allowQuickNoteCreation {
                if !quickNoteActive {
                    quickNoteActive = true
                    onQuickNoteDetected?()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    parsedContacts = []
                }
                filterString = ""
                suggestedContacts = []
                shouldShowCreateButton = false
                parsedTagNames = []
                return
            }
        } else if quickNoteActive {
            quickNoteActive = false
            onQuickNoteCleared?()
            let sanitized = stripQuickNoteMarkers(from: workingInput)
            workingInput = sanitized
            text = sanitized
            trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    parsedContacts = []
                }
                filterString = ""
                suggestedContacts = []
                shouldShowCreateButton = false
                parsedTagNames = []
                return
            }
        }

        let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var detectedDate: Date? = nil
        var cleanedInput = workingInput

        if let matches = dateDetector?.matches(in: workingInput, options: [], range: NSRange(location: 0, length: workingInput.utf16.count)) {
            for match in matches {
                if match.resultType == .date, let date = match.date {
                    detectedDate = adjustToPast(date)
                    if let range = Range(match.range, in: workingInput) {
                        cleanedInput.removeSubrange(range)
                    }
                    break
                }
            }
        }

        let fallbackDate = Date()
        let finalDate = detectedDate ?? fallbackDate

        var longAgoDetected = false
        let patterns = ["\\blong\\s*time\\s*ago\\b", "\\blta\\b"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: cleanedInput.utf16.count)
                if regex.firstMatch(in: cleanedInput, options: [], range: range) != nil {
                    longAgoDetected = true
                }
                cleanedInput = regex.stringByReplacingMatches(in: cleanedInput, options: [], range: range, withTemplate: "")
            }
        }
        cleanedInput = cleanedInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Store extracted tag names in state
        parsedTagNames = extractValidTagNames(from: cleanedInput)
        cleanedInput = removeTagTokens(from: cleanedInput)

        let nameEntries = cleanedInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var previews: [Contact] = []

        for entry in nameEntries {
            if entry.starts(with: "#") { continue }

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

                let contact = Contact(name: name, timestamp: finalDate, notes: notes, tags: [], photo: Data())
                contact.summary = summary
                contact.isMetLongAgo = longAgoDetected
                contact.uuid = UUID()
                previews.append(contact)
            }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            parsedContacts = previews
        }
    }

    private func removeTagTokens(from text: String) -> String {
        var tokens = text.split(whereSeparator: { $0.isWhitespace })
        tokens.removeAll(where: { $0.hasPrefix("#") })
        return tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Pure function to extract valid tag names without creating Tag objects
    private func extractValidTagNames(from text: String) -> [String] {
        var tagNames: [String] = []
        var seenKeys = Set<String>()
        
        // Split into tokens with their preceding character context
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        
        for token in tokens {
            // Must start with # to be a tag
            guard token.hasPrefix("#") else { continue }
            
            // Extract tag text (remove # and trailing punctuation)
            let raw = token.dropFirst()
            let trimmed = raw.trimmingCharacters(in: .punctuationCharacters)
            
            // Must have content after #
            guard !trimmed.isEmpty else { continue }
            
            // Check if this exact # position is valid (preceded by whitespace or start of string)
            let tagString = String(token)
            if let range = text.range(of: tagString) {
                let startIndex = range.lowerBound
                
                // Valid if at start of string OR preceded by whitespace
                let isAtStart = startIndex == text.startIndex
                let isPrecededByWhitespace = !isAtStart && text[text.index(before: startIndex)].isWhitespace
                
                if isAtStart || isPrecededByWhitespace {
                    let key = Tag.normalizedKey(String(trimmed))
                    if !seenKeys.contains(key) {
                        tagNames.append(String(trimmed))
                        seenKeys.insert(key)
                    }
                }
            }
        }
        
        return tagNames
    }

    private func filterContacts() {
        if filterString.isEmpty {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                suggestedContacts = []
                shouldShowCreateButton = false
            }
        } else {
            let q = filterString.trimmingCharacters(in: .whitespacesAndNewlines)
            let filtered = contacts.filter { contact in
                guard let name = contact.name, !q.isEmpty else { return false }
                if name.localizedStandardContains(q) { return true }
                return name.lowercased().hasPrefix(q.lowercased())
            }
            
            // Show create button when:
            // 1. There's valid input (at least 2 characters)
            // 2. Not a quick note command
            // Note: We allow duplicates since multiple people can have the same name
            let isValidName = !q.isEmpty && q.count >= 2 && !isQuickNoteCommand(q)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                suggestedContacts = filtered
                shouldShowCreateButton = isValidName
            }
        }
    }

    private func createNewContactFromFilterString() {
        // Use the parsed contact if available (which has cleaned name)
        // Otherwise fall back to filterString
        let cleanedName: String
        let contactTags: [Tag]
        
        if let firstParsed = parsedContacts.first {
            cleanedName = firstParsed.name ?? filterString.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            cleanedName = filterString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !cleanedName.isEmpty else { return }
        
        // Create Tag objects from parsed tag names
        var tags: [Tag] = []
        for tagName in parsedTagNames {
            if let tag = Tag.fetchOrCreate(named: tagName, in: modelContext, seedDate: Date()) {
                tags.append(tag)
            }
        }
        
        // Create a new contact with the cleaned name and parsed tags
        let newContact = Contact(
            name: cleanedName,
            timestamp: Date(),
            notes: [],
            tags: tags,
            photo: Data()
        )
        newContact.uuid = UUID()
        
        // Select this new contact immediately (it will be saved when user adds a note)
        selectedContact = newContact
        text = ""
        filterString = ""
        suggestedContacts = []
        shouldShowCreateButton = false
        parsedTagNames = []
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            parsedContacts = []
        }
        
        // Insert into context so it's tracked
        modelContext.insert(newContact)
        
        // Save immediately
        do {
            try modelContext.save()
        } catch {
            print("❌ [QuickInput] Failed to save new contact: \(error)")
        }
        
        // Focus the input field for adding a note
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            fieldIsFocused = true
        }
    }

    private func selectExistingContact(_ contact: Contact) {
        selectedContact = contact
        text = ""
        filterString = ""
        suggestedContacts = []
        shouldShowCreateButton = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            parsedContacts = []
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            fieldIsFocused = true
        }
    }

    private func buildNoteFromText(for contact: Contact, text: String) -> Note? {
        var working = text
        let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var detectedDate: Date? = nil

        if let matches = dateDetector?.matches(in: working, options: [], range: NSRange(location: 0, length: working.utf16.count)) {
            for match in matches {
                if match.resultType == .date, let date = match.date {
                    detectedDate = adjustToPast(date)
                    if let range = Range(match.range, in: working) {
                        working.removeSubrange(range)
                    }
                    break
                }
            }
        }

        var isLongAgo = false
        let patterns = ["\\blong\\s*time\\s*ago\\b", "\\blta\\b"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: working.utf16.count)
                if regex.firstMatch(in: working, options: [], range: range) != nil {
                    isLongAgo = true
                }
                working = regex.stringByReplacingMatches(in: working, options: [], range: range, withTemplate: "")
            }
        }

        // Extract tag names first, validate them properly
        let tagNames = extractValidTagNames(from: working)
        
        // Remove tag tokens from working text
        var tokens = working.split(whereSeparator: { $0.isWhitespace })
        tokens.removeAll(where: { $0.hasPrefix("#") })
        working = tokens.joined(separator: " ")

        // NOW create the Tag objects and assign to contact
        var contactTags = contact.tags ?? []
        for tagName in tagNames {
            if let tag = Tag.fetchOrCreate(named: tagName, in: modelContext) {
                if !contactTags.contains(where: { $0.normalizedKey == tag.normalizedKey }) {
                    contactTags.append(tag)
                }
            }
        }
        
        if !contactTags.isEmpty {
            contact.tags = contactTags
            for t in contactTags {
                t.updateRange(withSeed: detectedDate ?? Date())
            }
        }

        let content = working.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let when = detectedDate ?? Date()
        if isLongAgo {
            contact.isMetLongAgo = true
        }
        return Note(content: content, creationDate: when, isLongAgo: isLongAgo)
    }

    private func buildQuickNoteFromText(_ raw: String) -> QuickNote? {
        var working = stripQuickNotePrefix(from: raw)

        if working.isEmpty { return nil }

        let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var detectedDate: Date? = nil

        if let matches = dateDetector?.matches(in: working, options: [], range: NSRange(location: 0, length: working.utf16.count)) {
            for match in matches {
                if match.resultType == .date, let date = match.date {
                    detectedDate = adjustToPast(date)
                    if let range = Range(match.range, in: working) {
                        working.removeSubrange(range)
                    }
                    break
                }
            }
        }

        var isLongAgo = false
        let patterns = ["\\blong\\s*time\\s*ago\\b", "\\blta\\b"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: working.utf16.count)
                if regex.firstMatch(in: working, options: [], range: range) != nil {
                    isLongAgo = true
                }
                working = regex.stringByReplacingMatches(in: working, options: [], range: range, withTemplate: "")
            }
        }

        let content = working.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let when = detectedDate ?? Date()
        return QuickNote(content: content, date: when, isLongAgo: isLongAgo, isProcessed: false)
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

    private func stripQuickNoteMarkers(from input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPattern = #"(?i)^(quick\s*note|quick)\b[\s:]*"#
        if let r = s.range(of: prefixPattern, options: .regularExpression) {
            s = String(s[r.upperBound...])
        }
        let separators = CharacterSet.whitespacesAndNewlines
        let punct = CharacterSet.punctuationCharacters
        let filteredTokens: [String] = s.components(separatedBy: separators).compactMap { raw in
            guard !raw.isEmpty else { return nil }
            let trimmedToken = raw.trimmingCharacters(in: punct)
            if trimmedToken.isEmpty { return nil }
            let lower = trimmedToken.lowercased()
            if lower == "qn" || lower == "q" { return nil }
            if lower == "quick" || lower == "quicknote" { return nil }
            return raw
        }

        let joined = filteredTokens.joined(separator: " ")
        return joined.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handlePhotoPicked(image: UIImage, date: Date?) {
        // Only auto-assign if a single contact is selected
        guard let selectedContact = selectedContact else {
            // Pass through to normal photo picker flow if no contact selected
            print("📸 [QuickInput] No contact selected, passing to fallback")
            onPhotoPicked?(image, date)
            return
        }
        
        Task {
            let success = await detectAndAssignSingleFace(to: selectedContact, image: image)
            
            await MainActor.run {
                if success {
                    print("✅ [QuickInput] Successfully auto-assigned single face to \(selectedContact.name ?? "contact")")
                } else {
                    print("📸 [QuickInput] Auto-assignment failed (0 or multiple faces), passing to fallback")
                    onPhotoPicked?(image, date)
                }
            }
        }
    }

    private func detectAndAssignSingleFace(to contact: Contact, image: UIImage) async -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        await MainActor.run {
            isProcessingPhoto = true
        }
        
        defer {
            Task { @MainActor in
                isProcessingPhoto = false
            }
        }
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform([request])
            
            if let observations = request.results as? [VNFaceObservation],
               observations.count == 1,
               let face = observations.first {
                
                let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
                let rect = FaceCrop.expandedRect(for: face, imageSize: imageSize)
                
                if !rect.isNull && !rect.isEmpty,
                   let cropped = cgImage.cropping(to: rect) {
                    let faceImage = UIImage(cgImage: cropped)
                    
                    // Update the selected contact with this photo
                    await MainActor.run {
                        contact.photo = faceImage.jpegData(compressionQuality: 0.92) ?? Data()
                    }
                    
                    do {
                        try await MainActor.run {
                            try modelContext.save()
                        }
                        return true
                    } catch {
                        print("❌ [QuickInput] Failed to save contact with new photo: \(error)")
                    }
                }
            } else {
                let count = (request.results as? [VNFaceObservation])?.count ?? 0
                print("📸 [QuickInput] Detected \(count) faces, need exactly 1 for auto-assignment")
            }
        } catch {
            print("❌ [QuickInput] Face detection failed: \(error)")
        }
        return false
    }
}

private struct BottomInputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SuggestionsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FaceCarouselHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TotalQuickInputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Notification name for live text updates
extension Notification.Name {
    static let quickInputTextDidChange = Notification.Name("QuickInputTextDidChange")
    static let quickInputRequestFocus = Notification.Name("QuickInputRequestFocus")
    static let quickInputResignFocus = Notification.Name("QuickInputResignFocus")
    static let quickInputCameraDidPickPhoto = Notification.Name("QuickInputCameraDidPickPhoto")
    static let quickInputCameraDidDismiss = Notification.Name("QuickInputCameraDidDismiss")
}

private extension View {
    @ViewBuilder
    func glassBackground<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 15.0, *) {
            self.background(.ultraThinMaterial, in: shape)
        } else {
            self.background(Color.secondary.opacity(0.12), in: shape)
        }
    }
} 

private struct InputBubble<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .liquidGlass(in: .rect(cornerRadius: 32))
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 64, alignment: .center)
    }
}