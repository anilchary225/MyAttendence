import SwiftUI
import Charts

struct ReportsView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @Environment(\.colorScheme) private var scheme

    @State private var month = DateFormatting.startOfMonth(Date())
    @State private var year = DateFormatting.yearNumber(Date())
    @State private var rangeStart = DateFormatting.startOfMonth(Date())
    @State private var rangeEnd = Date()
    @State private var shareItem: ShareItem?
    @State private var errorMessage: String?

    private var rules: AttendanceRules { AttendanceRules(settings: settings) }
    private var entries: [AttendanceEntry] { store.entries() }

    var body: some View {
        let all = entries
        let monthSummary = AttendanceCalculator.summary(
            entries: all, from: DateFormatting.startOfMonth(month),
            to: DateFormatting.endOfMonth(month), rules: rules)
        let overall = AttendanceCalculator.summary(
            entries: all, from: store.records.last?.date ?? Date(), to: Date(), rules: rules)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SalaryOverviewCard()
                    if store.records.isEmpty {
                        Card {
                            EmptyStateView(systemImage: "chart.bar",
                                           title: "No data to report yet",
                                           message: "Reports are built from your saved attendance. Mark a few days and they'll appear here.")
                        }
                    } else {
                        monthSection(all: all, summary: monthSummary)
                        trendSection(all: all)
                        overallSection(overall: overall)
                        absenceSection(all: all)
                        rangeSection(all: all)
                        yearSection(all: all)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
            .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    // MARK: - Month

    private func monthSection(all: [AttendanceEntry], summary: AttendanceSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { month = DateFormatting.addingMonths(-1, to: month) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }.accessibilityLabel("Previous month")
                    Spacer()
                    Text(DateFormatting.monthYear(month)).font(.headline)
                    Spacer()
                    Button { month = DateFormatting.addingMonths(1, to: month) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }.accessibilityLabel("Next month")
                }
                SummaryTilesView(summary: summary)

                if summary.recorded == 0 {
                    Text("No present or absent days recorded in this month.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Chart(statusBars(summary), id: \.label) { bar in
                        BarMark(x: .value("Status", bar.label), y: .value("Days", bar.count))
                            .foregroundStyle(by: .value("Status", bar.label))
                            .annotation(position: .top) { Text("\(bar.count)").font(.caption2) }
                    }
                    .chartForegroundStyleScale([
                        "Present": StatusPalette.color(for: .present, scheme: scheme),
                        "Absent": StatusPalette.color(for: .absent, scheme: scheme),
                        "Unmarked": Color.secondary
                    ])
                    .chartLegend(.hidden)
                    .frame(height: 160)
                    .accessibilityLabel("Bar chart: \(summary.present) present, \(summary.absent) absent, \(summary.unmarked) unmarked")
                }

                Button { exportPDF(from: DateFormatting.startOfMonth(month), to: DateFormatting.endOfMonth(month)) } label: {
                    Label("Export month as PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private struct Bar { let label: String; let count: Int }
    private func statusBars(_ s: AttendanceSummary) -> [Bar] {
        [Bar(label: "Present", count: s.present), Bar(label: "Absent", count: s.absent), Bar(label: "Unmarked", count: s.unmarked)]
    }

    // MARK: - Trend

    private func trendSection(all: [AttendanceEntry]) -> some View {
        let points = ReportService.monthPoints(entries: all, endingAt: Date(), count: 6, rules: rules)
            .filter { $0.summary.percentage != nil }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent months").font(.headline)
                if points.isEmpty {
                    Text("Not enough recorded days to show a trend.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Chart(points) { p in
                        LineMark(x: .value("Month", p.month, unit: .month),
                                 y: .value("Attendance %", p.summary.percentage ?? 0))
                        PointMark(x: .value("Month", p.month, unit: .month),
                                  y: .value("Attendance %", p.summary.percentage ?? 0))
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 160)
                    .accessibilityLabel("Attendance percentage trend over recent months")
                }
            }
        }
    }

    // MARK: - Overall

    private func overallSection(overall: AttendanceSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("All time").font(.headline)
                LabeledContent("Recorded working days", value: "\(overall.recorded)")
                LabeledContent("Attendance", value: overall.percentageText)
                Text("Percentage = present ÷ (present + absent). Weekends, non-working days, future dates and unmarked days are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Absences

    private func absenceSection(all: [AttendanceEntry]) -> some View {
        let list = ReportService.absences(entries: all,
                                          from: DateFormatting.startOfMonth(month),
                                          to: DateFormatting.endOfMonth(month))
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Absences — \(DateFormatting.monthYear(month))").font(.headline)
                if list.isEmpty {
                    Text("No absences this month.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(list, id: \.date) { RecordRow(entry: $0) ; Divider() }
                }
                NavigationLink("All absences") { AllAbsencesView() }
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Date range

    private func rangeSection(all: [AttendanceEntry]) -> some View {
        let s = AttendanceCalculator.summary(entries: all, from: rangeStart, to: rangeEnd, rules: rules)
        let range = ExportRange(start: rangeStart, end: rangeEnd)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Date range").font(.headline)
                DatePicker("From", selection: $rangeStart, in: ...rangeEnd, displayedComponents: .date)
                DatePicker("To", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                SummaryTilesView(summary: s)
                HStack {
                    Button { exportPDF(from: rangeStart, to: rangeEnd) } label: { Label("PDF", systemImage: "doc.richtext") }
                    Button { exportCSV(range) } label: { Label("CSV", systemImage: "tablecells") }
                    Button { exportJSON(range) } label: { Label("JSON", systemImage: "curlybraces") }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Year

    private func yearSection(all: [AttendanceEntry]) -> some View {
        let years = Array(Set(store.records.map { DateFormatting.yearNumber($0.date) } + [DateFormatting.yearNumber(Date())])).sorted(by: >)
        let summary = ReportService.yearSummary(entries: all, year: year, rules: rules)
        struct Row: Identifiable { let id = UUID(); let month: Date; let status: String; let count: Int }
        let rows = summary.months.flatMap { p in
            [Row(month: p.month, status: "Present", count: p.summary.present),
             Row(month: p.month, status: "Absent", count: p.summary.absent)]
        }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Yearly summary").font(.headline)
                    Spacer()
                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                }
                SummaryTilesView(summary: summary.total)
                if summary.total.recorded > 0 {
                    Chart(rows) { r in
                        BarMark(x: .value("Month", r.month, unit: .month), y: .value("Days", r.count))
                            .foregroundStyle(by: .value("Status", r.status))
                            .position(by: .value("Status", r.status))
                    }
                    .chartForegroundStyleScale([
                        "Present": StatusPalette.color(for: .present, scheme: scheme),
                        "Absent": StatusPalette.color(for: .absent, scheme: scheme)
                    ])
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
                    .frame(height: 180)
                    .accessibilityLabel("Monthly present and absent days for \(year)")
                }
            }
        }
    }

    // MARK: - Export actions

    private func exportPDF(from start: Date, to end: Date) {
        do {
            let url = try ReportService.makePDF(entries: entries, from: start, to: end, rules: rules)
            shareItem = ShareItem(url: url)
        } catch { errorMessage = error.localizedDescription }
    }

    private func exportCSV(_ range: ExportRange) {
        do { shareItem = ShareItem(url: try ExportService.exportCSV(entries: entries, range: range)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func exportJSON(_ range: ExportRange) {
        do { shareItem = ShareItem(url: try ExportService.exportJSON(entries: entries, range: range)) }
        catch { errorMessage = error.localizedDescription }
    }
}

/// Complete absence history with reasons, newest first.
struct AllAbsencesView: View {
    @EnvironmentObject private var store: AttendanceStore

    var body: some View {
        let list = store.records.filter { $0.status == .absent }.map(AttendanceEntry.init)
        List {
            if list.isEmpty {
                EmptyStateView(systemImage: "checkmark.seal", title: "No absences",
                               message: "Absent days and their reasons will be listed here.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(list, id: \.date) { RecordRow(entry: $0) }
            }
        }
        .navigationTitle("All Absences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
