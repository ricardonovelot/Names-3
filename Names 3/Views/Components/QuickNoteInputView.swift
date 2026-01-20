import SwiftUI
import SwiftData

struct QuickNoteInputView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var text: String = ""
    @FocusState private var fieldIsFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Quick note", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($fieldIsFocused)
                    .lineLimit(1...5)
                    .onSubmit {
                        saveQuickNote()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .liquidGlass(in: .rect(cornerRadius: 32))
            .frame(minHeight: 64, alignment: .center)
            
            Button {
                saveQuickNote()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(text.isEmpty ? .gray : .blue)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                fieldIsFocused = true
            }
        }
    }
    
    private func saveQuickNote() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var detectedDate: Date? = nil
        var cleanedText = trimmed
        
        if let matches = dateDetector?.matches(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) {
            for match in matches {
                if match.resultType == .date, let date = match.date {
                    detectedDate = adjustToPast(date)
                    if let range = Range(match.range, in: trimmed) {
                        cleanedText.removeSubrange(range)
                    }
                    break
                }
            }
        }
        
        var isLongAgo = false
        let patterns = ["\\blong\\s*time\\s*ago\\b", "\\blta\\b"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: cleanedText.utf16.count)
                if regex.firstMatch(in: cleanedText, options: [], range: range) != nil {
                    isLongAgo = true
                }
                cleanedText = regex.stringByReplacingMatches(in: cleanedText, options: [], range: range, withTemplate: "")
            }
        }
        
        let content = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let when = detectedDate ?? Date()
        
        let quickNote = QuickNote(content: content, date: when, isLongAgo: isLongAgo, isProcessed: false)
        modelContext.insert(quickNote)
        
        do {
            try modelContext.save()
            text = ""
            fieldIsFocused = true
        } catch {
            print("❌ Failed to save quick note: \(error)")
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
}