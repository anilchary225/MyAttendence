import Foundation

/// Central place for calendar maths and date formatting.
/// Dates are stored as local start-of-day and exchanged as `yyyy-MM-dd`
/// strings in backups/CSV so they never shift with time zones.
enum DateFormatting {

    /// Gregorian calendar, Monday first, current time zone.
    /// Tests may replace this to pin a time zone.
    nonisolated(unsafe) static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        cal.timeZone = .current
        return cal
    }()

    static func normalize(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    static func isFuture(_ date: Date, now: Date = Date()) -> Bool {
        normalize(date) > normalize(now)
    }

    /// 1 = Sunday … 7 = Saturday (Foundation convention).
    static func weekday(of date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    static func isWeekend(_ date: Date) -> Bool {
        let w = weekday(of: date)
        return w == 1 || w == 7
    }

    static func startOfMonth(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? normalize(date)
    }

    static func endOfMonth(_ date: Date) -> Date {
        let start = startOfMonth(date)
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return calendar.date(byAdding: .day, value: -1, to: next) ?? start
    }

    static func addingMonths(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: startOfMonth(date)) ?? date
    }

    static func daysInMonth(_ date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func startOfYear(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year], from: date)
        return calendar.date(from: comps) ?? normalize(date)
    }

    static func endOfYear(_ date: Date) -> Date {
        let start = startOfYear(date)
        let next = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return calendar.date(byAdding: .day, value: -1, to: next) ?? start
    }

    /// Every day in the inclusive range, normalized.
    static func days(from start: Date, to end: Date) -> [Date] {
        let s = normalize(start)
        let e = normalize(end)
        guard s <= e else { return [] }
        var result: [Date] = []
        var cursor = s
        while cursor <= e {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Grid cells for a month, Monday first. `nil` entries are leading blanks.
    static func monthGrid(for month: Date) -> [Date?] {
        let first = startOfMonth(month)
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<daysInMonth(first) {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        return cells
    }

    /// Short weekday symbols starting Monday: ["M","T","W","T","F","S","S"] style.
    static func weekdaySymbolsMondayFirst() -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols // Sunday first
        return Array(symbols[1...]) + [symbols[0]]
    }

    // MARK: - Formatters

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }

    static func monthYear(_ date: Date) -> String { formatter("MMMM y").string(from: date) }
    static func fullDate(_ date: Date) -> String { formatter("EEEE d MMMM y").string(from: date) }
    static func mediumDate(_ date: Date) -> String { formatter("d MMM y").string(from: date) }
    static func weekdayName(_ date: Date) -> String { formatter("EEEE").string(from: date) }
    static func dayNumber(_ date: Date) -> String { String(calendar.component(.day, from: date)) }
    static func shortMonth(_ date: Date) -> String { formatter("MMM").string(from: date) }
    static func yearNumber(_ date: Date) -> Int { calendar.component(.year, from: date) }
    static func monthNumber(_ date: Date) -> Int { calendar.component(.month, from: date) }

    /// Stable, locale-independent `yyyy-MM-dd` used in files.
    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Strict parse of `yyyy-MM-dd`; returns nil for invalid dates like 2026-02-30.
    static func parseIsoDay(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        guard let date = calendar.date(from: comps) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return normalize(date)
    }

    /// Stable ISO-8601 timestamp (UTC) for created/updated/export times.
    static func isoTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func parseIsoTimestamp(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string.trimmingCharacters(in: .whitespaces))
    }

    /// Timestamp for file names, e.g. 2026-10-11.
    static func fileDateStamp(_ date: Date = Date()) -> String { isoDay(date) }
}
