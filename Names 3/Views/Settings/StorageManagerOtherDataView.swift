//
//  StorageManagerOtherDataView.swift
//  Names 3
//
//  Identify and delete notes, quick notes, tags. Compact database. Clear quiz/rehearsal history.
//

import SwiftUI
import SwiftData

struct StorageManagerOtherDataView: View {
    @Environment(\.modelContext) private var modelContext

    var otherMetadataSize: Int64 = 0
    var otherBreakdown: OtherDataBreakdown = OtherDataBreakdown()

    @State private var notes: [(note: Note, size: Int64)] = []
    @State private var quickNotes: [(note: QuickNote, size: Int64)] = []
    @State private var tags: [(tag: Tag, size: Int64)] = []
    @State private var isLoading = true
    @State private var noteToDelete: Note?
    @State private var quickNoteToDelete: QuickNote?
    @State private var tagToDelete: Tag?
    @State private var isCompacting = false
    @State private var compactFreed: Int64?
    @State private var isShrinking = false
    @State private var shrinkResult: (Int, Int)?
    @State private var showShrinkConfirmation = false
    @State private var showClearQuizConfirmation = false
    @State private var showClearRehearsalConfirmation = false

    private var otherBreakdownRows: [(title: String, icon: String, size: Int64)] {
        [
            (String(localized: "storage.app.other.breakdown.contactMetadata"), "person.text.rectangle", otherBreakdown.contactMetadata),
            (String(localized: "storage.app.other.breakdown.faceMetadata"), "face.smiling", otherBreakdown.faceMetadata),
            (String(localized: "storage.app.other.breakdown.faceClusters"), "square.stack.3d.up", otherBreakdown.faceClusters),
            (String(localized: "storage.app.other.breakdown.quizHistory"), "brain.head.profile", otherBreakdown.quizHistory),
            (String(localized: "storage.app.other.breakdown.noteRehearsal"), "note.text", otherBreakdown.noteRehearsal),
            (String(localized: "storage.app.other.breakdown.quizSessions"), "list.bullet.clipboard", otherBreakdown.quizSessions),
            (String(localized: "storage.app.other.breakdown.deletedPhotos"), "photo.badge.plus", otherBreakdown.deletedPhotos),
            (String(localized: "storage.app.other.breakdown.databaseOverhead"), "internaldrive", otherBreakdown.databaseOverhead),
        ]
    }

