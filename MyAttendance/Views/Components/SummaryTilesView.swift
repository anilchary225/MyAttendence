import SwiftUI

/// Working days / present / absent / unmarked tiles plus the percentage line.
struct SummaryTilesView: View {
    let summary: AttendanceSummary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.percentageText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(summary.percentage == nil
                                        ? "Attendance not available"
                                        : "Attendance \(summary.percentageText)")
                Text("attendance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if summary.percentage == nil {
                Text("No working days recorded yet. Mark a day to see your percentage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                tile("Working days", summary.workingDays, .primary)
                tile("Present", summary.present, StatusPalette.color(for: .present, scheme: scheme))
                tile("Absent", summary.absent, StatusPalette.color(for: .absent, scheme: scheme))
                tile("Unmarked", summary.unmarked, .secondary)
            }
        }
    }

    private func tile(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// A single attendance row used by Dashboard and History.
struct RecordRow: View {
    let entry: AttendanceEntry
    var showReason = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(DateFormatting.dayNumber(entry.date)).font(.title3.weight(.semibold).monospacedDigit())
                Text(DateFormatting.shortMonth(entry.date)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(DateFormatting.weekdayName(entry.date)).font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    AttendanceStatusBadge(status: entry.status, compact: true)
                }
                if showReason, entry.status == .absent, !entry.absenceReason.isEmpty {
                    Text(entry.absenceReason).font(.footnote).foregroundStyle(.secondary)
                }
                if showReason, !entry.notes.isEmpty {
                    Text(entry.notes).font(.footnote).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
