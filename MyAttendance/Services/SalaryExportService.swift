import Foundation
import CoreGraphics
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

struct SalaryReport: Identifiable {
    var summary: SalarySummary
    var configuration: SalaryConfiguration
    var hasSnapshot: Bool
    var id: String { summary.month }
    var basis: String { hasSnapshot ? "Saved period rules; totals recalculate with attendance" : "Estimate using current salary settings; no historical snapshot" }
}

@MainActor
extension AttendanceStore {
    func salaryReport(month: Date, settings: AttendanceSettings, now: Date = Date()) throws -> SalaryReport? {
        guard let summary = try salaryResult(month: month, settings: settings, now: now) else { return nil }
        let snapshot = salary.snapshots.first { $0.month == summary.month }
        guard let config = snapshot?.configuration ?? salaryConfiguration(settings: settings) else { return nil }
        return SalaryReport(summary: summary, configuration: config, hasSnapshot: snapshot != nil)
    }
}

extension ExportService {
    static func salaryCSVData(reports: [SalaryReport]) throws -> Data {
        guard !reports.isEmpty else { throw ExportError.nothingToExport }
        let rows = reports.sorted { $0.id < $1.id }.map { report -> [String] in
            let s = report.summary, c = report.configuration
            return [s.month, s.periodStart, s.periodEnd, Money.raw(s.monthlySalary), String(s.scheduled),
                    String(s.scheduledToDate), String(s.present), String(s.paidAbsences), String(s.unpaidAbsences),
                    String(s.holidays), String(s.unmarked), String(s.future), Money.raw(s.dailyRate), Money.raw(s.gross),
                    Money.raw(s.lost), Money.raw(s.deductions), Money.raw(s.bonuses), Money.raw(s.net),
                    Money.raw(s.projectedGross), Money.raw(s.projectedNet), c.method.rawValue,
                    c.workingWeekdays.map(String.init).joined(separator: "|"), c.startDay,
                    c.paidAbsences ? "Paid" : "Unpaid", c.paidHolidays.joined(separator: "|"), report.basis]
        }
        let header = ["Month", "Period Start", "Period End", "Monthly Salary INR", "Scheduled Days",
                      "Scheduled To Date", "Present", "Paid Absences", "Unpaid Absences", "Paid Holidays",
                      "Unmarked To Date", "Future Days", "Daily Rate INR", "Confirmed Gross INR", "Salary Lost INR",
                      "Other Deductions INR", "Bonuses INR", "Estimated Net INR", "Projected Gross INR",
                      "Projected Net INR", "Calculation Method", "Working Weekdays", "Salary Start",
                      "Absence Rule", "Holiday Dates", "Settings Basis"]
        return Data(CSVCodec.encode(header: header, rows: rows).utf8)
    }

    static func exportSalaryCSV(reports: [SalaryReport]) throws -> URL {
        try writeTemporary(salaryCSVData(reports: reports), fileName: "MyAttendance_Salary_\(DateFormatting.fileDateStamp()).csv")
    }
}

extension ReportService {
    static func makeSalaryPDF(report: SalaryReport, generatedAt: Date = Date(), isPreview: Bool = false) throws -> URL {
        let logo: CGImage?
        #if canImport(UIKit)
        logo = UIImage(named: "BrandMark")?.cgImage
        #else
        if let url = Bundle(for: SalaryLedger.self).url(forResource: "BrandMark", withExtension: "png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            logo = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else { logo = nil }
        #endif
        let data = try SalaryInvoiceRenderer.data(report: report, logo: logo, generatedAt: generatedAt, isPreview: isPreview)
        return try ExportService.writeTemporary(data, fileName: "MyAttendance_SalaryStatement_\(report.summary.month).pdf")
    }
}
