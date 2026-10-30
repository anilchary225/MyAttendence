import SwiftUI

/// Monday-first month grid shared by the Calendar tab and the Dashboard preview.
struct MonthGridView: View {
    let month: Date
    var compact = false
    var onSelect: ((Date) -> Void)? = nil

    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let statusByDate = Dictionary(store.records.map { ($0.date, $0.status) },
                                      uniquingKeysWith: { first, _ in first })
        let now = Date()

        VStack(spacing: compact ? 2 : 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(DateFormatting.weekdaySymbolsMondayFirst().enumerated()), id: \.offset) { _, symbol in
                    Text(compact ? String(symbol.prefix(1)) : symbol)
                        .font(compact ? .system(size: 9, weight: .semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(DateFormatting.monthGrid(for: month).enumerated()), id: \.offset) { _, day in
                    if let day {
                        let cell = AttendanceDayCell(
                            date: day,
                            status: statusByDate[day],
                            isNonWorking: !settings.isWorkingDay(day),
                            isFuture: DateFormatting.isFuture(day, now: now),
                            isToday: DateFormatting.isSameDay(day, now),
                            compact: compact,
                            isPaidHoliday: store.isPaidHoliday(on: day))
                        if let onSelect {
                            Button { onSelect(day) } label: { cell }.buttonStyle(.plain)
                        } else {
                            cell
                        }
                    } else {
                        Color.clear.aspectRatio(compact ? 1 : 0.92, contentMode: .fit)
                    }
                }
            }
        }
    }
}
