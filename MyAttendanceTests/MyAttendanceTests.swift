import XCTest
import SwiftData
@testable import MyAttendance

// MARK: - Helpers

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    DateFormatting.parseIsoDay(String(format: "%04d-%02d-%02d", y, m, d))!
}

private func entry(_ y: Int, _ m: Int, _ d: Int, _ s: AttendanceStatus,
                   reason: String = "", notes: String = "",
                   updated: Date = Date(timeIntervalSince1970: 1_000)) -> AttendanceEntry {
    AttendanceEntry(date: day(y, m, d), status: s,
                    absenceReason: s == .absent && reason.isEmpty ? "Sick leave" : reason,
                    notes: notes, createdAt: updated, updatedAt: updated)
}

// A fixed "now": Friday 2026-10-30 12:00 local.
private var fixedNow: Date {
    DateFormatting.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day(2026, 10, 30))!
}

// MARK: - Calculations

final class AttendanceCalculatorTests: XCTestCase {

    private var rules: AttendanceRules { AttendanceRules(now: fixedNow) }

    func testPercentageUsesPresentOverRecorded() {
        // Mon 12 – Fri 16 Oct 2026: 4 present, 1 absent
        let entries = [
            entry(2026, 10, 12, .present), entry(2026, 10, 13, .present),
            entry(2026, 10, 14, .present), entry(2026, 10, 15, .present),
            entry(2026, 10, 16, .absent)
        ]
        let s = AttendanceCalculator.summary(entries: entries, from: day(2026, 10, 12), to: day(2026, 10, 16), rules: rules)
        XCTAssertEqual(s.present, 4)
        XCTAssertEqual(s.absent, 1)
        XCTAssertEqual(s.unmarked, 0)
        XCTAssertEqual(s.percentage!, 80.0, accuracy: 0.0001)
    }

    func testZeroRecordedDaysHasNoPercentage() {
        let s = AttendanceCalculator.summary(entries: [], from: day(2026, 10, 1), to: day(2026, 10, 31), rules: rules)
        XCTAssertNil(s.percentage)
        XCTAssertEqual(s.percentageText, "—")
        XCTAssertEqual(s.recorded, 0)
    }

    func testUnmarkedDaysAreExcludedFromPercentage() {
        let s = AttendanceCalculator.summary(entries: [entry(2026, 10, 12, .present)],
                                             from: day(2026, 10, 12), to: day(2026, 10, 16), rules: rules)
        XCTAssertEqual(s.unmarked, 4)
        XCTAssertEqual(s.percentage!, 100.0, accuracy: 0.0001)
    }

    func testWeekendsAreExcluded() {
        // Sat 17 and Sun 18 Oct carry (imported) records but must not count.
        let entries = [entry(2026, 10, 17, .absent), entry(2026, 10, 18, .present)]
        let s = AttendanceCalculator.summary(entries: entries, from: day(2026, 10, 17), to: day(2026, 10, 18), rules: rules)
        XCTAssertEqual(s, AttendanceSummary())
    }

    func testFutureDatesAreExcluded() {
        // "Now" is Fri 30 Oct. Mon 2 Nov is future.
        let s = AttendanceCalculator.summary(entries: [entry(2026, 11, 2, .absent)],
                                             from: day(2026, 11, 1), to: day(2026, 11, 30), rules: rules)
        XCTAssertEqual(s.workingDays, 0)
        XCTAssertEqual(s.absent, 0)
        XCTAssertEqual(s.unmarked, 0)
    }

    func testTodayCountsAsElapsedWorkingDay() {
        let s = AttendanceCalculator.summary(entries: [], from: day(2026, 10, 30), to: day(2026, 10, 30), rules: rules)
        XCTAssertEqual(s.workingDays, 1)
        XCTAssertEqual(s.unmarked, 1)
    }

    func testCustomWorkingDaysIncludeSaturday() {
        let r = AttendanceRules(workingWeekdays: [2, 3, 4, 5, 6, 7], now: fixedNow)
        let s = AttendanceCalculator.summary(entries: [entry(2026, 10, 17, .present)],
                                             from: day(2026, 10, 17), to: day(2026, 10, 17), rules: r)
        XCTAssertEqual(s.present, 1)
    }

