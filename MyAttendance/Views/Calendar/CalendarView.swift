import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @EnvironmentObject private var router: AppRouter

    @State private var month = DateFormatting.startOfMonth(Date())
    @State private var layoutOverride: CalendarLayout?
    @State private var showSummary = true
    @Environment(\.colorScheme) private var scheme

    private var layout: CalendarLayout { layoutOverride ?? settings.defaultCalendarLayout }
    private var isCurrentMonth: Bool { DateFormatting.startOfMonth(Date()) == month }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader

                    Card {
                        if layout == .grid {
                            MonthGridView(month: month) { router.openEditor(for: $0) }
                        } else {
                            dayList
                        }
                    }
                    .gesture(swipe)

                    legend

                    Card {
                        DisclosureGroup(isExpanded: $showSummary) {
                            SummaryTilesView(summary: store.monthSummary(month, settings: settings))
                                .padding(.top, 8)
                        } label: {
                            Text("Month summary").font(.headline)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Layout", selection: Binding(get: { layout }, set: { layoutOverride = $0 })) {
                            ForEach(CalendarLayout.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Image(systemName: layout == .grid ? "calendar" : "list.bullet")
                    }
                    .accessibilityLabel("Calendar layout")
                }
            }
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Previous month")
            Spacer()
            VStack(spacing: 2) {
                Text(DateFormatting.monthYear(month)).font(.title3.weight(.semibold))
                if !isCurrentMonth {
                    Button("Today") {
                        withAnimation { month = DateFormatting.startOfMonth(Date()) }
                    }
                    .font(.subheadline)
                }
            }
            .accessibilityElement(children: .contain)
            Spacer()
            Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Next month")
        }
    }

    private func changeMonth(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            month = DateFormatting.addingMonths(delta, to: month)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            changeMonth(value.translation.width < 0 ? 1 : -1)
        }
    }

    // MARK: - List layout

    private var dayList: some View {
        let now = Date()
        let byDate = Dictionary(store.records.map { ($0.date, AttendanceEntry($0)) },
                                uniquingKeysWith: { first, _ in first })
        let days = DateFormatting.days(from: DateFormatting.startOfMonth(month),
                                       to: DateFormatting.endOfMonth(month))
        return VStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let entry = byDate[day]
                Button { router.openEditor(for: day) } label: {
                    HStack {
                        Text("\(DateFormatting.dayNumber(day)) \(DateFormatting.weekdayName(day))")
                            .font(.subheadline)
                            .foregroundStyle(settings.isWorkingDay(day) || entry != nil ? .primary : .secondary)
                        if DateFormatting.isSameDay(day, now) {
                            Text("Today").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        if store.isPaidHoliday(on: day) {
                            Label("Holiday", systemImage: "sun.max.fill").font(.caption).foregroundStyle(.orange)
                        }
                        if let entry {
                            AttendanceStatusBadge(status: entry.status, compact: true)
                        } else if DateFormatting.isFuture(day, now: now) {
                            Text("Upcoming").font(.caption).foregroundStyle(.secondary)
                        } else if !settings.isWorkingDay(day) {
                            Text("Non-working").font(.caption).foregroundStyle(.secondary)
                        } else {
                            AttendanceStatusBadge(status: nil, compact: true)
                        }
                    }
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if day != days.last { Divider() }
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        ViewThatFits {
            HStack(spacing: 16) { legendItems }
            VStack(alignment: .leading, spacing: 6) { legendItems }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: green check is present, red cross is absent, sun is a paid holiday, dashed circle is not marked, faded days are weekends or future dates")
    }

    @ViewBuilder
    private var legendItems: some View {
        Label("Present", systemImage: "checkmark.circle.fill")
            .foregroundStyle(StatusPalette.color(for: .present, scheme: scheme))
        Label("Absent", systemImage: "xmark.circle.fill")
            .foregroundStyle(StatusPalette.color(for: .absent, scheme: scheme))
        Label("Paid holiday", systemImage: "sun.max.fill").foregroundStyle(.orange)
        Label("Not marked", systemImage: "circle.dashed")
        Label("Weekend / future", systemImage: "circle.lefthalf.filled")
    }
}
