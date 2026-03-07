import SwiftUI
import SwiftData

// MARK: - Journal Quick Input

/// Mirrors `QuickInputView`'s visual design and interaction model for journal entries.
/// In the collapsed tab bar a magnifying glass circle appears; tapping expands this view.
/// Typing a title and hitting Return (or Send) instantly creates a `JournalEntry` and posts
/// `journalEntryDidCreate` so `JournalTabView` can navigate to the new entry for editing.
struct JournalQuickInputView: View {
    @Environment(\.modelContext) private var modelContext

    /// When `true`, renders the single-row Apple-Music–style pill used inside the tab bar.
    var inlineInBar: Bool = false

    /// Called right after the entry is persisted, with its UUID.
    var onEntryCreated: ((UUID) -> Void)? = nil

    @State private var text: String = ""
    @FocusState private var fieldIsFocused: Bool

    private let inputRowHeight: CGFloat = 56

    var body: some View {
        Group {
            if inlineInBar {
                appleMusicStyleInputRow
            } else {
                VStack(spacing: 0) {
                    inputControlsSection(controlSize: inputRowHeight)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickInputRequestFocus)) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                fieldIsFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickInputResignFocus)) { _ in
            fieldIsFocused = false
        }
    }

    // MARK: - Inline Bar Row (matches QuickInputView.appleMusicStyleInputRow exactly)

    @AppStorage(QuickInputExpandIconPreference.userDefaultsKey) private var quickInputExpandIconRaw: String = QuickInputExpandIconPreference.magnifyingglass.rawValue

    @ViewBuilder
    private var appleMusicStyleInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: (QuickInputExpandIconPreference(rawValue: quickInputExpandIconRaw) ?? .magnifyingglass).systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("New entry…")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                GrowingTextView(
                    text: $text,
                    isFirstResponder: Binding(
                        get: { fieldIsFocused },
                        set: { fieldIsFocused = $0 }
                    ),
                    minHeight: 20,
                    maxHeight: 80,
                    onDeleteWhenEmpty: nil,
                    onReturn: { handleReturn() }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: text) { _, newValue in handleTextChange(newValue) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 40)
    }

    // MARK: - Full (Non-Inline) View

    @ViewBuilder
    private func inputControlsSection(controlSize: CGFloat) -> some View {
        InputBubble(height: controlSize) {
            inputFieldContent
        }
        .frame(height: controlSize)
    }

    @ViewBuilder
    private var inputFieldContent: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                GrowingTextView(
                    text: $text,
                    isFirstResponder: Binding(
                        get: { fieldIsFocused },
                        set: { fieldIsFocused = $0 }
                    ),
                    minHeight: 22,
                    maxHeight: 140,
                    onDeleteWhenEmpty: nil,
                    onReturn: { handleReturn() }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: text) { _, newValue in handleTextChange(newValue) }

                if text.isEmpty {
                    Text("New entry…")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Input Handling

    private func handleReturn() {
        save()
    }

    private func handleTextChange(_ newValue: String) {
        if let last = newValue.last, last == "\n" {
            text.removeLast()
            save()
        }
    }

    // MARK: - Persistence

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = JournalEntry(title: trimmed, content: "", date: Date())
        modelContext.insert(entry)

        do {
            try modelContext.save()
        } catch {
            print("❌ [JournalQuickInput] Save failed: \(error)")
        }

        let savedUUID = entry.uuid
        text = ""

        onEntryCreated?(savedUUID)
        NotificationCenter.default.post(
            name: .journalEntryDidCreate,
            object: nil,
            userInfo: ["uuid": savedUUID]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a `JournalEntry` is created via quick input.
    /// `userInfo["uuid"]` contains the entry's `UUID`.
    static let journalEntryDidCreate = Notification.Name("Names3.JournalEntryDidCreate")
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        var body: some View {
            VStack {
                Spacer()
                JournalQuickInputView(inlineInBar: false)
                    .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
    return PreviewWrapper()
        .modelContainer(for: JournalEntry.self, inMemory: true)
}