    func testTrackingStartExcludesEarlierDays() {
        let r = AttendanceRules(trackingStart: day(2026, 10, 14), now: fixedNow)
        let s = AttendanceCalculator.summary(entries: [], from: day(2026, 10, 12), to: day(2026, 10, 16), rules: r)
        XCTAssertEqual(s.workingDays, 3) // 14, 15, 16
    }

    func testLeapYearFebruary() {
        XCTAssertEqual(DateFormatting.daysInMonth(day(2028, 2, 10)), 29)
        XCTAssertEqual(DateFormatting.daysInMonth(day(2026, 2, 10)), 28)
        XCTAssertEqual(DateFormatting.daysInMonth(day(1900, 2, 10)), 28) // not a leap year
        XCTAssertEqual(DateFormatting.daysInMonth(day(2000, 2, 10)), 29)
        XCTAssertNotNil(DateFormatting.parseIsoDay("2028-02-29"))
        XCTAssertNil(DateFormatting.parseIsoDay("2026-02-29"))
    }

    func testMonthBoundaries() {
        XCTAssertEqual(DateFormatting.isoDay(DateFormatting.endOfMonth(day(2026, 12, 5))), "2026-12-31")
        XCTAssertEqual(DateFormatting.isoDay(DateFormatting.addingMonths(1, to: day(2026, 12, 15))), "2027-01-01")
        XCTAssertEqual(DateFormatting.isoDay(DateFormatting.addingMonths(-1, to: day(2027, 1, 31))), "2026-12-01")
        XCTAssertEqual(DateFormatting.isoDay(DateFormatting.endOfMonth(day(2028, 2, 1))), "2028-02-29")
    }

    func testMonthGridStartsOnMonday() {
        // 1 Oct 2026 is a Thursday → 3 leading blanks (Mon, Tue, Wed).
        let grid = DateFormatting.monthGrid(for: day(2026, 10, 1))
        XCTAssertEqual(grid.prefix(3).compactMap { $0 }.count, 0)
        XCTAssertEqual(grid[3], day(2026, 10, 1))
        XCTAssertEqual(grid.compactMap { $0 }.count, 31)
    }

    func testMondayFirstWeekdaySymbols() {
        XCTAssertEqual(DateFormatting.weekdaySymbolsMondayFirst().count, 7)
    }
}

// MARK: - Dates & validation

final class DateAndValidationTests: XCTestCase {

    func testNormalizeStripsTimeOfDay() {
        let noon = DateFormatting.calendar.date(bySettingHour: 15, minute: 42, second: 7, of: day(2026, 10, 12))!
        XCTAssertEqual(DateFormatting.normalize(noon), day(2026, 10, 12))
        let late = DateFormatting.calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day(2026, 10, 12))!
        XCTAssertEqual(DateFormatting.normalize(late), day(2026, 10, 12))
    }

    func testIsoDayRoundTrip() {
        let d = day(2026, 10, 12)
        XCTAssertEqual(DateFormatting.isoDay(d), "2026-10-12")
        XCTAssertEqual(DateFormatting.parseIsoDay("2026-10-12"), d)
    }

    func testRejectsMalformedDates() {
        for bad in ["", "2026-1-5", "12/10/2026", "2026-13-01", "2026-00-10", "2026-04-31", "abcd-ef-gh"] {
            XCTAssertNil(DateFormatting.parseIsoDay(bad), bad)
        }
    }

    func testAbsentRequiresNonBlankReason() {
        XCTAssertThrowsError(try AttendanceStore.validate(status: .absent, reason: "", requireReason: true))
        XCTAssertThrowsError(try AttendanceStore.validate(status: .absent, reason: "   \n\t ", requireReason: true))
        XCTAssertNoThrow(try AttendanceStore.validate(status: .absent, reason: "Sick leave", requireReason: true))
    }

    func testPresentNeverNeedsReason() {
        XCTAssertNoThrow(try AttendanceStore.validate(status: .present, reason: "", requireReason: true))
    }

    func testReasonOptionalWhenSettingOff() {
        XCTAssertNoThrow(try AttendanceStore.validate(status: .absent, reason: "", requireReason: false))
    }

    func testSettingsRecordingRules() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AttendanceSettings(defaults: defaults)
        XCTAssertNil(settings.recordingBlockReason(for: day(2026, 10, 12), now: fixedNow))      // Monday
        XCTAssertNotNil(settings.recordingBlockReason(for: day(2026, 10, 17), now: fixedNow))   // Saturday
        XCTAssertNotNil(settings.recordingBlockReason(for: day(2026, 11, 2), now: fixedNow))    // future
        settings.trackingStartDate = day(2026, 10, 20)
        XCTAssertNotNil(settings.recordingBlockReason(for: day(2026, 10, 12), now: fixedNow))   // before start
    }

    func testSettingsPersistAcrossInstances() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let a = AttendanceSettings(defaults: defaults)
        a.appearance = .dark
        a.workingWeekdays = [2, 3]
        a.requireAbsenceReason = false
        a.reminderHour = 8
        let b = AttendanceSettings(defaults: defaults)
        XCTAssertEqual(b.appearance, .dark)
        XCTAssertEqual(b.workingWeekdays, [2, 3])
        XCTAssertFalse(b.requireAbsenceReason)
        XCTAssertEqual(b.reminderHour, 8)
        XCTAssertFalse(b.remindersEnabled, "Reminders default to off")
    }
}

