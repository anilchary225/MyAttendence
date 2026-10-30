import Foundation

/// Versioned, documented JSON structure shared by full backups and report exports.
///
/// ```
/// {
///   "appIdentifier": "com.myattendance.app",
///   "formatVersion": 2,
///   "kind": "fullBackup" | "reportExport",
///   "exportedAt": "2026-10-11T14:17:00Z",
///   "appVersion": "1.0",
///   "settings": { ... }          // present for fullBackup only
///   "records": [ { "date": "2026-10-09", "status": "Present" | "Absent",
///                  "absenceReason": "", "notes": "",
///                  "createdAt": "ISO-8601", "updatedAt": "ISO-8601" } ],
///   "metadata": { "recordCount": "42" },
///   "salary": { "configuration": { ... }, "snapshots": [ ... ] } // full backups only
/// }
/// ```
struct BackupFile: Codable, Equatable {
    var appIdentifier: String
    var formatVersion: Int
    var kind: String
    var exportedAt: String
    var appVersion: String
    var settings: SettingsSnapshot?
    var records: [RecordDTO]
    var metadata: [String: String]?
    var salary: SalaryArchive? = nil

    struct RecordDTO: Codable, Equatable {
        var date: String
        var status: String
        var absenceReason: String
        var notes: String
        var createdAt: String
        var updatedAt: String
    }
}

enum BackupKind {
    static let full = "fullBackup"
    static let report = "reportExport"
}

enum BackupError: LocalizedError, Equatable {
    case encodingFailed(String)
    case verificationFailed
    case notAMyAttendanceFile
    case malformed(String)
    case unsupportedVersion(Int)
    case notAFullBackup
    case unreadable(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let m): return "Couldn't create the backup: \(m)"
        case .verificationFailed: return "The backup failed its self-check and was not saved. Your data is unchanged."
        case .notAMyAttendanceFile: return "This file isn't a MyAttendance backup."
        case .malformed(let m): return "The backup file is damaged or incomplete (\(m)). Nothing was changed."
        case .unsupportedVersion(let v):
            return "This backup uses format version \(v), which this version of MyAttendance can't read. Update the app and try again."
        case .notAFullBackup: return "This is a report export, not a full backup. Use Import to add its records instead."
        case .unreadable(let m): return "Couldn't read the file: \(m)"
        case .writeFailed(let m): return "Couldn't write the file: \(m)"
        }
    }
}

enum BackupService {

    static let appIdentifier = "com.myattendance.app"
    static let currentVersion = 2
    static let supportedVersions = 1...2

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Build

    static func makeFile(entries: [AttendanceEntry],
                         settings: SettingsSnapshot?,
                         kind: String,
                         now: Date = Date(), salary: SalaryArchive? = nil) -> BackupFile {
        let sorted = entries.sorted { $0.date < $1.date }
        return BackupFile(
            appIdentifier: appIdentifier,
            formatVersion: currentVersion,
            kind: kind,
            exportedAt: DateFormatting.isoTimestamp(now),
            appVersion: appVersion,
            settings: kind == BackupKind.full ? settings : nil,
            records: sorted.map {
                BackupFile.RecordDTO(date: DateFormatting.isoDay($0.date),
                                     status: $0.status.rawValue,
                                     absenceReason: $0.absenceReason,
                                     notes: $0.notes,
                                     createdAt: DateFormatting.isoTimestamp($0.createdAt),
                                     updatedAt: DateFormatting.isoTimestamp($0.updatedAt))
            },
            metadata: ["recordCount": String(sorted.count)],
            salary: kind == BackupKind.full ? salary : nil
        )
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { return try encoder.encode(file) }
        catch { throw BackupError.encodingFailed(error.localizedDescription) }
    }

    /// Encodes and then re-parses the result; throws if it doesn't round-trip.
    static func generate(entries: [AttendanceEntry],
                         settings: SettingsSnapshot?,
                         kind: String = BackupKind.full,
                         now: Date = Date(), salary: SalaryArchive? = nil) throws -> Data {
        let file = makeFile(entries: entries, settings: settings, kind: kind, now: now, salary: salary)
        let data = try encode(file)
        let check = try parse(data: data, requireFullBackup: kind == BackupKind.full)
        guard check.issues.isEmpty, check.entries.count == entries.count, check.salary == salary else {
            throw BackupError.verificationFailed
        }
        return data
    }

    // MARK: - Parse / validate

