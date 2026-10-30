import Foundation

struct ImportIssue: Equatable, Identifiable {
    var id = UUID()
    var location: String
    var message: String

    static func == (l: ImportIssue, r: ImportIssue) -> Bool {
        l.location == r.location && l.message == r.message
    }
}

/// Result of parsing + validating a file, before anything is applied.
struct ImportParseResult {
    var source: String
    var entries: [AttendanceEntry]
    var issues: [ImportIssue]
    var settings: SettingsSnapshot?
    var exportedAt: Date?
    var totalRows: Int
    var salary: SalaryArchive? = nil

    var invalidCount: Int { issues.count }

    var dateRange: ClosedRange<Date>? {
        guard let first = entries.map(\.date).min(), let last = entries.map(\.date).max() else { return nil }
        return first...last
    }

    var dateRangeText: String {
        guard let r = dateRange else { return "No valid records" }
        return "\(DateFormatting.mediumDate(r.lowerBound)) – \(DateFormatting.mediumDate(r.upperBound))"
    }
}

/// What the user sees before confirming.
struct ImportPreview {
    var result: ImportParseResult
    var strategy: RestoreStrategy
    var plan: MergePlan
    var existingCount: Int

    /// Records that exist locally and would be removed by a replace.
    var removedByReplace: Int {
        strategy == .replaceAll ? existingCount : 0
    }
    var canApply: Bool { !result.entries.isEmpty || result.salary != nil || result.settings != nil }
}

/// Outcome shown after applying.
struct ImportSummary: Equatable {
    var imported = 0      // new dates added
    var updated = 0       // existing dates overwritten
    var skipped = 0       // kept existing (same or newer) + duplicate dates inside the file
    var invalid = 0       // rejected during validation
}

enum ImportError: LocalizedError {
    case notUTF8
    case emptyFile
    case missingColumns([String])
    case csv(String)

    var errorDescription: String? {
        switch self {
        case .notUTF8: return "The file isn't UTF-8 text, so it can't be read as CSV."
        case .emptyFile: return "The file is empty."
        case .missingColumns(let cols):
            return "The CSV is missing required column(s): \(cols.joined(separator: ", ")). Expected the header produced by MyAttendance's CSV export."
        case .csv(let m): return m
        }
    }
}

enum ImportService {

    // MARK: - Preview & summary

    static func preview(_ result: ImportParseResult,
                        existing: [AttendanceEntry],
                        strategy: RestoreStrategy) -> ImportPreview {
        let plan: MergePlan
        switch strategy {
        case .replaceAll:
            let (unique, dupes) = MergePlanner.dedupe(result.entries)
            var p = MergePlan(); p.toAdd = unique; p.duplicatesInFile = dupes
            plan = p
        case .merge:
            plan = MergePlanner.plan(existing: existing, incoming: result.entries)
        }
        return ImportPreview(result: result, strategy: strategy, plan: plan, existingCount: existing.count)
    }

    static func summary(for preview: ImportPreview) -> ImportSummary {
        ImportSummary(imported: preview.plan.addCount,
                      updated: preview.plan.replaceCount,
                      skipped: preview.plan.keepCount + preview.plan.duplicatesInFile,
                      invalid: preview.result.invalidCount)
    }

    // MARK: - File detection

    /// Parses either a MyAttendance JSON backup/report or a CSV exported by the app.
    static func parse(data: Data, fileName: String) throws -> ImportParseResult {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "csv" { return try parseCSV(data: data) }
        if ext == "json" { return try BackupService.parse(data: data) }
        // Unknown extension: sniff.
        if let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }), first == UInt8(ascii: "{") {
            return try BackupService.parse(data: data)
        }
        return try parseCSV(data: data)
    }

    // MARK: - CSV

    /// CSV import rules:
    /// - Required columns: `Date` (yyyy-MM-dd) and `Status` (Present/Absent, case-insensitive). Missing → file rejected.
    /// - Optional columns: `Weekday` (ignored), `Absence Reason`, `Notes`, `Created At`, `Updated At`.
    /// - Row with an invalid date or status → skipped and reported as invalid.
    /// - Absent row with an empty reason → skipped and reported as invalid.
    /// - Present row with a reason → reason is dropped.
    /// - Missing/invalid timestamps → the import time is used.
    /// - Duplicate dates inside the file → the later `Updated At` wins; ties keep the first row.
    static func parseCSV(data: Data, now: Date = Date()) throws -> ImportParseResult {
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.notUTF8 }
        let rows: [[String]]
        do { rows = try CSVCodec.parse(text) }
        catch { throw ImportError.csv(error.localizedDescription) }
        guard let header = rows.first else { throw ImportError.emptyFile }

        let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ name: String) -> Int? { names.firstIndex(of: name) }

        var missing: [String] = []
        let dateCol = column("date"); if dateCol == nil { missing.append("Date") }
        let statusCol = column("status"); if statusCol == nil { missing.append("Status") }
        guard let dateCol, let statusCol else { throw ImportError.missingColumns(missing) }

        let reasonCol = column("absence reason")
        let notesCol = column("notes")
        let createdCol = column("created at")
        let updatedCol = column("updated at")

        func value(_ row: [String], _ col: Int?) -> String {
            guard let col, col < row.count else { return "" }
            return row[col]
        }

        var entries: [AttendanceEntry] = []
        var issues: [ImportIssue] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let location = "Row \(offset + 2)"
            let dateText = value(row, dateCol)
            guard let date = DateFormatting.parseIsoDay(dateText) else {
                issues.append(ImportIssue(location: location, message: "Invalid date \"\(dateText)\" (expected yyyy-MM-dd)."))
                continue
            }
            let statusText = value(row, statusCol).trimmingCharacters(in: .whitespaces)
            guard let status = AttendanceStatus.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(statusText) == .orderedSame }) else {
                issues.append(ImportIssue(location: location, message: "Unknown status \"\(statusText)\"."))
                continue
            }
            let reason = value(row, reasonCol).trimmingCharacters(in: .whitespacesAndNewlines)
            if status == .absent && reason.isEmpty {
                issues.append(ImportIssue(location: location, message: "Absent row on \(dateText) has no reason."))
                continue
            }
            let created = DateFormatting.parseIsoTimestamp(value(row, createdCol)) ?? now
            let updated = DateFormatting.parseIsoTimestamp(value(row, updatedCol)) ?? created
            entries.append(AttendanceEntry(date: date, status: status,
                                           absenceReason: status == .absent ? reason : "",
                                           notes: value(row, notesCol),
                                           createdAt: created, updatedAt: updated))
        }

        return ImportParseResult(source: "CSV file", entries: entries, issues: issues,
                                 settings: nil, exportedAt: nil, totalRows: max(rows.count - 1, 0))
    }
}