// MARK: - Store (in-memory SwiftData)

@MainActor
final class AttendanceStoreTests: XCTestCase {

    private var store: AttendanceStore!
    private var settings: AttendanceSettings!

    override func setUpWithError() throws {
        store = try AttendanceStore.inMemory()
        settings = AttendanceSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    func testSaveCreatesRecord() throws {
        try store.save(date: day(2026, 10, 12), status: .present, reason: "", notes: "", settings: settings, now: fixedNow)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.record(on: day(2026, 10, 12))?.status, .present)
    }

    func testDuplicateDateUpdatesInsteadOfInserting() throws {
        try store.save(date: day(2026, 10, 12), status: .present, reason: "", notes: "", settings: settings, now: fixedNow)
        let laterSameDay = DateFormatting.calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day(2026, 10, 12))!
        try store.save(date: laterSameDay, status: .absent, reason: "Travel", notes: "n", settings: settings, now: fixedNow)
        XCTAssertEqual(store.count, 1)
        let r = store.record(on: day(2026, 10, 12))!
        XCTAssertEqual(r.status, .absent)
        XCTAssertEqual(r.absenceReason, "Travel")
        XCTAssertTrue(store.hasRecord(on: day(2026, 10, 12)))
    }

    func testUpdatePreservesIdAndCreatedAt() throws {
        let t1 = fixedNow
        let t2 = fixedNow.addingTimeInterval(60)
        let first = try store.save(date: day(2026, 10, 12), status: .present, reason: "", notes: "", settings: settings, now: t1)
        let id = first.id
        try store.save(date: day(2026, 10, 12), status: .absent, reason: "Sick leave", notes: "", settings: settings, now: t2)
        let r = store.record(on: day(2026, 10, 12))!
        XCTAssertEqual(r.id, id)
        XCTAssertEqual(r.createdAt, t1)
        XCTAssertEqual(r.updatedAt, t2)
    }

    func testAbsentWithoutReasonIsRejectedAndNothingSaved() {
        XCTAssertThrowsError(try store.save(date: day(2026, 10, 12), status: .absent, reason: "  ", notes: "", settings: settings, now: fixedNow)) {
            XCTAssertEqual($0 as? AttendanceError, .missingReason)
        }
        XCTAssertEqual(store.count, 0)
    }

    func testPresentClearsStaleReason() throws {
        try store.save(date: day(2026, 10, 12), status: .absent, reason: "Travel", notes: "", settings: settings, now: fixedNow)
        try store.save(date: day(2026, 10, 12), status: .present, reason: "Travel", notes: "", settings: settings, now: fixedNow)
        XCTAssertEqual(store.record(on: day(2026, 10, 12))?.absenceReason, "")
    }

    func testWeekendAndFutureEntriesAreRejected() {
        XCTAssertThrowsError(try store.save(date: day(2026, 10, 17), status: .present, reason: "", notes: "", settings: settings, now: fixedNow))
        XCTAssertThrowsError(try store.save(date: day(2026, 11, 2), status: .present, reason: "", notes: "", settings: settings, now: fixedNow))
        XCTAssertEqual(store.count, 0)
    }

    func testExistingWeekendRecordCanStillBeEdited() throws {
        _ = try store.apply(entries: [entry(2026, 10, 17, .present)], strategy: .merge)
        XCTAssertNoThrow(try store.save(date: day(2026, 10, 17), status: .absent, reason: "Travel", notes: "", settings: settings, now: fixedNow))
        XCTAssertEqual(store.count, 1)
    }

    func testDeleteRemovesRecord() throws {
        let r = try store.save(date: day(2026, 10, 12), status: .present, reason: "", notes: "", settings: settings, now: fixedNow)
        try store.delete(r)
        XCTAssertEqual(store.count, 0)
    }

    func testReplaceStrategy() throws {
        _ = try store.apply(entries: [entry(2026, 10, 12, .present), entry(2026, 10, 13, .present)], strategy: .merge)
        try store.apply(entries: [entry(2026, 10, 14, .absent)], strategy: .replaceAll)
        XCTAssertEqual(store.count, 1)
        XCTAssertNotNil(store.record(on: day(2026, 10, 14)))
        XCTAssertNil(store.record(on: day(2026, 10, 12)))
    }

    func testMergeStrategyKeepsNewerAndAddsMissing() throws {
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 5_000)
        _ = try store.apply(entries: [entry(2026, 10, 12, .present, updated: new),
                                      entry(2026, 10, 13, .present, updated: old)], strategy: .merge)
        let plan = try store.apply(entries: [
            entry(2026, 10, 12, .absent, reason: "Travel", updated: old),   // older → keep local
            entry(2026, 10, 13, .absent, reason: "Travel", updated: new),   // newer → replace
            entry(2026, 10, 14, .present, updated: old)                     // new date → add
        ], strategy: .merge)
        XCTAssertEqual(plan.addCount, 1)
        XCTAssertEqual(plan.replaceCount, 1)
        XCTAssertEqual(plan.keepCount, 1)
        XCTAssertEqual(store.count, 3)
        XCTAssertEqual(store.record(on: day(2026, 10, 12))?.status, .present)
        XCTAssertEqual(store.record(on: day(2026, 10, 13))?.status, .absent)
    }

    func testMergeNeverDeletesLocalRecords() throws {
        _ = try store.apply(entries: [entry(2026, 10, 12, .present)], strategy: .merge)
        try store.apply(entries: [entry(2026, 10, 13, .present)], strategy: .merge)
        XCTAssertEqual(store.count, 2)
    }

    func testDuplicateDatesInsideImportAreCollapsedDeterministically() throws {
        let a = entry(2026, 10, 12, .present, updated: Date(timeIntervalSince1970: 1))
        let b = entry(2026, 10, 12, .absent, reason: "Travel", updated: Date(timeIntervalSince1970: 9))
        let plan = try store.apply(entries: [a, b], strategy: .merge)
        XCTAssertEqual(plan.duplicatesInFile, 1)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.record(on: day(2026, 10, 12))?.status, .absent)
    }

    func testStoreSummaryMatchesCalculator() throws {
        _ = try store.apply(entries: [entry(2026, 10, 12, .present), entry(2026, 10, 13, .absent)], strategy: .merge)
        let s = store.monthSummary(day(2026, 10, 1), settings: settings, now: fixedNow)
        XCTAssertEqual(s.present, 1)
        XCTAssertEqual(s.absent, 1)
        XCTAssertEqual(s.percentage!, 50.0, accuracy: 0.0001)
    }
}

