import SwiftUI
import SwiftData
import SmoothGradient
import Vision
import UIKit
import TipKit

struct QuickInputView: View {
    @Environment(\.modelContext) private var modelContext

    // Bindings and hooks
    @Binding var parsedContacts: [Contact]
    @Binding var selectedContact: Contact?
    var onQuizTap: (() -> Void)? = nil
    var onQuickNoteAdded: (() -> Void)? = nil
    var onReturnOverride: (() -> Void)? = nil
    
    // Face carousel integration
    var faceDetectionViewModel: FaceDetectionViewModel? = nil
    var onFaceSelected: ((Int) -> Void)? = nil

    // Optional quick note to link created entities to
    var linkedQuickNote: QuickNote? = nil

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
    @State private var shouldShowCreateButton: Bool = false
    @State private var parsedTagNames: [String] = []

    // Photo processing state
    @State private var isProcessingPhoto = false

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
            
            VStack(spacing: 12) {
                TipView(QuickInputFormatTip(), arrowEdge: .bottom)
                    .padding(.horizontal)
                
                TipView(QuickInputBulkAddTip(), arrowEdge: .bottom)
                    .padding(.horizontal)
                
                TipView(QuickInputTagsTip(), arrowEdge: .bottom)
                    .padding(.horizontal)
                
                TipView(QuickInputDateParsingTip(), arrowEdge: .bottom)
                    .padding(.horizontal)
                
                HStack(spacing: 6) {
                    InputBubble {
                        HStack(spacing: 8) {
                            if let token = selectedContact {
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
                                        if !suggestedContacts.isEmpty {
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
                                        parseDebounceWork?.cancel()
                                        let work = DispatchWorkItem {
                                            parsePeopleInput()
                                        }
                                        parseDebounceWork = work
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
                                    }
                                }

                                if text.isEmpty {
                                    Text(selectedContact != nil ? "Add a note…" : "")
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 3)
                                        .padding(.top, 1)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }

                    Button {
                        onQuizTap?()
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .frame(width: controlSize, height: controlSize)
                            .liquidGlass(in: Circle())
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Open Quiz")
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            if selectedContact == nil && !filterString.isEmpty && (!suggestedContacts.isEmpty || shouldShowCreateButton) {
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
        .onReceive(NotificationCenter.default.publisher(for: .quickInputShowExample)) { notification in
            if let example = notification.userInfo?["example"] as? String {
                text = example
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    fieldIsFocused = true
                }
            }
        }
    }

    private func save() {
        isLoading = true
        defer { isLoading = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = selectedContact {
            if let note = buildNoteFromText(for: existing, text: trimmed) {
                if existing.notes == nil { existing.notes = [] }
                existing.notes?.append(note)
                if let qn = linkedQuickNote {
                    note.quickNote = qn
                    if qn.linkedNotes == nil { qn.linkedNotes = [] }
                    qn.linkedNotes?.append(note)
                }
                do { try modelContext.save() } catch { print("Save failed: \(error)") }
                
                TipManager.shared.donateNoteAdded()
            }
            text = ""
            resetTextAndPreview()
            return
        }

        var globalTags: [Tag] = []
        
        for tagName in parsedTagNames {
            if let tag = Tag.fetchOrCreate(named: tagName, in: modelContext, seedDate: Date()) {
                globalTags.append(tag)
            }
        }
        
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
        
        if parsedContacts.count > 0 {
            TipManager.shared.donateContactCreated()
        }
        
        resetTextAndPreview()
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                parsedContacts = []
            }
            filterString = ""
            suggestedContacts = []
            shouldShowCreateButton = false
            parsedTagNames = []
            return
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

    private func extractValidTagNames(from text: String) -> [String] {
        var tagNames: [String] = []
        var seenKeys = Set<String>()
        
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        
        for token in tokens {
            guard token.hasPrefix("#") else { continue }
            
            let raw = token.dropFirst()
            let trimmed = raw.trimmingCharacters(in: .punctuationCharacters)
            
            guard !trimmed.isEmpty else { continue }
            
            let tagString = String(token)
            if let range = text.range(of: tagString) {
                let startIndex = range.lowerBound
                
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
            
            let isValidName = !q.isEmpty && q.count >= 2 && !isQuickNoteCommand(q)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                suggestedContacts = filtered
                shouldShowCreateButton = isValidName
            }
        }
    }

    private func createNewContactFromFilterString() {
        let cleanedName: String
        
        if let firstParsed = parsedContacts.first {
            cleanedName = firstParsed.name ?? filterString.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            cleanedName = filterString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !cleanedName.isEmpty else { return }
        
        var tags: [Tag] = []
        for tagName in parsedTagNames {
            if let tag = Tag.fetchOrCreate(named: tagName, in: modelContext, seedDate: Date()) {
                tags.append(tag)
            }
        }
        
        let newContact = Contact(
            name: cleanedName,
            timestamp: Date(),
            notes: [],
            tags: tags,
            photo: Data()
        )
        newContact.uuid = UUID()
        
        selectedContact = newContact
        text = ""
        filterString = ""
        suggestedContacts = []
        shouldShowCreateButton = false
        parsedTagNames = []
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            parsedContacts = []
        }
        
        modelContext.insert(newContact)
        
        do {
            try modelContext.save()
        } catch {
            print("❌ [QuickInput] Failed to save new contact: \(error)")
        }
        
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

        let tagNames = extractValidTagNames(from: working)
        
        var tokens = working.split(whereSeparator: { $0.isWhitespace })
        tokens.removeAll(where: { $0.hasPrefix("#") })
        working = tokens.joined(separator: " ")

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

    private func adjustToPast(_ date: Date) -> Date {
        let today = Date()
        let calendar = Calendar.current

        if date > today {
            let adjustedDate = calendar.date(byAdding: .year, value: -1, to: date)
            return adjustedDate ?? date
        }

        return date
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

extension Notification.Name {
    static let quickInputTextDidChange = Notification.Name("QuickInputTextDidChange")
    static let quickInputRequestFocus = Notification.Name("QuickInputRequestFocus")
    static let quickInputResignFocus = Notification.Name("QuickInputResignFocus")
    static let quickInputShowExample = Notification.Name("QuickInputShowExample")
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