//
//  JournalTabView.swift
//  Names 3
//
//  Root view for the Journal tab — lists all entries sorted by date descending.
//

import SwiftUI
import SwiftData

struct JournalTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\JournalEntry.date, order: .reverse)])
    private var entries: [JournalEntry]

    var bottomBarHeight: CGFloat = 0

    /// Drives programmatic push to a just-created entry after quick-input save.
    @State private var entryToOpen: JournalEntry?
    /// Stores the UUID of an entry created via quick input while we wait for @Query to catch up.
    @State private var pendingOpenUUID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    entryList
                }
            }
            .navigationDestination(item: $entryToOpen) { entry in
                JournalEntryDetailView(entry: entry)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: bottomBarHeight)
            }
            // When @Query refreshes and the pending entry is now available, push to it.
            .onChange(of: entries) { _, newEntries in
                guard let uuid = pendingOpenUUID else { return }
                if let match = newEntries.first(where: { $0.uuid == uuid }) {
                    pendingOpenUUID = nil
                    entryToOpen = match
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalEntryDidCreate)) { notification in
            guard let uuid = notification.userInfo?["uuid"] as? UUID else { return }
            // Try the fast path first: entry is already in @Query results.
            if let match = entries.first(where: { $0.uuid == uuid }) {
                entryToOpen = match
            } else {
                // Fall back: wait for the next @Query refresh cycle.
                pendingOpenUUID = uuid
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Entries Yet")
                .font(.headline)
            Text("Tap the pencil icon to write your first gratitude entry.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(name: .quickInputResignFocus, object: nil)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(entries, id: \.uuid) { entry in
                    NavigationLink {
                        JournalEntryDetailView(entry: entry)
                    } label: {
                        entryRow(entry)
                    }
                    .id(entry.uuid)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(entry)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .journalFeedScrollToTop)) { _ in
                if let first = entries.first {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(first.uuid, anchor: .top)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.always)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                NotificationCenter.default.post(name: .quickInputResignFocus, object: nil)
            }
        )
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    private func entryRow(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.content.isEmpty {
                Text(entry.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    JournalTabView()
        .modelContainer(for: JournalEntry.self, inMemory: true)
}
