import SwiftUI
import SwiftData
import SmoothGradient

struct QuickNotesFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [SortDescriptor(\QuickNote.date, order: .reverse)])
    private var quickNotes: [QuickNote]

    @State private var text: String = ""
    @FocusState private var fieldIsFocused: Bool
    @State private var bottomInputHeight: CGFloat = 0

    private var dynamicBackground: Color {
        if fieldIsFocused {
            return colorScheme == .light ? .clear : .clear
        } else {
            return colorScheme == .light ? .clear : .clear
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if quickNotes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No quick notes")
                            .font(.headline)
                        Text("Capture thoughts fast using the input below or from the People tab using “quick” or “quick note”.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
                } else {
                    List {
                        ForEach(quickNotes, id: \.self) { qn in
                            QuickNoteEditableRow(quickNote: qn)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(qn.isProcessed ? "Unprocess" : "Processed") {
                                        qn.isProcessed.toggle()
                                        try? modelContext.save()
                                    }
                                    .tint(qn.isProcessed ? .orange : .green)

                                    Button(role: .destructive) {
                                        modelContext.delete(qn)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Quick Notes")
            .safeAreaInset(edge: .bottom) { bottomInput }
        }
    }

    @ViewBuilder
    private var bottomInput: some View {
        VStack {
            HStack(spacing: 6) {
                TextField("", text: $text, axis: .vertical)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
                    .focused($fieldIsFocused)
                    .submitLabel(.send)
                    .onChange(of: text) { oldValue, newValue in
                        if let last = newValue.last, last == "\n" {
                            text.removeLast()
                            saveQuickNote()
                        }
                    }
                    .liquidGlass(in: Capsule())
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal)
        .background(dynamicBackground)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: BottomInputHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(BottomInputHeightKey.self) { bottomInputHeight = $0 }
    }

    private func saveQuickNote() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let qn = buildQuickNoteFromText(trimmed) {
            modelContext.insert(qn)
            try? modelContext.save()
        }

        text = ""
    }

    private func buildQuickNoteFromText(_ raw: String) -> QuickNote? {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = working.lowercased()
        if lower.hasPrefix("quick note") {
            working = String(working.dropFirst("quick note".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("quick") {
            working = String(working.dropFirst("quick".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if working.hasPrefix(":") {
            working.removeFirst()
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
}

private struct QuickNoteEditableRow: View {
    @Bindable var quickNote: QuickNote
    @State private var showDatePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Quick note", text: $quickNote.content, axis: .vertical)
                .lineLimit(2...)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                if quickNote.isProcessed {
                    Label("Processed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()

                Group {
                    if quickNote.isLongAgo {
                        Text("Long time ago")
                    } else {
                        Text(quickNote.date, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .onTapGesture {
                    showDatePicker = true
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                Form {
                    Toggle("Long ago", isOn: $quickNote.isLongAgo)
                    DatePicker("Exact Date", selection: $quickNote.date, in: ...Date(), displayedComponents: .date)
                        .disabled(quickNote.isLongAgo)
                }
                .navigationTitle("Quick Note Date")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct BottomInputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}