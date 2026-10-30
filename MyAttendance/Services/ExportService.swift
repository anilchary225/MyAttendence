import Foundation

enum ExportError: LocalizedError {
    case nothingToExport
    case encodingFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .nothingToExport: return "There are no attendance records in that range to export."
        case .encodingFailed: return "Couldn't encode the export as UTF-8."
        case .writeFailed(let m): return "Couldn't write the export file: \(m)"
        }
    }
}

/// Optional date filter for exports. `nil` means "all records".
struct ExportRange: Equatable {
    var start: Date
    var end: Date

    func contains(_ date: Date) -> Bool {
        let d = DateFormatting.normalize(date)
        return d >= DateFormatting.normalize(start) && d <= DateFormatting.normalize(end)
    }

    var label: String {
        "\(DateFormatting.isoDay(start))_to_\(DateFormatting.isoDay(end))"
    }
}

enum ExportService {

    static let csvHeader = ["Date", "Weekday", "Status", "Absence Reason", "Notes", "Created At", "Updated At"]

    static func filter(_ entries: [AttendanceEntry], range: ExportRange?) -> [AttendanceEntry] {
        let list = range.map { r in entries.filter { r.contains($0.date) } } ?? entries
        return list.sorted { $0.date < $1.date }
    }

    // MARK: - CSV

    static func csvString(entries: [AttendanceEntry], range: ExportRange? = nil) -> String {
        let rows = filter(entries, range: range).map { e -> [String] in
            [DateFormatting.isoDay(e.date),
             DateFormatting.weekdayName(e.date),
             e.status.rawValue,
             e.absenceReason,
             e.notes,
             DateFormatting.isoTimestamp(e.createdAt),
             DateFormatting.isoTimestamp(e.updatedAt)]
        }
        return CSVCodec.encode(header: csvHeader, rows: rows)
    }

    static func csvData(entries: [AttendanceEntry], range: ExportRange? = nil) throws -> Data {
        let filtered = filter(entries, range: range)
        guard !filtered.isEmpty else { throw ExportError.nothingToExport }
        guard let data = csvString(entries: entries, range: range).data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    static func csvFileName(range: ExportRange?, now: Date = Date()) -> String {
        if let range { return "MyAttendance_\(range.label).csv" }
        return "MyAttendance_Export_\(DateFormatting.fileDateStamp(now)).csv"
    }

    // MARK: - JSON (report-only; not a restorable backup)

    static func jsonData(entries: [AttendanceEntry], range: ExportRange? = nil, now: Date = Date()) throws -> Data {
        let filtered = filter(entries, range: range)
        guard !filtered.isEmpty else { throw ExportError.nothingToExport }
        let file = BackupService.makeFile(entries: filtered, settings: nil, kind: BackupKind.report, now: now)
        return try BackupService.encode(file)
    }

    static func jsonFileName(range: ExportRange?, now: Date = Date()) -> String {
        if let range { return "MyAttendance_Report_\(range.label).json" }
        return "MyAttendance_Report_\(DateFormatting.fileDateStamp(now)).json"
    }

    // MARK: - Temp files

    static func writeTemporary(_ data: Data, fileName: String) throws -> URL {
        let url = BackupService.uniqueURL(in: FileManager.default.temporaryDirectory, fileName: fileName)
        do { try data.write(to: url, options: .atomic) }
        catch { throw ExportError.writeFailed(error.localizedDescription) }
        return url
    }

    static func exportCSV(entries: [AttendanceEntry], range: ExportRange?) throws -> URL {
        try writeTemporary(csvData(entries: entries, range: range), fileName: csvFileName(range: range))
    }

    static func exportJSON(entries: [AttendanceEntry], range: ExportRange?) throws -> URL {
        try writeTemporary(jsonData(entries: entries, range: range), fileName: jsonFileName(range: range))
    }
}
