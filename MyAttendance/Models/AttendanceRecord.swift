import Foundation
import SwiftData

/// Allowed attendance statuses. Raw values are stable and used in backups/CSV.
enum AttendanceStatus: String, Codable, CaseIterable, Identifiable {
    case present = "Present"
    case absent = "Absent"

    var id: String { rawValue }
}

/// One attendance entry per calendar day. `date` is always the start of the
/// day in the user's current calendar (see `DateFormatting.normalize`).
@Model
final class AttendanceRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var statusRaw: String
    var absenceReason: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    var status: AttendanceStatus {
        get { AttendanceStatus(rawValue: statusRaw) ?? .present }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        date: Date,
        status: AttendanceStatus,
        absenceReason: String = "",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = DateFormatting.normalize(date)
        self.statusRaw = status.rawValue
        self.absenceReason = absenceReason
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Plain value used by services, tests, backup and import so they never
/// depend on live SwiftData objects.
struct AttendanceEntry: Codable, Equatable, Hashable {
    var date: Date
    var status: AttendanceStatus
    var absenceReason: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(date: Date,
         status: AttendanceStatus,
         absenceReason: String = "",
         notes: String = "",
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.date = DateFormatting.normalize(date)
        self.status = status
        self.absenceReason = absenceReason
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(_ record: AttendanceRecord) {
        self.init(date: record.date,
                  status: record.status,
                  absenceReason: record.absenceReason,
                  notes: record.notes,
                  createdAt: record.createdAt,
                  updatedAt: record.updatedAt)
    }
}
