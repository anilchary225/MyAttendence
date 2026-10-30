import SwiftUI
import Charts

struct SalaryTrackerView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @State private var month = DateFormatting.startOfMonth(Date())
    @State private var loaded = false
    @State private var share: ShareItem?
    @State private var error: String?
    @State private var confirmSnapshot = false

    private var activeMonth: Date {
        SalaryCalculator.activeMonth(configuration: store.salaryConfiguration(settings: settings) ?? SalaryConfiguration())
    }
    private var report: SalaryReport? { try? store.salaryReport(month: month, settings: settings) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthSelector
                if let report {
                    summaryCards(report.summary)
                    breakdown(report)
                    insights(report.summary)
                    charts(report.summary)
                    trend
                    historyAndExports(report)
                } else {
                    Card {
                        VStack(spacing: 12) {
                            Label("Set up Salary Tracker", systemImage: "indianrupeesign.circle").font(.headline)
                            Text(store.salaryLoadError ?? "Enter your monthly salary and calculation rules to see earnings. Invalid or incomplete settings never produce salary estimates.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            NavigationLink("Salary Settings") { SalarySettingsView() }
                        }
                    }
                }
            }.padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Salary Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SalarySettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Salary settings")
            }
        }
        .onAppear {
            if !loaded { month = activeMonth; loaded = true }
            do { try store.synchronizeSalary(settings: settings) } catch { self.error = error.localizedDescription }
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .alert("Salary Tracker", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .confirmationDialog("Save these salary rules for this historical month?", isPresented: $confirmSnapshot, titleVisibility: .visible) {
            Button("Save Monthly Snapshot") {
                perform { try store.saveHistoricalSalary(month: month, settings: settings) }
            }
        } message: {
            Text("This month currently uses today's salary settings. Saving freezes those rules for this month. Later attendance edits still recalculate its totals.")
        }
    }

    private var monthSelector: some View {
        HStack {
            Button { month = DateFormatting.addingMonths(-1, to: month) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel("Previous salary month")
            Spacer()
            VStack {
                Text(DateFormatting.monthYear(month)).font(.headline)
                if month != activeMonth { Button("Current period") { month = activeMonth }.font(.caption) }
            }
            Spacer()
            Button { month = DateFormatting.addingMonths(1, to: month) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }.disabled(month >= activeMonth).accessibilityLabel("Next salary month")
        }
    }

    private func summaryCards(_ s: SalarySummary) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CONFIRMED GROSS EARNINGS").font(.caption.weight(.semibold))
                Text(Money.text(s.gross)).font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                Text("\(s.paidDays) payable days · \(s.periodStart) – \(s.periodEnd)").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                metric("Monthly salary target", Money.text(s.monthlySalary), color: .primary)
                metric("Per-day salary", Money.text(s.dailyRate), color: .primary)
                metric("Salary lost", Money.text(s.lost), color: .red)
                metric("Paid days", "\(s.paidDays)", color: .green)
                metric("Unpaid absent days", "\(s.unpaidAbsences)", color: .red)
                metric("Attendance", s.attendancePercentage.map { String(format: "%.1f%%", $0) } ?? "Unavailable", color: .primary)
                metric("Estimated net salary", Money.text(s.net), color: .green)
                if s.projectedNet != nil { metric("Projected period-end net", Money.text(s.projectedNet), color: .teal) }
            }
        }
    }

    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func breakdown(_ report: SalaryReport) -> some View {
        let s = report.summary
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Salary breakdown").font(.headline)
                LabeledContent("Confirmed gross", value: Money.text(s.gross))
                LabeledContent("Absence deductions · \(s.unpaidAbsences) days", value: Money.text(s.lost)).foregroundStyle(.red)
                Text("Absence deductions are already excluded from gross earnings.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Other deductions", value: Money.text(s.deductions))
                LabeledContent("Bonuses / extra earnings", value: Money.text(s.bonuses))
                Divider()
                LabeledContent("Estimated net", value: Money.text(s.net)).fontWeight(.semibold)
                if let projected = s.projectedGross {
                    LabeledContent("Projected period-end gross", value: Money.text(projected))
                    LabeledContent("Projected absence deductions", value: Money.text(s.lost))
                    Text("Projection assumes all \(s.future) future scheduled days are attended. Past unmarked days earn no attendance pay; configured paid holidays remain payable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Net = gross − other deductions + bonuses. Full period adjustments apply once. Net is capped at ₹0 when deductions exceed earnings. Estimates do not confirm salary received.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(report.configuration.method.explanation).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func insights(_ s: SalarySummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Attendance & insights").font(.headline)
                LabeledContent("Scheduled days · full period", value: "\(s.scheduled)")
                LabeledContent("Scheduled days · to date", value: "\(s.scheduledToDate)")
                LabeledContent("Present", value: "\(s.present)")
                LabeledContent("Paid absences / holidays", value: "\(s.paidAbsences) / \(s.holidays)")
                LabeledContent("Unmarked working days · to date", value: "\(s.unmarked)")
                LabeledContent("Future working days", value: "\(s.future)")
                if s.gross != nil {
                    Text("You earned \(Money.text(s.gross)) in this period.")
                    Text("\(Money.text(s.lost)) was deducted for \(s.unpaidAbsences) unpaid absence days.")
                    Text("You have \(s.unmarked) unmarked working days.")
                } else {
                    Text("Salary is unavailable: no eligible scheduled working days to date. No division by zero or earnings are inferred.")
                }
                Text("Attendance = present ÷ recorded working days. Holidays without attendance stay unmarked, but qualify for holiday pay.")
                    .font(.caption).foregroundStyle(.secondary)
                if let gross = s.gross, s.monthlySalary > 0 {
                    let fraction = Money.number(gross / s.monthlySalary)
                    ProgressView(value: min(max(fraction, 0), 1))
                        .tint(.green).accessibilityLabel("Salary target earned")
                    Text(String(format: "%.1f%% of monthly target earned", fraction * 100)).font(.caption)
                }
            }
        }
    }

    private struct Bar: Identifiable { var label: String; var amount: Double; var id: String { label } }
    private func charts(_ s: SalarySummary) -> some View {
        VStack(spacing: 16) {
            if let gross = s.gross, let lost = s.lost {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Earned vs lost · INR").font(.headline)
                        Chart([Bar(label: "Earned", amount: Money.number(gross)), Bar(label: "Lost", amount: Money.number(lost))]) { bar in
                            BarMark(x: .value("Amount INR", bar.amount), y: .value("Category", bar.label))
                                .foregroundStyle(bar.label == "Earned" ? Color.green : Color.red)
                        }.frame(height: 110)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Working days to date").font(.headline)
                    Chart([Bar(label: "Present", amount: Double(s.present)),
                           Bar(label: "Absent", amount: Double(s.paidAbsences + s.unpaidAbsences)),
                           Bar(label: "Unmarked", amount: Double(s.unmarked))]) { bar in
                        BarMark(x: .value("Status", bar.label), y: .value("Days", bar.amount))
                            .foregroundStyle(bar.label == "Present" ? Color.green : bar.label == "Absent" ? .orange : .gray)
                    }.frame(height: 160)
                }
            }
            let marked = s.days.filter { $0.state != "Unmarked" }
            if !marked.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily salary impact · INR").font(.headline)
                        Chart(marked) { day in
                            BarMark(x: .value("Day", DateFormatting.parseIsoDay(day.date)!, unit: .day),
                                    y: .value("Impact INR", Money.number(day.impact)))
                                .foregroundStyle(day.state == "Unpaid absence" ? Color.red : Color.green)
                        }.frame(height: 180)
                        Text("Green: present, paid absence or configured holiday. Red: unpaid absence. Other unmarked days and future days have no confirmed impact.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var trend: some View {
        let reports = (0..<6).reversed().compactMap { offset -> SalaryReport? in
            guard let r = try? store.salaryReport(month: DateFormatting.addingMonths(-offset, to: month), settings: settings),
                  r.summary.gross != nil, r.summary.paidDays + r.summary.unpaidAbsences > 0 else { return nil }
            return r
        }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent earnings · INR").font(.headline)
                if reports.isEmpty {
                    Text("Record attendance or configure paid holidays to see earnings history.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Chart(reports) { r in
                        BarMark(x: .value("Month", DateFormatting.parseIsoDay(r.id)!, unit: .month),
                                y: .value("Gross INR", Money.number(r.summary.gross!)))
                            .foregroundStyle(r.hasSnapshot ? Color.green : Color.gray)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 180)
                    Text("Green uses saved period rules. Gray uses current settings because historical rules were not saved. No missing months are filled with invented earnings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func historyAndExports(_ report: SalaryReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("History & export").font(.headline)
                Text(report.basis).font(.subheadline).foregroundStyle(report.hasSnapshot ? Color.secondary : Color.orange)
                Text("Saved settings remain fixed for closed periods. Editing or deleting attendance recalculates their financial totals using the saved rules. The open period follows current settings.")
                    .font(.caption).foregroundStyle(.secondary)
                if !report.hasSnapshot {
                    Button("Save Monthly Snapshot") { confirmSnapshot = true }
                }
                Button { perform { share = ShareItem(url: try ExportService.exportSalaryCSV(reports: [report])) } } label: {
                    Label("Export salary summary (CSV)", systemImage: "tablecells")
                }
                Button { perform { share = ShareItem(url: try ReportService.makeSalaryPDF(report: report)) } } label: {
                    Label("Export salary statement (PDF)", systemImage: "doc.richtext")
                }
                Button { perform {
                    let reports = try store.salary.snapshots.compactMap { snapshot in
                        try store.salaryReport(month: DateFormatting.parseIsoDay(snapshot.month)!, settings: settings)
                    }
                    share = ShareItem(url: try ExportService.exportSalaryCSV(reports: reports))
                } } label: { Label("Export all saved salary months (CSV)", systemImage: "clock.arrow.circlepath") }
                .disabled(store.salary.snapshots.isEmpty)
            }
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = error.localizedDescription }
    }
}

/// Shared entry point uses the same service and snapshot rules as Salary Tracker.
struct SalaryOverviewCard: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    var body: some View {
        let config = store.salaryConfiguration(settings: settings)
        let month = SalaryCalculator.activeMonth(configuration: config ?? SalaryConfiguration())
        let summary = try? store.salaryResult(month: month, settings: settings)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { SalaryTrackerView() } label: {
                    Label("Salary Tracker", systemImage: "indianrupeesign.circle.fill").font(.headline)
                }
                if let summary {
                    LabeledContent("Confirmed gross", value: Money.text(summary.gross))
                    LabeledContent("Salary lost", value: Money.text(summary.lost))
                    LabeledContent("Estimated net", value: Money.text(summary.net))
                    Text("\(summary.periodStart) – \(summary.periodEnd) · Estimates from attendance")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(store.salaryLoadError ?? "Set your monthly salary to track earnings and absence deductions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
