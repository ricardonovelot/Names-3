import SwiftUI
import SwiftData
import Photos

struct CustomDatePicker: View {
    @Bindable var contact: Contact
    /// When non-nil (e.g. when changing date for a whole group), the same date/tag changes are applied to these contacts when the user confirms.
    var additionalContactsToApply: [Contact]? = nil
    /// Called before applying date/group changes so the host can push an undo entry. Receives snapshots of all affected contacts’ previous state.
    var onRecordUndo: (([ContactMovementSnapshot]) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Contact> { $0.isArchived == false && $0.isMetLongAgo == false })
    private var activeContacts: [Contact]

    @State private var showAllTagOptions = false
    @State private var selectedQuickOption: QuickDateOption.ID?
    @State private var customDate: Date
    @State private var libraryThumbnailsForCalendar: [Date: Data] = [:]
    @State private var libraryThumbnailsCache: [Date: [Date: Data]] = [:]
    @State private var displayedMonthForThumbnails: Date?
    @State private var calendarLibraryLoadTask: Task<Void, Never>?

    init(contact: Contact, additionalContactsToApply: [Contact]? = nil, onRecordUndo: (([ContactMovementSnapshot]) -> Void)? = nil) {
        self.contact = contact
        self.additionalContactsToApply = additionalContactsToApply
        self.onRecordUndo = onRecordUndo
        _customDate = State(initialValue: contact.timestamp)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    customDateSectionContent
                    quickSelectSectionContent
                    tagBasedSectionContent
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
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
                        // Only apply custom date if no quick option was selected and "Long Ago" is not set
                        // This preserves the "Long Ago" selection even if user interacted with date picker
                        if selectedQuickOption == nil && !contact.isMetLongAgo {
                            applyCustomDate()
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
    
    // MARK: - Quick Select Section

    private var quickSelectSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Select")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(QuickDateOption.allOptions) { option in
                    quickSelectRow(for: option)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    if option.id != QuickDateOption.allOptions.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
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

    private var tagBasedSectionContent: some View {
        let options = tagDateOptions()
        let limited = showAllTagOptions ? options : Array(options.prefix(3))
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent Places & Groups")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            VStack(spacing: 0) {
                if options.isEmpty {
                    HStack {
                        Image(systemName: "tag.slash")
                            .foregroundStyle(.tertiary)
                        Text("No recent places or groups")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                } else {
                    ForEach(Array(limited.enumerated()), id: \.element.id) { index, opt in
                        tagDateRow(for: opt)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        if index < limited.count - 1 || (!showAllTagOptions && options.count > 3) {
                            Divider()
                                .padding(.leading, 56)
                        }
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
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if !options.isEmpty {
                Text("Select from your existing places and group events")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.horizontal, 20)
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
    
    /// Calendar placed outside List to avoid UICollectionView self-sizing feedback loop (section 2-0).
    private var customDateSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Date")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            PhotoCalendarView(
                selection: $customDate,
                thumbnailForDay: { dayStart in
                    thumbnailForDay(dayStart)
                },
                maxSelectableDate: Date(),
                onDisplayedMonthChange: { monthStart in
                    loadLibraryThumbnailsForMonth(monthStart)
                }
            )
            .onChange(of: customDate) { oldValue, newValue in
                selectedQuickOption = nil
            }
            .padding(.horizontal, 20)
            Text("Choose any specific date up to today. Days show a photo from your library or someone you met that day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    /// Prefer library thumbnail for the day; fall back to contact photo if no library photo for that day.
    private func thumbnailForDay(_ dayStart: Date) -> Data? {
        if let library = libraryThumbnailsForCalendar[dayStart], !library.isEmpty {
            return library
        }
        return contactPhotoForDay(dayStart)
    }

    /// Returns contact photo data for the given day (start-of-day date) if any contact has that timestamp.
    private func contactPhotoForDay(_ dayStart: Date) -> Data? {
        let calendar = Calendar.current
        let contactsToConsider = activeContacts + (activeContacts.contains(where: { $0.id == contact.id }) ? [] : [contact])
        return contactsToConsider
            .first(where: { calendar.isDate($0.timestamp, inSameDayAs: dayStart) && !$0.photo.isEmpty })
            .map { $0.photo }
    }

    private func loadLibraryThumbnailsForMonth(_ monthStart: Date) {
        let calendar = Calendar.current
        let monthKey = calendar.startOfDay(for: calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart)) ?? monthStart)
        displayedMonthForThumbnails = monthKey
        if let cached = libraryThumbnailsCache[monthKey] {
            libraryThumbnailsForCalendar = cached
            return
        }
        calendarLibraryLoadTask?.cancel()
        calendarLibraryLoadTask = Task {
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized ||
                  PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { return }
            let result = await PhotoLibraryService.shared.loadThumbnailsForCalendarMonth(monthStart: monthStart)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                libraryThumbnailsCache[monthKey] = result.thumbnails
                if displayedMonthForThumbnails == monthKey {
                    libraryThumbnailsForCalendar = result.thumbnails
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func movementSnapshot(for c: Contact) -> ContactMovementSnapshot {
        ContactMovementSnapshot(
            uuid: c.uuid,
            isMetLongAgo: c.isMetLongAgo,
            timestamp: c.timestamp,
            tagNames: (c.tags ?? []).compactMap { $0.name }
        )
    }
    
    private func affectedContacts() -> [Contact] {
        [contact] + (additionalContactsToApply ?? [])
    }
    
    private func applyQuickOption(_ option: QuickDateOption) {
        let snapshots = affectedContacts().map { movementSnapshot(for: $0) }
        onRecordUndo?(snapshots)
        
        contact.isMetLongAgo = option.isLongAgo
        
        if !option.isLongAgo {
            contact.timestamp = option.date
            customDate = option.date
        } else {
            contact.timestamp = .distantPast
        }
        
        applyToAdditionalContacts(copyTags: false)
        saveContact()
    }
    
    private func applyTagOption(_ option: TagDateOption) {
        let snapshots = affectedContacts().map { movementSnapshot(for: $0) }
        onRecordUndo?(snapshots)
        
        contact.isMetLongAgo = false
        contact.timestamp = option.date
        contact.tags = [option.tag]
        customDate = option.date
        selectedQuickOption = nil
        
        applyToAdditionalContacts(copyTags: true)
        saveContact()
        dismiss()
    }
    
    private func applyCustomDate() {
        let snapshots = affectedContacts().map { movementSnapshot(for: $0) }
        onRecordUndo?(snapshots)
        
        contact.isMetLongAgo = false
        contact.timestamp = customDate
        applyToAdditionalContacts(copyTags: false)
        saveContact()
    }
    
    private func applyToAdditionalContacts(copyTags: Bool) {
        guard let others = additionalContactsToApply, !others.isEmpty else { return }
        for c in others {
            c.isMetLongAgo = contact.isMetLongAgo
            c.timestamp = contact.timestamp
            if copyTags {
                c.tags = contact.tags
            }
        }
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