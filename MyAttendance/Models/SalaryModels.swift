import Foundation
import SwiftData

enum SalaryMethod: String, Codable, CaseIterable, Identifiable {
    case scheduledWorkingDays, calendarDays
    var id: String { rawValue }
    var title: String { self == .scheduledWorkingDays ? "Scheduled working days" : "Calendar-day rate" }
    var explanation: String {
        self == .scheduledWorkingDays
        ? "Monthly salary ÷ scheduled working days. Only payable working days earn salary."
        : "Monthly salary ÷ all calendar days in the period. Only payable working days earn salary, so a full work schedule may earn less than the monthly target."
    }
}

struct SalaryConfiguration: Codable, Equatable {
    var monthlySalary: Decimal = 0
    var method: SalaryMethod = .scheduledWorkingDays
    var paidAbsences = false
    var deductions: Decimal = 0
    var bonuses: Decimal = 0
    var startDay: String = DateFormatting.isoDay(Date())
    // Restricted to 1...28 so every month has this day, without ambiguous clamping.
    var periodStartDay = 1
    var paidHolidays: [String] = []
    var workingWeekdays: [Int] = [2, 3, 4, 5, 6]
    var attendanceStartDay: String?

    var validationMessage: String? {
        for amount in [monthlySalary, deductions, bonuses] {
            if amount.isNaN || amount < 0 || amount > Decimal(1_000_000_000) {
                return "Enter amounts from ₹0 to ₹1,00,00,00,000."
            }
            if Money.round(amount) != amount { return "Use at most two decimal places for money." }
        }
        guard DateFormatting.parseIsoDay(startDay) != nil,
              (1...28).contains(periodStartDay),
              !workingWeekdays.isEmpty, workingWeekdays.allSatisfy({ (1...7).contains($0) }),
              Set(workingWeekdays).count == workingWeekdays.count,
              paidHolidays.allSatisfy({ DateFormatting.parseIsoDay($0) != nil }),
              attendanceStartDay == nil || DateFormatting.parseIsoDay(attendanceStartDay!) != nil else {
            return "Check the start date, salary period, holidays and working days."
        }
        return nil
    }

    func usingAttendance(_ settings: AttendanceSettings) -> Self {
        var copy = self
        copy.workingWeekdays = settings.workingWeekdays.sorted()
        copy.attendanceStartDay = settings.trackingStartDate.map(DateFormatting.isoDay)
        return copy
    }
}

struct SalaryDay: Codable, Equatable, Identifiable {
    var date: String
    var state: String
    var impact: Decimal
    var id: String { date }
}

struct SalarySummary: Codable, Equatable {
    var month: String
    var periodStart: String
    var periodEnd: String
    var monthlySalary: Decimal
    var scheduled = 0
    var scheduledToDate = 0
    var present = 0
    var paidAbsences = 0
    var unpaidAbsences = 0
    var holidays = 0
    var unmarked = 0
    var future = 0
    var dailyRate: Decimal?
    var gross: Decimal?
    var lost: Decimal?
    var deductions: Decimal
    var bonuses: Decimal
    var net: Decimal?
    var projectedGross: Decimal?
    var projectedNet: Decimal?
    var days: [SalaryDay] = []
    var paidDays: Int { present + paidAbsences + holidays }
    var attendancePercentage: Double? {
        let marked = present + paidAbsences + unpaidAbsences
        return marked == 0 ? nil : Double(present) / Double(marked) * 100
    }
}

/// Settings are frozen; metrics are recalculated only from the shared attendance records.
struct SalarySnapshot: Codable, Equatable, Identifiable {
    var month: String
    var configuration: SalaryConfiguration
    var summary: SalarySummary
    var savedAt: Date
    var id: String { month }
}

struct SalaryArchive: Codable, Equatable {
    var configuration: SalaryConfiguration?
    var effectiveMonth: String?
    var snapshots: [SalarySnapshot] = []
    var calendarHolidays: [String]? = nil

    func validate() throws {
        if let holidays = calendarHolidays {
            guard Set(holidays).count == holidays.count,
                  holidays.allSatisfy({ DateFormatting.parseIsoDay($0) != nil }) else {
                throw SalaryError.invalid("Invalid calendar holidays in backup.")
            }
        }
        if let config = configuration, let message = config.validationMessage { throw SalaryError.invalid(message) }
        if let month = effectiveMonth, !Self.isMonthKey(month) { throw SalaryError.invalid("Invalid salary effective month.") }
        guard Set(snapshots.map(\.month)).count == snapshots.count else {
            throw SalaryError.invalid("Duplicate salary periods in backup.")
        }
        for snapshot in snapshots {
            guard Self.isMonthKey(snapshot.month), snapshot.configuration.validationMessage == nil,
                  snapshot.summary.month == snapshot.month else {
                throw SalaryError.invalid("Invalid salary snapshot in backup.")
            }
        }
    }
    static func isMonthKey(_ key: String) -> Bool {
        guard let date = DateFormatting.parseIsoDay(key) else { return false }
        return DateFormatting.isoDay(DateFormatting.startOfMonth(date)) == key
    }
}

/// One local ledger keeps settings and monthly snapshots in the same transaction
/// as attendance restores. Money is encoded as Decimal, never floating point.
@Model
final class SalaryLedger {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { self.key = "salary"; self.payload = payload }
}

enum SalaryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return text } }
}

enum Money {
    static func round(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }
    static func text(_ value: Decimal?) -> String {
        guard let value, !value.isNaN else { return "Unavailable" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.locale = Locale(identifier: "en_IN")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: round(value))) ?? "Unavailable"
    }
    static func number(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
    static func raw(_ value: Decimal?) -> String {
        value.map { NSDecimalNumber(decimal: round($0)).stringValue } ?? ""
    }
    static func parse(_ text: String) -> Decimal? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")),
              value <= Decimal(1_000_000_000) else { return nil }
        return value
    }
}