    /// Validates the whole file before anything touches the database.
    /// File-level problems throw. Record-level problems are collected as issues and
    /// those records are skipped.
    static func parse(data: Data, requireFullBackup: Bool = false) throws -> ImportParseResult {
        let file: BackupFile
        do {
            file = try JSONDecoder().decode(BackupFile.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            // A JSON object that lacks our identifying keys is "not ours", not "damaged".
            if key.stringValue == "appIdentifier" || key.stringValue == "formatVersion" {
                throw BackupError.notAMyAttendanceFile
            }
            throw BackupError.malformed("missing \"\(key.stringValue)\"")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw BackupError.malformed(ctx.codingPath.map(\.stringValue).joined(separator: "."))
        } catch {
            throw BackupError.malformed("not valid JSON")
        }

        guard file.appIdentifier == appIdentifier else { throw BackupError.notAMyAttendanceFile }
        guard supportedVersions.contains(file.formatVersion) else {
            throw BackupError.unsupportedVersion(file.formatVersion)
        }
        if requireFullBackup && file.kind != BackupKind.full { throw BackupError.notAFullBackup }

        try file.salary?.validate()

        var entries: [AttendanceEntry] = []
        var issues: [ImportIssue] = []

        for (index, dto) in file.records.enumerated() {
            let location = "Record \(index + 1)"
            guard let date = DateFormatting.parseIsoDay(dto.date) else {
                issues.append(ImportIssue(location: location, message: "Invalid date \"\(dto.date)\"."))
                continue
            }
            guard let status = AttendanceStatus(rawValue: dto.status) else {
                issues.append(ImportIssue(location: location, message: "Unknown status \"\(dto.status)\"."))
                continue
            }
            if status == .absent && dto.absenceReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ImportIssue(location: location, message: "Absent record on \(dto.date) has no reason."))
                continue
            }
            let created = DateFormatting.parseIsoTimestamp(dto.createdAt) ?? Date()
            let updated = DateFormatting.parseIsoTimestamp(dto.updatedAt) ?? created
            entries.append(AttendanceEntry(
                date: date,
                status: status,
                absenceReason: status == .absent ? dto.absenceReason.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                notes: dto.notes,
                createdAt: created,
                updatedAt: updated))
        }

        return ImportParseResult(
            source: "MyAttendance backup",
            entries: entries,
            issues: issues,
            settings: file.kind == BackupKind.full ? file.settings : nil,
            exportedAt: DateFormatting.parseIsoTimestamp(file.exportedAt),
            totalRows: file.records.count,
            salary: file.kind == BackupKind.full ? file.salary : nil)
    }

    // MARK: - Files

    /// `MyAttendance_Backup_2026-10-11.json`; adds " (2)", " (3)"… instead of overwriting.
    static func backupFileName(now: Date = Date()) -> String {
        "MyAttendance_Backup_\(DateFormatting.fileDateStamp(now)).json"
    }

    static func uniqueURL(in directory: URL, fileName: String) -> URL {
        let fm = FileManager.default
        var url = directory.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var n = 2
        repeat {
            url = directory.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        } while fm.fileExists(atPath: url.path)
        return url
    }

    /// Writes backup data to a unique temp file for the share sheet / document picker.
    static func writeTemporary(_ data: Data, fileName: String) throws -> URL {
        let url = uniqueURL(in: FileManager.default.temporaryDirectory, fileName: fileName)
        do { try data.write(to: url, options: .atomic) }
        catch { throw BackupError.writeFailed(error.localizedDescription) }
        return url
    }

    /// Automatic safety copy of current data before a destructive restore. Stored in the
    /// app's Documents folder (local only). Throws so the caller can abort the restore.
    @discardableResult
    static func writeSafetyBackup(entries: [AttendanceEntry],
                                  settings: SettingsSnapshot?,
                                  now: Date = Date(), salary: SalaryArchive? = nil) throws -> URL {
        let data = try generate(entries: entries, settings: settings, now: now, salary: salary)
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("SafetyBackups", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = DateFormatting.isoTimestamp(now).replacingOccurrences(of: ":", with: "-")
            let url = uniqueURL(in: dir, fileName: "MyAttendance_SafetyBackup_\(stamp).json")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }
    }

    /// Reads a user-picked file (handles security-scoped URLs from the document picker).
    static func readFile(at url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { return try Data(contentsOf: url) }
        catch { throw BackupError.unreadable(error.localizedDescription) }
    }
}