    var body: some View {
        List {
            if otherMetadataSize > 0 {
                actionsSection
            }
            if isLoading {
                HStack {
                    ProgressView()
                    Text(String(localized: "storage.calculating"))
                        .foregroundStyle(.secondary)
                }
            } else {
                if !notes.isEmpty {
                    Section {
                        ForEach(notes, id: \.note.uuid) { item in
                            NoteRow(note: item.note, size: item.size) {
                                noteToDelete = item.note
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("storage.app.other.notes"))
                    }
                }

                if !quickNotes.isEmpty {
                    Section {
                        ForEach(quickNotes, id: \.note.uuid) { item in
                            QuickNoteRow(note: item.note, size: item.size) {
                                quickNoteToDelete = item.note
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("storage.app.other.quickNotes"))
                    }
                }

                if !tags.isEmpty {
                    Section {
                        ForEach(Array(tags.enumerated()), id: \.offset) { _, item in
                            TagRow(tag: item.tag, size: item.size) {
                                tagToDelete = item.tag
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("storage.app.other.tags"))
                    }
                }

                if otherMetadataSize > 0 {
                    Section {
                        ForEach(Array(otherBreakdownRows.enumerated()), id: \.offset) { _, row in
                            if row.size > 0 {
                                HStack {
                                    Label(row.title, systemImage: row.icon)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("storage.app.other.breakdown.header"))
                    } footer: {
                        Text(LocalizedStringKey("storage.app.other.breakdown.footer"))
                    }
                }

                if notes.isEmpty && quickNotes.isEmpty && tags.isEmpty && otherMetadataSize <= 0 {
                    ContentUnavailableView(
                        String(localized: "storage.other.empty.title"),
                        systemImage: "doc.text",
                        description: Text(String(localized: "storage.other.empty.subtitle"))
                    )
                }
            }
        }
        .navigationTitle(String(localized: "storage.app.otherData"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(String(localized: "storage.other.deleteNote.title"), isPresented: Binding(
            get: { noteToDelete != nil },
            set: { if !$0 { noteToDelete = nil } }
        )) {
            if noteToDelete != nil {
                Button(String(localized: "storage.delete"), role: .destructive) {
                    if let n = noteToDelete { StorageManagerService.shared.deleteNote(n, context: modelContext) }
                    noteToDelete = nil
                    Task { await load() }
                    NotificationCenter.default.post(name: .storageDidChange, object: nil)
                }
            }
            Button(String(localized: "storage.cancel"), role: .cancel) { noteToDelete = nil }
        } message: {
            Text(String(localized: "storage.other.deleteNote.message"))
        }
        .confirmationDialog(String(localized: "storage.other.deleteQuickNote.title"), isPresented: Binding(
            get: { quickNoteToDelete != nil },
            set: { if !$0 { quickNoteToDelete = nil } }
        )) {
            if quickNoteToDelete != nil {
                Button(String(localized: "storage.delete"), role: .destructive) {
                    if let n = quickNoteToDelete { StorageManagerService.shared.deleteQuickNote(n, context: modelContext) }
                    quickNoteToDelete = nil
                    Task { await load() }
                    NotificationCenter.default.post(name: .storageDidChange, object: nil)
                }
            }
            Button(String(localized: "storage.cancel"), role: .cancel) { quickNoteToDelete = nil }
        } message: {
            Text(String(localized: "storage.other.deleteQuickNote.message"))
        }
        .confirmationDialog(String(localized: "storage.other.deleteTag.title"), isPresented: Binding(
            get: { tagToDelete != nil },
            set: { if !$0 { tagToDelete = nil } }
        )) {
            if tagToDelete != nil {
                Button(String(localized: "storage.delete"), role: .destructive) {
                    if let t = tagToDelete { StorageManagerService.shared.deleteTag(t, context: modelContext) }
                    tagToDelete = nil
                    Task { await load() }
                    NotificationCenter.default.post(name: .storageDidChange, object: nil)
                }
            }
            Button(String(localized: "storage.cancel"), role: .cancel) { tagToDelete = nil }
        } message: {
            Text(String(localized: "storage.other.deleteTag.message"))
        }
        .confirmationDialog(String(localized: "storage.shrink.dialog.title"), isPresented: $showShrinkConfirmation) {
            Button(String(localized: "storage.actions.shrink"), role: .none) {
                runShrink()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(localized: "storage.shrink.dialog.message"))
        }
        .confirmationDialog(String(localized: "storage.other.clearQuiz.title"), isPresented: $showClearQuizConfirmation) {
            Button(String(localized: "storage.other.clearQuiz.action"), role: .destructive) {
                clearQuizHistory()
            }
            Button(String(localized: "storage.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "storage.other.clearQuiz.message"))
        }
        .confirmationDialog(String(localized: "storage.other.clearRehearsal.title"), isPresented: $showClearRehearsalConfirmation) {
            Button(String(localized: "storage.other.clearRehearsal.action"), role: .destructive) {
                clearRehearsalHistory()
            }
            Button(String(localized: "storage.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "storage.other.clearRehearsal.message"))
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                compactDatabase()
            } label: {
                HStack {
                    Label(String(localized: "storage.actions.compact"), systemImage: "arrow.down.doc")
                    Spacer()
                    if isCompacting {
                        ProgressView()
                    } else if let freed = compactFreed, freed > 0 {
                        Text(String(format: String(localized: "storage.actions.freed"), Double(freed) / 1_000_000))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .disabled(isCompacting)

            Button {
                showShrinkConfirmation = true
            } label: {
                HStack {
                    Label(String(localized: "storage.actions.shrink"), systemImage: "arrow.down.right.and.arrow.up.left")
                    Spacer()
                    if isShrinking {
                        ProgressView()
                    } else if let (c, e) = shrinkResult, c + e > 0 {
                        Text(String(format: String(localized: "storage.actions.shrinkResult"), c + e))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .disabled(isShrinking)

            Button {
                showClearQuizConfirmation = true
            } label: {
                Label(String(localized: "storage.other.clearQuiz.action"), systemImage: "brain.head.profile")
            }

            Button {
                showClearRehearsalConfirmation = true
            } label: {
                Label(String(localized: "storage.other.clearRehearsal.action"), systemImage: "note.text")
            }
        } header: {
            Text(LocalizedStringKey("storage.actions.freeSpace"))
        } footer: {
            Text(LocalizedStringKey("storage.other.actions.footer"))
        }
    }

    private func load() async {
        isLoading = true
        notes = StorageManagerService.shared.fetchNotesWithSizes(context: modelContext)
        quickNotes = StorageManagerService.shared.fetchQuickNotesWithSizes(context: modelContext)
        tags = StorageManagerService.shared.fetchTagsWithSizes(context: modelContext)
        isLoading = false
    }

    private func compactDatabase() {
        isCompacting = true
        compactFreed = nil
        let freed = StorageManagerService.shared.compactDatabase(modelContext: modelContext)
        compactFreed = freed
        isCompacting = false
        NotificationCenter.default.post(name: .storageDidChange, object: nil)
    }

    private func runShrink() {
        isShrinking = true
        shrinkResult = nil
        shrinkResult = StorageManagerService.shared.runStorageShrink(modelContext: modelContext)
        isShrinking = false
        NotificationCenter.default.post(name: .storageDidChange, object: nil)
    }

    private func clearQuizHistory() {
        _ = StorageManagerService.shared.clearQuizHistory(context: modelContext)
        NotificationCenter.default.post(name: .storageDidChange, object: nil)
    }

    private func clearRehearsalHistory() {
        _ = StorageManagerService.shared.clearNoteRehearsalHistory(context: modelContext)
        NotificationCenter.default.post(name: .storageDidChange, object: nil)
    }
}

private struct NoteRow: View {
    let note: Note
    let size: Int64
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.content.isEmpty ? String(localized: "storage.emptyContent") : String(note.content.prefix(80)))
                    .lineLimit(2)
                    .font(.body)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
        }
    }
}

private struct QuickNoteRow: View {
    let note: QuickNote
    let size: Int64
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.content.isEmpty ? String(localized: "storage.emptyContent") : String(note.content.prefix(80)))
                    .lineLimit(2)
                    .font(.body)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
        }
    }
}

private struct TagRow: View {
    let tag: Tag
    let size: Int64
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(tag.name.isEmpty ? String(localized: "storage.unnamed") : tag.name)
                .font(.body)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
        }
    }
}