// MARK: - Backup / import

final class BackupTests: XCTestCase {

    private let sample = [
        entry(2026, 10, 12, .present, notes: "Quote \" and, comma"),
        entry(2026, 10, 13, .absent, reason: "Family emergency")
    ]

    func testBackupEncodesAndDecodes() throws {
        let data = try BackupService.generate(entries: sample, settings: .default, now: fixedNow)
        let parsed = try BackupService.parse(data: data, requireFullBackup: true)
        XCTAssertEqual(parsed.entries.count, 2)
        XCTAssertTrue(parsed.issues.isEmpty)
        XCTAssertEqual(parsed.settings, .default)
        XCTAssertEqual(parsed.entries.first(where: { $0.status == .absent })?.absenceReason, "Family emergency")
        XCTAssertEqual(parsed.entries.first(where: { $0.status == .present })?.notes, "Quote \" and, comma")
    }

    func testBackupFileNameUsesDate() {
        XCTAssertEqual(BackupService.backupFileName(now: fixedNow), "MyAttendance_Backup_2026-10-30.json")
    }

    func testBackupContainsVersionMetadata() throws {
        let data = try BackupService.generate(entries: sample, settings: .default, now: fixedNow)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["appIdentifier"] as? String, BackupService.appIdentifier)
        XCTAssertEqual(json["formatVersion"] as? Int, 2)
        XCTAssertEqual(json["kind"] as? String, BackupKind.full)
        XCTAssertNotNil(json["exportedAt"])
    }

    func testUnsupportedVersionRejected() throws {
        var file = BackupService.makeFile(entries: sample, settings: .default, kind: BackupKind.full)
        file.formatVersion = 99
        let data = try BackupService.encode(file)
        XCTAssertThrowsError(try BackupService.parse(data: data)) {
            XCTAssertEqual($0 as? BackupError, .unsupportedVersion(99))
        }
    }

    func testWrongAppIdentifierRejected() throws {
        var file = BackupService.makeFile(entries: sample, settings: .default, kind: BackupKind.full)
        file.appIdentifier = "com.other.app"
        XCTAssertThrowsError(try BackupService.parse(data: try BackupService.encode(file))) {
            XCTAssertEqual($0 as? BackupError, .notAMyAttendanceFile)
        }
    }

    func testGarbageAndEmptyFilesRejected() {
        XCTAssertThrowsError(try BackupService.parse(data: Data("not json".utf8)))
        XCTAssertThrowsError(try BackupService.parse(data: Data()))
        XCTAssertThrowsError(try BackupService.parse(data: Data("{}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notAMyAttendanceFile)
        }
        XCTAssertThrowsError(try BackupService.parse(data: Data("[1,2,3]".utf8)))
    }

    func testReportExportIsNotAcceptedAsRestore() throws {
        let data = try ExportService.jsonData(entries: sample, now: fixedNow)
        XCTAssertThrowsError(try BackupService.parse(data: data, requireFullBackup: true)) {
            XCTAssertEqual($0 as? BackupError, .notAFullBackup)
        }
        // …but it can still be imported as records.
        XCTAssertEqual(try BackupService.parse(data: data).entries.count, 2)
    }

    func testInvalidRecordsAreReportedAndSkipped() throws {
        var file = BackupService.makeFile(entries: sample, settings: .default, kind: BackupKind.full)
        let ts = DateFormatting.isoTimestamp(fixedNow)
        file.records.append(.init(date: "2026-02-30", status: "Present", absenceReason: "", notes: "", createdAt: ts, updatedAt: ts))
        file.records.append(.init(date: "2026-10-14", status: "Late", absenceReason: "", notes: "", createdAt: ts, updatedAt: ts))
        file.records.append(.init(date: "2026-10-15", status: "Absent", absenceReason: "  ", notes: "", createdAt: ts, updatedAt: ts))
        let parsed = try BackupService.parse(data: try BackupService.encode(file))
        XCTAssertEqual(parsed.entries.count, 2)
        XCTAssertEqual(parsed.invalidCount, 3)
    }

    func testUniqueURLNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = BackupService.uniqueURL(in: dir, fileName: "a.json")
        try Data("x".utf8).write(to: first)
        let second = BackupService.uniqueURL(in: dir, fileName: "a.json")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "a (2).json")
    }

    func testSettingsSnapshotRoundTrip() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let a = AttendanceSettings(defaults: defaults)
        a.workingWeekdays = [2, 4, 6]
        a.requireAbsenceReason = false
        a.trackingStartDate = day(2026, 1, 5)
        let snap = a.snapshot
        let b = AttendanceSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        b.apply(snap)
        XCTAssertEqual(b.workingWeekdays, [2, 4, 6])
        XCTAssertFalse(b.requireAbsenceReason)
        XCTAssertEqual(b.trackingStartDate, day(2026, 1, 5))
    }
}

