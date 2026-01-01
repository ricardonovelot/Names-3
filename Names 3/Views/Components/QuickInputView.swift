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
    var onCameraTap: (() -> Void)? = nil
    var onQuickNoteAdded: (() -> Void)? = nil
    var onQuickNoteDetected: (() -> Void)? = nil
    var onQuickNoteCleared: (() -> Void)? = nil

    // People suggestions and selection
    @Query(filter: #Predicate<Contact> { $0.isArchived == false })
    private var contacts: [Contact]

    // UI State
    @State private var text: String = ""
    @FocusState private var fieldIsFocused: Bool
    @State private var bottomInputHeight: CGFloat = 0
    @State private var isLoading = false

    // People-mode state
    @State private var selectedExistingContact: Contact?
    @State private var noteTextForExisting: String = ""
    @State private var filterString: String = ""
    @State private var suggestedContacts: [Contact] = []
    @State private var parseDebounceWork: DispatchWorkItem?
    @State private var quickNoteActive: Bool = false
    @State private var suppressNextClear: Bool = false

    private var quickNoteKeywords: [String] { ["quick note", "quick", "qn"] }

    private func isQuickNoteCommand(_ input: String) -> Bool {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // prefix forms for "quick" / "quick note"
        let prefixPattern = #"^(quick\s*note|quick)\b[\s:]*"#
        if s.range(of: prefixPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        // anywhere standalone token "qn" (optionally followed by colon)
        let anywhereQN = #"(?i)\bqn\b"#
        return s.range(of: anywhereQN, options: .regularExpression) != nil
    }

    private func stripQuickNotePrefix(from input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPattern = #"(?i)^(quick\s*note|quick)\b[\s:]*"#
        if let r = s.range(of: prefixPattern, options: .regularExpression) {
            s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Remove any standalone "qn" tokens (case-insensitive), optional spaces and trailing punctuation like ":" or ",".
        let qnPattern = #"(?i)\bqn\b\s*[:;,]?"#
        s = s.replacingOccurrences(of: qnPattern, with: "", options: .regularExpression)
        // Collapse multiple spaces and trim again
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    var body: some View {
        VStack {
            HStack(spacing: 6) {
                Group {
                    if mode == .people, let token = selectedExistingContact {
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Text(token.name ?? "Unnamed")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                Button {
                                    selectedExistingContact = nil
                                    noteTextForExisting = ""
                                    fieldIsFocused = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())

                            TextField("Add a note…", text: $noteTextForExisting, axis: .vertical)
                                .onChange(of: noteTextForExisting) { oldValue, newValue in
                                    if let last = newValue.last, last == "\n" {
                                        noteTextForExisting.removeLast()
                                        save()
                                    }
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($fieldIsFocused)
                        .submitLabel(.send)
                    } else {
                        TextField("", text: $text, axis: .vertical)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 8)
                            .focused($fieldIsFocused)
                            .submitLabel(.send)
                            .onChange(of: text) { oldValue, newValue in
                                if let last = newValue.last, last == "\n" {
                                    text.removeLast()
                                    save()
                                } else {
                                    if mode == .people {
                                        parseDebounceWork?.cancel()
                                        let s = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if isQuickNoteCommand(s) {
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
                    }
                }
                .liquidGlass(in: Capsule())
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if mode == .people {
                    Button {
                        onCameraTap?()
                    } label: {
                        Image(systemName: "camera")
                            .fontWeight(.medium)
                            .padding(10)
                            .liquidGlass(in: Capsule())
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: BottomInputHeightKey.self, value: proxy.size.height)
            }
        )
        .overlay(alignment: .bottom) {
            if mode == .people, selectedExistingContact == nil && !filterString.isEmpty && !suggestedContacts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedContacts) { contact in
                            Button {
                                selectExistingContact(contact)
                            } label: {
                                Text(contact.name ?? "Unnamed")
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal)
                .padding(.bottom, bottomInputHeight + 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onPreferenceChange(BottomInputHeightKey.self) { bottomInputHeight = $0 }
    }

    private func save() {
        isLoading = true
        defer { isLoading = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = selectedExistingContact, mode == .people {
            if let note = buildNoteFromText(for: existing, text: noteTextForExisting) {
                if existing.notes == nil { existing.notes = [] }
                existing.notes?.append(note)
                do { try modelContext.save() } catch { print("Save failed: \(error)") }
            }
            noteTextForExisting = ""
            selectedExistingContact = nil
            resetTextAndPreview()
            return
        }

        if isQuickNoteCommand(trimmed) || mode == .quickNotes {
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
            parsedContacts = []
            filterString = ""
            suggestedContacts = []
            return
        }

        let detected = isQuickNoteCommand(trimmed)
        if detected {
            if !quickNoteActive {
                quickNoteActive = true
                onQuickNoteDetected?()
            }
            parsedContacts = []
            filterString = ""
            suggestedContacts = []
            return
        } else if quickNoteActive {
            // Lost quick-note detection (e.g. "Maria Qn" -> "Maria Q"):
            // Exit quick-notes mode, strip markers, keep remaining text, then continue parsing People.
            quickNoteActive = false
            onQuickNoteCleared?()
            let sanitized = stripQuickNoteMarkers(from: workingInput)
            workingInput = sanitized
            text = sanitized
            trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                parsedContacts = []
                filterString = ""
                suggestedContacts = []
                return
            }
        }

        // From here on, parse People input using workingInput
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
            suggestedContacts = contacts
        } else {
            let q = filterString.trimmingCharacters(in: .whitespacesAndNewlines)
            suggestedContacts = contacts.filter { contact in
                guard let name = contact.name, !q.isEmpty else { return false }
                if name.localizedStandardContains(q) { return true }
                return name.lowercased().hasPrefix(q.lowercased())
            }
        }
    }

    private func selectExistingContact(_ contact: Contact) {
        selectedExistingContact = contact
        noteTextForExisting = ""
        text = ""
        filterString = ""
        suggestedContacts = []
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            parsedContacts = []
        }
        fieldIsFocused = true
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

        // Remove prefix "quick note" or "quick"
        let prefixPattern = #"(?i)^(quick\s*note|quick)\b[\s:]*"#
        if let r = s.range(of: prefixPattern, options: .regularExpression) {
            s = String(s[r.upperBound...])
        }

        // Tokenize and remove standalone q/qa/qn variants (case-insensitive) with trailing punctuation
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