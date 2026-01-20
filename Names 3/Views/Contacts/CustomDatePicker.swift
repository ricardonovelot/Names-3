import SwiftUI
import SwiftData

struct CustomDatePicker: View {
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Contact> { $0.isArchived == false && $0.isMetLongAgo == false })
    private var activeContacts: [Contact]

    @State private var showAllTagOptions = false
    @State private var selectedQuickOption: QuickDateOption.ID?
    @State private var customDate: Date
    
    init(contact: Contact) {
        self.contact = contact
        _customDate = State(initialValue: contact.timestamp)
    }

    var body: some View {
        NavigationStack {
            List {
                quickSelectSection
                
                tagBasedSection
                
                customDateSection
            }
            .navigationTitle("Change Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyCustomDate()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
    
    // MARK: - Quick Select Section
    
    private var quickSelectSection: some View {
        Section {
            ForEach(QuickDateOption.allOptions) { option in
                quickSelectRow(for: option)
            }
        } header: {
            Text("Quick Select")
        }
    }
    
    private func quickSelectRow(for option: QuickDateOption) -> some View {
        Button {
            selectedQuickOption = option.id
            applyQuickOption(option)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.iconName)
                    .font(.body)
                    .foregroundStyle(option.isLongAgo ? .secondary : .primary)
                    .frame(width: 24, alignment: .center)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .foregroundStyle(.primary)
                    
                    if !option.isLongAgo {
                        Text(dayOfWeek(for: option.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if selectedQuickOption == option.id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Tag-Based Section
    
    private var tagBasedSection: some View {
        Section {
            let options = tagDateOptions()
            let limited = showAllTagOptions ? options : Array(options.prefix(3))

            if options.isEmpty {
                HStack {
                    Image(systemName: "tag.slash")
                        .foregroundStyle(.tertiary)
                    Text("No recent places or groups")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(limited) { opt in
                    tagDateRow(for: opt)
                }

                if !showAllTagOptions && options.count > 3 {
                    Button {
                        withAnimation {
                            showAllTagOptions = true
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Show All \(options.count)")
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            Text("Recent Places & Groups")
        } footer: {
            if !tagDateOptions().isEmpty {
                Text("Select from your existing places and group events")
                    .font(.footnote)
            }
        }
    }
    
    private func tagDateRow(for option: TagDateOption) -> some View {
        Button {
            applyTagOption(option)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 24, alignment: .center)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(formatDate(option.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if !Calendar.current.isDate(option.date, inSameDayAs: Date()) {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            
                            Text(relativeDate(option.date))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Custom Date Section
    
    private var customDateSection: some View {
        Section {
            DatePicker(
                "Select Date",
                selection: $customDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .onChange(of: customDate) { oldValue, newValue in
                selectedQuickOption = nil
            }
        } header: {
            Text("Custom Date")
        } footer: {
            Text("Choose any specific date up to today")
                .font(.footnote)
        }
    }
    
    // MARK: - Actions
    
    private func applyQuickOption(_ option: QuickDateOption) {
        contact.isMetLongAgo = option.isLongAgo
        
        if !option.isLongAgo {
            contact.timestamp = option.date
            customDate = option.date
        } else {
            contact.timestamp = .distantPast
        }
        
        saveContact()
    }
    
    private func applyTagOption(_ option: TagDateOption) {
        contact.isMetLongAgo = false
        contact.timestamp = option.date
        contact.tags = [option.tag]
        customDate = option.date
        selectedQuickOption = nil
        
        saveContact()
        dismiss()
    }
    
    private func applyCustomDate() {
        contact.isMetLongAgo = false
        contact.timestamp = customDate
        saveContact()
    }
    
    private func saveContact() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving contact: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    private func dayOfWeek(for date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        let components = calendar.dateComponents([.year, .month, .day], from: date, to: now)
        
        if let year = components.year, year > 0 {
            return year == 1 ? "1 year ago" : "\(year) years ago"
        } else if let month = components.month, month > 0 {
            return month == 1 ? "1 month ago" : "\(month) months ago"
        } else if let day = components.day, day > 0 {
            return day == 1 ? "1 day ago" : "\(day) days ago"
        }
        
        return "Today"
    }
    
    private func tagDateOptions() -> [TagDateOption] {
        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: activeContacts) { c in
            calendar.startOfDay(for: c.timestamp)
        }

        var options: [TagDateOption] = []
        for (day, contacts) in groupedByDay {
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

        return options.sorted { $0.date > $1.date }
    }
}

// MARK: - Models

private struct QuickDateOption: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let date: Date
    let isLongAgo: Bool
    
    static let allOptions: [QuickDateOption] = {
        let calendar = Calendar.current
        let now = Date()
        
        func dateBySubtracting(days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        }
        
        return [
            QuickDateOption(
                id: "today",
                title: "Today",
                iconName: "calendar.circle.fill",
                date: calendar.startOfDay(for: now),
                isLongAgo: false
            ),
            QuickDateOption(
                id: "yesterday",
                title: "Yesterday",
                iconName: "calendar.badge.clock",
                date: dateBySubtracting(days: 1),
                isLongAgo: false
            ),
            QuickDateOption(
                id: "longago",
                title: "Long Ago",
                iconName: "clock.arrow.circlepath",
                date: .distantPast,
                isLongAgo: true
            )
        ]
    }()
}

private struct TagDateOption: Identifiable, Hashable {
    let id: String
    let date: Date
    let tag: Tag
    let name: String
}