// MARK: - CSV

final class CSVTests: XCTestCase {

    func testEscaping() {
        XCTAssertEqual(CSVCodec.escape("plain"), "plain")
        XCTAssertEqual(CSVCodec.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVCodec.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVCodec.escape("line1\nline2"), "\"line1\nline2\"")
    }

    func testParseHandlesQuotesCommasNewlinesAndBOM() throws {
        let text = "\u{FEFF}a,b\r\n\"x,1\",\"he said \"\"yo\"\"\"\r\n\"multi\nline\",z\r\n"
        let rows = try CSVCodec.parse(text)
        XCTAssertEqual(rows, [["a", "b"], ["x,1", "he said \"yo\""], ["multi\nline", "z"]])
    }

    func testUnterminatedQuoteThrows() {
        XCTAssertThrowsError(try CSVCodec.parse("a,b\n\"oops,1\n"))
    }

    func testExportHasHeaderAndStableDates() {
        let csv = ExportService.csvString(entries: [entry(2026, 10, 13, .absent, reason: "Sick, flu")])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "Date,Weekday,Status,Absence Reason,Notes,Created At,Updated At")
        XCTAssertTrue(lines[1].hasPrefix("2026-10-13,"))
        XCTAssertTrue(lines[1].contains("\"Sick, flu\""))
    }

    func testRoundTripImport() throws {
        let original = [
            entry(2026, 10, 12, .present, notes: "multi\nline, \"quoted\""),
            entry(2026, 10, 13, .absent, reason: "Travel, \"long\" trip")
        ]
        let data = try ExportService.csvData(entries: original)
        let parsed = try ImportService.parseCSV(data: data)
        XCTAssertTrue(parsed.issues.isEmpty)
        XCTAssertEqual(Set(parsed.entries.map(\.date)), Set(original.map(\.date)))
        let absent = parsed.entries.first { $0.status == .absent }!
        XCTAssertEqual(absent.absenceReason, "Travel, \"long\" trip")
        let present = parsed.entries.first { $0.status == .present }!
        XCTAssertEqual(present.notes, "multi\nline, \"quoted\"")
    }

    func testCSVImportValidation() throws {
        let csv = """
        Date,Status,Absence Reason
        2026-10-12,present,
        2026-10-13,Absent,
        2026-10-14,Absent,Travel
        2026-13-01,Present,
        2026-10-15,Maybe,
        """
        let parsed = try ImportService.parseCSV(data: Data(csv.utf8))
        XCTAssertEqual(parsed.entries.count, 2)      // present (case-insensitive) + absent w/ reason
        XCTAssertEqual(parsed.invalidCount, 3)       // no reason, bad date, bad status
        XCTAssertEqual(parsed.totalRows, 5)
    }

    func testCSVMissingRequiredColumnRejected() {
        XCTAssertThrowsError(try ImportService.parseCSV(data: Data("Date,Notes\n2026-10-12,x\n".utf8))) {
            guard case ImportError.missingColumns(let cols) = $0 else { return XCTFail("wrong error") }
            XCTAssertEqual(cols, ["Status"])
        }
        XCTAssertThrowsError(try ImportService.parseCSV(data: Data()))
    }

    func testExportRangeFiltersAndNothingToExport() {
        let entries = [entry(2026, 9, 30, .present), entry(2026, 10, 1, .present), entry(2026, 10, 31, .present)]
        let range = ExportRange(start: day(2026, 10, 1), end: day(2026, 10, 31))
        XCTAssertEqual(ExportService.filter(entries, range: range).count, 2)
        XCTAssertThrowsError(try ExportService.csvData(entries: entries,
                             range: ExportRange(start: day(2025, 1, 1), end: day(2025, 1, 31))))
    }
}

