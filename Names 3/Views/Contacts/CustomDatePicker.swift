import SwiftUI
import SwiftData

struct CustomDatePicker: View {
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // All active (non-archived, non-long-ago) contacts to build tag-date options
    @Query(filter: #Predicate<Contact> { $0.isArchived == false && $0.isMetLongAgo == false })
    private var activeContacts: [Contact]

    @State private var showAllTagOptions = false

    var body: some View {
        NavigationStack {
            List {
                Section("From tags") {
                    let options = tagDateOptions()
                    let limited = showAllTagOptions ? options : Array(options.prefix(10))

                    if options.isEmpty {
                        Text("No tag-based dates available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(limited) { opt in
                            Button {
                                contact.isMetLongAgo = false
                                contact.timestamp = opt.date
                                contact.tags = [opt.tag]
                                do { try modelContext.save() } catch { print("Save failed: \(error)") }
                                dismiss()
                            } label: {
                                HStack {
                                    Text(opt.name)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(opt.date, style: .date)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !showAllTagOptions && options.count > 10 {
                            Button("See all tags") {
                                showAllTagOptions = true
                            }
                        }
                    }
                }

                Section("Pick a date") {
                    Toggle("Met long ago", isOn: $contact.isMetLongAgo)
                    Divider()
                    DatePicker("Exact Date", selection: $contact.timestamp, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .disabled(contact.isMetLongAgo)
                }
            }
            .navigationTitle("Change Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }

    private struct TagDateOption: Identifiable, Hashable {
        let id: String
        let date: Date
        let tag: Tag
        let name: String
    }

    private func tagDateOptions() -> [TagDateOption] {
        let calendar = Calendar.current
        // Group by day, then create one option per unique tag on that day
        let groupedByDay = Dictionary(grouping: activeContacts) { c in
            calendar.startOfDay(for: c.timestamp)
        }

        var options: [TagDateOption] = []
        for (day, contacts) in groupedByDay {
            // Unique tags for that day
            var seen = Set<String>()
            let tags = contacts
                .flatMap { ($0.tags ?? []) }
                .filter { !$0.name.isEmpty }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            for tag in tags {
                let key = tag.normalizedKey
                if !seen.contains(key) {
                    seen.insert(key)
                    options.append(
                        TagDateOption(
                            id: "\(key)-\(day.timeIntervalSince1970)",
                            date: day,
                            tag: tag,
                            name: tag.name
                        )
                    )
                }
            }
        }

        // Newest first
        return options.sorted { $0.date > $1.date }
    }
}