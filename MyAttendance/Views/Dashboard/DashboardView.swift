import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        let today = DateFormatting.normalize(Date())
        let todayRecord = store.record(on: today)
        let summary = store.monthSummary(today, settings: settings)
        let recent = store.records.prefix(5).map(AttendanceEntry.init)
        let absences = store.records.filter { $0.status == .absent }.prefix(3).map(AttendanceEntry.init)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    todayCard(today: today, record: todayRecord)
                    SalaryOverviewCard()

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(DateFormatting.monthYear(today)).font(.headline)
                            SummaryTilesView(summary: summary)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("This month").font(.headline)
                                Spacer()
                                Button("Open Calendar") {
                                    router.selectedTab = .calendar
                                }
                                .font(.subheadline)
                            }
                            MonthGridView(month: today, compact: true) { date in
                                router.openEditor(for: date)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent entries").font(.headline)
                            if recent.isEmpty {
                                Text("Nothing recorded yet. Tap Mark Attendance to add your first day.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                ForEach(recent, id: \.date) { entry in
                                    Button { router.openEditor(for: entry.date) } label: { RecordRow(entry: entry, showReason: false) }
                                        .buttonStyle(.plain)
                                    if entry.date != recent.last?.date { Divider() }
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent absences").font(.headline)
                            if absences.isEmpty {
                                Text("No absences recorded.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                ForEach(absences, id: \.date) { entry in
                                    Button { router.openEditor(for: entry.date) } label: { RecordRow(entry: entry) }
                                        .buttonStyle(.plain)
                                    if entry.date != absences.last?.date { Divider() }
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        shortcut("Calendar", "calendar") { router.selectedTab = .calendar }
                        shortcut("Create Backup", "externaldrive.badge.icloud") { router.openBackup() }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
        }
    }

    // MARK: - Pieces

    private func todayCard(today: Date, record: AttendanceRecord?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateFormatting.weekdayName(today)).font(.title2.weight(.bold))
                    Text(DateFormatting.mediumDate(today)).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Today").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    AttendanceStatusBadge(status: record?.status)
                }

                if let block = record == nil ? settings.recordingBlockReason(for: today) : nil {
                    Label(block, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button {
                        router.openEditor(for: today)
                    } label: {
                        Label(record == nil ? "Mark Attendance" : "Edit Today's Attendance",
                              systemImage: record == nil ? "checkmark.circle" : "pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private func shortcut(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}