// MARK: - Failed import leaves data intact

@MainActor
final class ImportSafetyTests: XCTestCase {

    func testFailedParsingDoesNotTouchExistingRecords() throws {
        let store = try AttendanceStore.inMemory()
        try store.apply(entries: [entry(2026, 10, 12, .present), entry(2026, 10, 13, .absent)], strategy: .merge)
        let before = store.entries()

        XCTAssertThrowsError(try BackupService.parse(data: Data("{\"appIdentifier\":".utf8)))
        XCTAssertThrowsError(try ImportService.parseCSV(data: Data("Foo,Bar\n1,2".utf8)))

        XCTAssertEqual(store.entries(), before)
    }

    func testPreviewDoesNotMutateStore() throws {
        let store = try AttendanceStore.inMemory()
        try store.apply(entries: [entry(2026, 10, 12, .present)], strategy: .merge)
        let parsed = ImportParseResult(source: "t", entries: [entry(2026, 10, 14, .present)], issues: [],
                                       settings: nil, exportedAt: nil, totalRows: 1)
        let preview = ImportService.preview(parsed, existing: store.entries(), strategy: .replaceAll)
        XCTAssertEqual(preview.removedByReplace, 1)
        XCTAssertEqual(store.count, 1)
    }

    func testImportSummaryCounts() {
        let existing = [entry(2026, 10, 12, .present, updated: Date(timeIntervalSince1970: 100))]
        let parsed = ImportParseResult(
            source: "t",
            entries: [entry(2026, 10, 12, .absent, updated: Date(timeIntervalSince1970: 500)),
                      entry(2026, 10, 13, .present),
                      entry(2026, 10, 13, .present)],
            issues: [ImportIssue(location: "Row 9", message: "bad")], settings: nil, exportedAt: nil, totalRows: 4)
        let s = ImportService.summary(for: ImportService.preview(parsed, existing: existing, strategy: .merge))
        XCTAssertEqual(s, ImportSummary(imported: 1, updated: 1, skipped: 1, invalid: 1))
    }
}

