import SwiftUI
import SwiftData
import TipKit

struct HomeView: View {
    @Binding var tabSelection: AppTab
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Contact> { $0.isArchived == false }, sort: \Contact.timestamp, order: .reverse)
    private var contacts: [Contact]

    @Query(sort: [SortDescriptor(\Note.creationDate, order: .reverse)])
    private var notes: [Note]

    @Query(filter: #Predicate<QuickNote> { $0.isProcessed == false }, sort: [SortDescriptor(\QuickNote.date, order: .reverse)])
    private var unprocessedQuickNotes: [QuickNote]

    @State private var showBulkAddFaces = false
    @State private var showQuizView = false
    @State private var showDeletedView = false
    @State private var showManageTags = false
    @State private var showGroupPhotos = false
    @State private var showNotesQuiz = false

    private var topRecent: [Contact] {
        Array(contacts.prefix(12))
    }

    private var recentNotes: [Note] {
        Array(notes.prefix(6))
    }

    private var recentUnprocessedQuickNotes: [QuickNote] {
        Array(unprocessedQuickNotes.prefix(6))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    TipView(QuizStreakTip(), arrowEdge: .top)
                        .padding(.horizontal)

                    QuizCardsSectionView(
                        onFacesQuiz: { showQuizView = true },
                        onNotesQuiz: { showNotesQuiz = true }
                    )
                    
                    if !unprocessedQuickNotes.isEmpty {
                        TipView(QuickNotesProcessingTip(), arrowEdge: .top)
                            .padding(.horizontal)
                    }

                    UnprocessedQuickNotesSectionView(
                        quickNotes: recentUnprocessedQuickNotes
                    )

                    RecentNotesSectionView(
                        notes: recentNotes
                    )

                    recentContactsSection
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showQuizView) {
            QuizView(contacts: contacts, onComplete: { showQuizView = false }, onRequestExit: .none)
        }
        .sheet(isPresented: $showNotesQuiz) {
            NotesQuizView(contacts: contacts)
        }
        .sheet(isPresented: $showDeletedView) {
            DeletedView()
        }
        .sheet(isPresented: $showManageTags) {
            TagPickerView(mode: .manage)
        }
        .sheet(isPresented: $showBulkAddFaces) {
            BulkAddFacesView(contactsContext: modelContext)
                .modelContainer(BatchModelContainer.shared)
        }
        .sheet(isPresented: $showGroupPhotos) {
            GroupPhotosListView(contactsContext: modelContext)
                .modelContainer(BatchModelContainer.shared)
        }
        .background {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
        }
    }

    private var recentContactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Contacts")
                    .font(.title3.bold())
                Spacer()
                Button {
                    tabSelection = .people
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(topRecent) { contact in
                    NavigationLink {
                        ContactDetailsView(contact: contact)
                    } label: {
                        RecentTile(contact: contact)
                            .frame(height: 110)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct RecentTile: View {
    let contact: Contact

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if !contact.photo.isEmpty, let uiImage = UIImage(data: contact.photo) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                    
                    LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                } else {
                    ZStack {
                        RadialGradient(
                            colors: [
                                Color(uiColor: .secondarySystemBackground),
                                Color(uiColor: .tertiarySystemBackground)
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: size.width * 0.7
                        )
                        
                        Color.clear
                            .frame(width: size.width, height: size.height)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), stroke: true)
                    }
                }

                VStack {
                    Spacer()
                    Text(contact.name ?? "")
                        .font(.footnote.bold())
                        .foregroundStyle(contact.photo.isEmpty ? Color.primary.opacity(0.8) : Color.white.opacity(0.9))
                        .padding(.bottom, 6)
                        .padding(.horizontal, 6)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
    }
}

private struct RecentNotesSectionView: View {
    let notes: [Note]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People Notes")
                .font(.title3.bold())

            if notes.isEmpty {
                Text("No recent notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(notes, id: \.self) { note in
                        NavigationLink {
                            NoteDetailView(note: note)
                        } label: {
                            NoteListRow(note: note, showContact: true)
                        }
                        .buttonStyle(.plain)

                        if note.id != notes.last?.id {
                            Divider()
                        }
                    }

                    NavigationLink {
                        NotesFeedView()
                    } label: {
                        HStack(spacing: 6) {
                            Text("See all notes")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct UnprocessedQuickNotesSectionView: View {
    let quickNotes: [QuickNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Notes")
                .font(.title3.bold())

            if quickNotes.isEmpty {
                Text("No quick notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(quickNotes, id: \.self) { qn in
                        QuickNoteRow(quickNote: qn)

                        if qn.id != quickNotes.last?.id {
                            Divider()
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    NavigationLink {
                        QuickNotesFeedView()
                    } label: {
                        HStack(spacing: 6) {
                            Text("See all quick notes")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct QuickNoteRow: View {
    let quickNote: QuickNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(quickNote.content.isEmpty ? "—" : quickNote.content)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                NavigationLink {
                    QuickNoteDetailView(quickNote: quickNote)
                } label: {
                    Group {
                        if quickNote.isLongAgo {
                            Text("Long time ago")
                        } else {
                            Text(quickNote.date, style: .date)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct QuizCardsSectionView: View {
    let onFacesQuiz: () -> Void
    let onNotesQuiz: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onFacesQuiz) {
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 28, weight: .regular))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(.white)
                            .background(Color.teal)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Faces Quiz")
                                .font(.headline)
                            Text("Practice recognizing faces")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .popoverTip(NotesQuizTip())

                Button(action: onNotesQuiz) {
                    HStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 28, weight: .regular))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(.white)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notes Quiz")
                                .font(.headline)
                            Text("Test your memory of notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
