import SwiftUI

struct GroupActionsSheet: View {
    let date: Date
    let onImport: () -> Void
    let onEditDate: () -> Void
    let onEditTag: () -> Void
    let onRenameTag: () -> Void
    let onDeleteAll: () -> Void
    @State private var isBusy = false
    @State private var showConfirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(date, style: .date)
                                .font(.title3.weight(.semibold))
                            Text(relativeString(for: date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            isBusy = true
                            onImport()
                        } label: {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("Import photos for this day")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            isBusy = true
                            onEditDate()
                        } label: {
                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                Text("Edit date")
                                Spacer()
                            }
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            isBusy = true
                            onEditTag()
                        } label: {
                            HStack {
                                Image(systemName: "tag")
                                Text("Change tag")
                                Spacer()
                            }
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            isBusy = true
                            onRenameTag()
                        } label: {
                            HStack {
                                Image(systemName: "pencil")
                                Text("Rename tag")
                                Spacer()
                            }
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showConfirmDelete = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete all entries for this day")
                                Spacer()
                            }
                            .foregroundStyle(.red)
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 8)
                    }
                    .padding()
                }

                if isBusy {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 12))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .navigationTitle("Group")
            .navigationBarTitleDisplayMode(.inline)
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
            .presentationSizing(.page)
            #endif
            // macOS window now gets a comfortable default size without UIKit colors
            .alert("Move to Deleted?", isPresented: $showConfirmDelete) {
                Button("Cancel", role: .cancel) { }
                Button("Move to Deleted", role: .destructive) {
                    onDeleteAll()
                }
            } message: {
                Text("These entries will move to Deleted. You can restore them later from the Deleted view.")
            }
        }
    }

    private func relativeString(for date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}