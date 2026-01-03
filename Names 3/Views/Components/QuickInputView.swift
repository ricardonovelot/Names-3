import SwiftUI
import SwiftData
import SmoothGradient

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

    // Optional quick note to link created entities to, and flag to allow/deny quick note creation
    var linkedQuickNote: QuickNote? = nil
    var allowQuickNoteCreation: Bool = true

    // People suggestions and selection
    @Query(filter: #Predicate<Contact> { $0.isArchived == false })
    private var contacts: [Contact]

    // Unified input state
    @State private var text: String = ""
    @FocusState private var fieldIsFocused: Bool
    @State private var bottomInputHeight: CGFloat = 0
    @State private var suggestionsHeight: CGFloat = 0
    @State private var isLoading = false

    // People-mode state
    @State private var filterString: String = ""
    @State private var suggestedContacts: [Contact] = []
    @State private var parseDebounceWork: DispatchWorkItem?
    @State private var quickNoteActive: Bool = false
    @State private var suppressNextClear: Bool = false

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
        VStack {
            HStack(spacing: 6) {
                InputBubble {
                    HStack(spacing: 8) {
                        if mode == .people, let token = selectedContact {
                            HStack(spacing: 6) {
                                Text(token.name ?? "Unnamed")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                Button {
                                    selectedContact = nil
                                    text = ""
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(30))
                                        fieldIsFocused = true
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
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
                                if let last = newValue.last, last == "\n" {
                                    text.removeLast()
                                    save()
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
                                    .allowsHitTesting(false)
                            }
                        }

                        if mode == .people {
                            Button {
                                onCameraTap?()
                            } label: {
                                Image(systemName: "camera")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if mode == .people {
                    Button {
                        if isQuickNotesActive {
                            isQuickNotesActive = false
                            onQuickNoteCleared?()
                        } else {
                            isQuickNotesActive = true
                            onQuickNoteDetected?()
                        }
                    } label: {
                        Image(systemName: isQuickNotesActive ? "person" : "note.text" )
                            .fontWeight(.medium)
                            .padding(10)
                            .glassBackground(Circle())
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(isQuickNotesActive ? "Switch to People" : "Switch to Quick Notes")
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            if mode == .people, selectedContact == nil && !filterString.isEmpty && !suggestedContacts.isEmpty {
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
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 24, height: 24)
                                            .overlay {
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
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
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: suggestedContacts.map(\.id))
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
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: !suggestedContacts.isEmpty)
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
        .preference(key: TotalQuickInputHeightKey.self, value: bottomInputHeight + suggestionsHeight + 8)
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
            selectedContact = nil
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
            for contact in parsedContacts {
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
                return
            } else {
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
                    return
                }
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

        let nameEntries = cleanedInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var previews: [Contact] = []
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

                let contact = Contact(name: name, timestamp: finalDate, notes: notes, tags: globalTags, photo: Data())
                contact.summary = summary
                contact.isMetLongAgo = longAgoDetected
                previews.append(contact)
            }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            parsedContacts = previews
        }
    }

    private func filterContacts() {
        if filterString.isEmpty {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                suggestedContacts = []
            }
        } else {
            let q = filterString.trimmingCharacters(in: .whitespacesAndNewlines)
            let filtered = contacts.filter { contact in
                guard let name = contact.name, !q.isEmpty else { return false }
                if name.localizedStandardContains(q) { return true }
                return name.lowercased().hasPrefix(q.lowercased())
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                suggestedContacts = filtered
            }
        }
    }

    private func selectExistingContact(_ contact: Contact) {
        selectedContact = contact
        text = ""
        filterString = ""
        suggestedContacts = []
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

        var contactTags = contact.tags ?? []
        let tokens = working.split(whereSeparator: { $0.isWhitespace })
        var retainedTokens: [Substring] = []
        for tok in tokens {
            if tok.hasPrefix("#") {
                let raw = tok.dropFirst()
                let trimmed = raw.trimmingCharacters(in: .punctuationCharacters)
                if !trimmed.isEmpty {
                    if let tag = Tag.fetchOrCreate(named: String(trimmed), in: modelContext) {
                        if !contactTags.contains(where: { $0.normalizedKey == tag.normalizedKey }) {
                            contactTags.append(tag)
                        }
                    }
                }
            } else {
                retainedTokens.append(tok)
            }
        }
        if !contactTags.isEmpty {
            contact.tags = contactTags
        }
        working = retainedTokens.joined(separator: " ")

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

struct TotalQuickInputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 24))
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44, alignment: .center)
    }
}