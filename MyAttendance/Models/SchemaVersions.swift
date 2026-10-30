import SwiftData

/// Version 1 of the on-disk schema. When `AttendanceRecord` changes in a future release:
/// 1. Freeze the current model inside a frozen `VersionedSchema` before adding the next version.
/// 2. Append it to `schemas`.
/// 3. Add a `MigrationStage.lightweight` (or `.custom`) stage to `stages`.
enum AttendanceSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [AttendanceRecord.self] }
}

enum AttendanceSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [AttendanceRecord.self, SalaryLedger.self] }
}

enum AttendanceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AttendanceSchemaV1.self, AttendanceSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: AttendanceSchemaV1.self, toVersion: AttendanceSchemaV2.self)]
    }
}
