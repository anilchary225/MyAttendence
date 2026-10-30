import Foundation
import UIKit

/// Everything the calculator needs to decide what counts as a working day.
struct AttendanceRules {
    var workingWeekdays: Set<Int>
    var trackingStart: Date?
    var now: Date

    init(workingWeekdays: Set<Int> = AttendanceSettings.defaultWorkingWeekdays,
         trackingStart: Date? = nil,
         now: Date = Date()) {
        self.workingWeekdays = workingWeekdays
        self.trackingStart = trackingStart
        self.now = now
    }

    init(settings: AttendanceSettings, now: Date = Date()) {
        self.init(workingWeekdays: settings.workingWeekdays,
                  trackingStart: settings.trackingStartDate,
                  now: now)
    }

    func isCountedDay(_ date: Date) -> Bool {
        guard workingWeekdays.contains(DateFormatting.weekday(of: date)) else { return false }
        guard !DateFormatting.isFuture(date, now: now) else { return false }
        if let start = trackingStart, DateFormatting.normalize(date) < DateFormatting.normalize(start) { return false }
        return true
    }
}

struct AttendanceSummary: Equatable {
    var workingDays = 0      // working days elapsed in the range (not future, not weekend)
    var present = 0
    var absent = 0
    var unmarked = 0

    var recorded: Int { present + absent }

    /// Present / (Present + Absent) × 100. `nil` when nothing is recorded (never divides by zero).
    var percentage: Double? {
        guard recorded > 0 else { return nil }
        return Double(present) / Double(recorded) * 100
    }

    var percentageText: String {
        guard let p = percentage else { return "—" }
        return String(format: "%.1f%%", p)
    }
}

enum AttendanceCalculator {

    static func summary(entries: [AttendanceEntry],
                        from start: Date,
                        to end: Date,
                        rules: AttendanceRules) -> AttendanceSummary {
        var byDate: [Date: AttendanceEntry] = [:]
        for e in entries { byDate[DateFormatting.normalize(e.date)] = e }

        var result = AttendanceSummary()
        for day in DateFormatting.days(from: start, to: end) where rules.isCountedDay(day) {
            result.workingDays += 1
            switch byDate[day]?.status {
            case .present?: result.present += 1
            case .absent?: result.absent += 1
            case nil: result.unmarked += 1
            }
        }
        return result
    }
}

struct MonthPoint: Identifiable, Equatable {
    var id: Date { month }
    var month: Date
    var summary: AttendanceSummary
}

struct YearSummary: Equatable {
    var year: Int
    var total: AttendanceSummary
    var months: [MonthPoint]
}

/// Report-level helpers shared by the Reports tab and PDF export.
enum ReportService {

    static func monthPoints(entries: [AttendanceEntry], endingAt month: Date, count: Int, rules: AttendanceRules) -> [MonthPoint] {
        (0..<count).reversed().map { offset in
            let m = DateFormatting.addingMonths(-offset, to: month)
            let s = AttendanceCalculator.summary(entries: entries,
                                                 from: DateFormatting.startOfMonth(m),
                                                 to: DateFormatting.endOfMonth(m),
                                                 rules: rules)
            return MonthPoint(month: m, summary: s)
        }
    }

    static func yearSummary(entries: [AttendanceEntry], year: Int, rules: AttendanceRules) -> YearSummary {
        var comps = DateComponents(); comps.year = year; comps.month = 1; comps.day = 1
        let jan = DateFormatting.calendar.date(from: comps) ?? Date()
        let total = AttendanceCalculator.summary(entries: entries,
                                                 from: DateFormatting.startOfYear(jan),
                                                 to: DateFormatting.endOfYear(jan),
                                                 rules: rules)
        let months = (0..<12).map { i -> MonthPoint in
            let m = DateFormatting.addingMonths(i, to: jan)
            let s = AttendanceCalculator.summary(entries: entries,
                                                 from: DateFormatting.startOfMonth(m),
                                                 to: DateFormatting.endOfMonth(m),
                                                 rules: rules)
            return MonthPoint(month: m, summary: s)
        }
        return YearSummary(year: year, total: total, months: months)
    }

    /// Absent entries in range, newest first (includes all absences, working day or not).
    static func absences(entries: [AttendanceEntry], from start: Date, to end: Date) -> [AttendanceEntry] {
        let s = DateFormatting.normalize(start), e = DateFormatting.normalize(end)
        return entries.filter { $0.status == .absent && $0.date >= s && $0.date <= e }
            .sorted { $0.date > $1.date }
    }

    // MARK: - PDF

    enum ReportError: LocalizedError {
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .writeFailed(let m): return "Couldn't create the PDF report: \(m)"
            }
        }
    }

    /// Renders a printable PDF using UIKit's PDF renderer and returns a temp file URL.
    static func makePDF(entries: [AttendanceEntry],
                        from start: Date,
                        to end: Date,
                        rules: AttendanceRules,
                        generatedAt: Date = Date()) throws -> URL {
        let summary = AttendanceCalculator.summary(entries: entries, from: start, to: end, rules: rules)
        let absences = absences(entries: entries, from: start, to: end)

        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let margin: CGFloat = 48
        let contentWidth = pageRect.width - margin * 2

        let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
        let headingFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let mutedColor = UIColor.darkGray

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin

            func newPage() { ctx.beginPage(); y = margin }
            func ensure(_ height: CGFloat) { if y + height > pageRect.height - margin { newPage() } }

            @discardableResult
            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacing: CGFloat = 6) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let bounds = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs, context: nil)
                let h = ceil(bounds.height)
                ensure(h)
                (text as NSString).draw(
                    with: CGRect(x: margin, y: y, width: contentWidth, height: h),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs, context: nil)
                y += h + spacing
                return h
            }

            newPage()
            draw("MyAttendance Report", font: titleFont, spacing: 4)
            draw("\(DateFormatting.mediumDate(start)) – \(DateFormatting.mediumDate(end))",
                 font: headingFont, color: mutedColor, spacing: 2)
            draw("Generated \(DateFormatting.fullDate(generatedAt))", font: bodyFont, color: mutedColor, spacing: 16)

            draw("Summary", font: headingFont)
            draw("Working days elapsed: \(summary.workingDays)", font: bodyFont, spacing: 2)
            draw("Present: \(summary.present)", font: bodyFont, spacing: 2)
            draw("Absent: \(summary.absent)", font: bodyFont, spacing: 2)
            draw("Not marked: \(summary.unmarked)", font: bodyFont, spacing: 2)
            draw("Attendance: \(summary.percentage == nil ? "No recorded working days" : summary.percentageText)",
                 font: bodyFont, spacing: 16)

            draw("Absences (\(absences.count))", font: headingFont)
            if absences.isEmpty {
                draw("No absences in this period.", font: bodyFont, color: mutedColor)
            } else {
                for a in absences {
                    var line = "\(DateFormatting.isoDay(a.date)) (\(DateFormatting.weekdayName(a.date))) — \(a.absenceReason)"
                    if !a.notes.isEmpty { line += "  [\(a.notes)]" }
                    draw(line, font: bodyFont, spacing: 3)
                }
            }
        }

        let name = "MyAttendance_Report_\(DateFormatting.isoDay(start))_to_\(DateFormatting.isoDay(end)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ReportError.writeFailed(error.localizedDescription)
        }
        return url
    }
}