// MARK: - Reminders planning

final class ReminderPlanningTests: XCTestCase {

    func testSkipsNonWorkingAndMarkedDays() {
        // Now: Fri 30 Oct 2026 at 08:00; reminders at 18:00.
        let now = DateFormatting.calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day(2026, 10, 30))!
        let dates = NotificationService.plannedFireDates(
            now: now, workingWeekdays: [2, 3, 4, 5, 6], trackingStart: nil, hour: 18, minute: 0,
            markedDates: [day(2026, 11, 2)], horizon: 7)
        let days = dates.map { DateFormatting.isoDay($0) }
        XCTAssertEqual(days, ["2026-10-30", "2026-11-03", "2026-11-04", "2026-11-05"]) // skips Sat/Sun and marked Mon
    }

    func testNoReminderForTodayWhenAlreadyMarkedOrTimePassed() {
        let evening = DateFormatting.calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day(2026, 10, 30))!
        let dates = NotificationService.plannedFireDates(
            now: evening, workingWeekdays: [2, 3, 4, 5, 6], trackingStart: nil, hour: 18, minute: 0,
            markedDates: [], horizon: 1)
        XCTAssertTrue(dates.isEmpty)
    }

    func testRespectsTrackingStart() {
        let now = DateFormatting.calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day(2026, 10, 30))!
        let dates = NotificationService.plannedFireDates(
            now: now, workingWeekdays: [2, 3, 4, 5, 6], trackingStart: day(2026, 11, 4), hour: 18, minute: 0,
            markedDates: [], horizon: 7)
        XCTAssertEqual(dates.map { DateFormatting.isoDay($0) }, ["2026-11-04", "2026-11-05"])
    }
}
