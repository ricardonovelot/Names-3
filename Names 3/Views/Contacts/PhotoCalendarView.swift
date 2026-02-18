//
//  PhotoCalendarView.swift
//  Names 3
//
//  Custom calendar that shows a photo thumbnail behind each date number
//  to help the user identify events (e.g. contact photos for that day).
//

import SwiftUI

/// A calendar grid where each day cell can show an optional thumbnail behind the date number.
/// Uses the same layout and selection semantics as the system graphical date picker (month navigation, weekdays, selectable days up to today).
struct PhotoCalendarView: View {
    @Binding var selection: Date
    /// Called with start-of-day date for each visible day; return photo data to show as background, or nil.
    var thumbnailForDay: (Date) -> Data?
    /// Maximum selectable date (e.g. today). Days after this are shown but not selectable.
    var maxSelectableDate: Date = Date()
    /// Called when the displayed month changes (initial appear and after tapping arrows). Use to load library thumbnails for that month.
    var onDisplayedMonthChange: ((Date) -> Void)?

    @State private var displayedMonth: Date

    private let calendar = Calendar.current
    /// Weekday symbols ordered so the first column matches calendar.firstWeekday (e.g. Mon first when week starts Monday).
    private let weekdaySymbols: [String]
    private let gridSpacing: CGFloat = 4
    private let numberOfRows: CGFloat = 6
    private let weekRowSpacing: CGFloat = 6
    private let weekRowPadding: CGFloat = 8

    init(
        selection: Binding<Date>,
        thumbnailForDay: @escaping (Date) -> Data?,
        maxSelectableDate: Date = Date(),
        onDisplayedMonthChange: ((Date) -> Void)? = nil
    ) {
        _selection = selection
        self.thumbnailForDay = thumbnailForDay
        self.maxSelectableDate = maxSelectableDate
        self.onDisplayedMonthChange = onDisplayedMonthChange
        let cal = Calendar.current
        _displayedMonth = State(initialValue: cal.startOfMonth(containing: selection.wrappedValue))
        let raw = cal.shortWeekdaySymbols
        let firstIndex = cal.firstWeekday - 1
        weekdaySymbols = Array(raw[firstIndex...]) + Array(raw[..<firstIndex])
    }

    private let calendarTotalHeight: CGFloat = 580
    private let monthNavHeight: CGFloat = 44
    private let headerHeight: CGFloat = 20
    private let verticalSpacing: CGFloat = 8
    private var gridHeight: CGFloat {
        calendarTotalHeight - monthNavHeight - headerHeight - verticalSpacing * 2
    }

    var body: some View {
        VStack(spacing: verticalSpacing) {
            monthNavigation
            GeometryReader { geo in
                let w = geo.size.width
                let h = gridHeight
                let cellW = (w - gridSpacing * 6) / 7
                let rowH = (h - (numberOfRows - 1) * weekRowSpacing - numberOfRows * weekRowPadding) / numberOfRows
                let cellSize = min(cellW, rowH)
                VStack(spacing: 0) {
                    weekdayHeaders(cellSize: cellSize)
                        .frame(height: headerHeight)
                    dayGridContent(cellSize: cellSize, width: w)
                }
            }
            .frame(height: headerHeight + gridHeight)
        }
        .frame(height: calendarTotalHeight)
        .clipped()
        .onAppear {
            onDisplayedMonthChange?(displayedMonth)
        }
        .onChange(of: displayedMonth) { _, newMonth in
            onDisplayedMonthChange?(newMonth)
        }
    }

    private var monthNavigation: some View {
        HStack(spacing: 0) {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Text(monthYearString(from: displayedMonth))
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: monthNavHeight)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func weekdayHeaders(cellSize: CGFloat) -> some View {
        HStack(spacing: gridSpacing) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: cellSize, alignment: .center)
            }
        }
    }

    private func dayGridContent(cellSize: CGFloat, width: CGFloat) -> some View {
        let weeks = weeksInDisplayedMonth()
        return VStack(spacing: weekRowSpacing) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: gridSpacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, dayInfo in
                        dayCell(dayInfo: dayInfo, cellSize: cellSize)
                    }
                }
            }
        }
        .frame(height: gridHeight)
    }

    /// One square per day (or empty). Fixed cell size so the grid looks like Apple's calendar.
    private func dayCell(dayInfo: DayCellInfo, cellSize: CGFloat) -> some View {
        Group {
            switch dayInfo {
            case .empty:
                Color.clear
                    .frame(width: cellSize, height: cellSize)
            case .day(let date):
                let dayStart = calendar.startOfDay(for: date)
                let isSelected = calendar.isDate(selection, inSameDayAs: date)
                let isSelectable = !(date > maxSelectableDate)
                let thumbnailData = thumbnailForDay(dayStart)

                Button {
                    if isSelectable {
                        selection = dayStart
                    }
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        thumbnailBackground(data: thumbnailData)
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: min(cellSize * 0.4, 16), weight: isSelected ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(isSelectable ? .primary : .secondary)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0)
                            .padding(6)
                    }
                    .frame(width: cellSize, height: cellSize)
                    .clipped()
                    .overlay {
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                                .padding(2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: cellSize, height: cellSize)
                .clipped()
                .disabled(!isSelectable)
            }
        }
    }

    @ViewBuilder
    private func thumbnailBackground(data: Data?) -> some View {
        if let data = data, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(1.25)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.25))
                )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .quaternarySystemFill))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func daysInDisplayedMonth() -> [DayCellInfo] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let firstWeekdayZeroBased = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [DayCellInfo] = []
        for _ in 0..<firstWeekdayZeroBased {
            result.append(.empty)
        }
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                result.append(.day(date))
            }
        }
        return result
    }

    /// Days grouped by week. Every row has exactly 7 cells (leading/trailing empties) so the grid is a fixed 7×6 layout like Apple's calendar.
    private func weeksInDisplayedMonth() -> [[DayCellInfo]] {
        let days = daysInDisplayedMonth()
        var weeks: [[DayCellInfo]] = []
        var index = 0
        while index < days.count {
            var week: [DayCellInfo] = []
            for _ in 0..<7 {
                if index < days.count {
                    week.append(days[index])
                    index += 1
                } else {
                    week.append(.empty)
                }
            }
            weeks.append(week)
        }
        return weeks
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func moveMonth(by delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = newMonth
    }
}

// MARK: - Day cell model

private enum DayCellInfo: Hashable {
    case empty
    case day(Date)
}

// MARK: - Calendar helpers

private extension Calendar {
    func startOfMonth(containing date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
