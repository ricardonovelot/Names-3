//
//  JournalEntryDetailView.swift
//  Names 3
//
//  View and inline-edit a single journal entry.
//

import SwiftUI
import SwiftData

struct JournalEntryDetailView: View {
    @Bindable var entry: JournalEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showDatePicker = false
    @State private var showDeleteAlert = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $entry.title)
                    .font(.body)
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if entry.content.isEmpty {
                        Text("What's on your mind?")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $entry.content)
                        .frame(minHeight: 200)
                }
            }

            Section {
                HStack {
                    Label("Date", systemImage: "calendar")
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        showDatePicker.toggle()
                    }
                }

                if showDatePicker {
                    DatePicker("", selection: $entry.date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .navigationTitle(entry.title.isEmpty ? "Entry" : entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .alert("Delete Entry", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry will be permanently deleted.")
        }
    }
}
