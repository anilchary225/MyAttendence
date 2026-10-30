import XCTest
import SwiftData
import PDFKit
@testable import MyAttendance

private func salaryDate(_ key: String) -> Date { DateFormatting.parseIsoDay(key)! }
private func salaryEntry(_ key: String, _ status: AttendanceStatus) -> AttendanceEntry {
    AttendanceEntry(date: salaryDate(key), status: status, absenceReason: status == .absent ? "Leave" : "")
}
private func salaryConfig(_ salary: Decimal = 30000) -> SalaryConfiguration {
    var config = SalaryConfiguration()
    config.monthlySalary = salary
    config.startDay = "2026-01-01"
    return config
}

final class SalaryCalculatorTests: XCTestCase {
    func testTwentyTwoDayMonthAndUnpaidAbsence() throws {
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: salaryConfig(),
            entries: [salaryEntry("2026-10-01", .present), salaryEntry("2026-10-02", .absent)], now: salaryDate("2026-10-30"))
        XCTAssertEqual(s.scheduled, 22)
        XCTAssertEqual(s.dailyRate, Decimal(string: "1363.64"))
        XCTAssertEqual(s.gross, Decimal(string: "1363.64"))
        XCTAssertEqual(s.lost, Decimal(string: "1363.64"))
        XCTAssertEqual(s.unmarked, 20)
        XCTAssertEqual(s.unpaidAbsences, 1)
        XCTAssertEqual(s.attendancePercentage, 50)
    }

    func testUnmarkedAndWeekendRecordsNeverCauseLoss() throws {
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: salaryConfig(),
            entries: [salaryEntry("2026-10-03", .absent)], now: salaryDate("2026-10-30"))
        XCTAssertEqual(s.lost, 0)
        XCTAssertEqual(s.gross, 0)
        XCTAssertEqual(s.unmarked, 22)
        XCTAssertNil(s.attendancePercentage)
    }

    func testProjectionDoesNotPayPastUnmarkedDaysOrCountFutureAttendance() throws {
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: salaryConfig(22000),
            entries: [salaryEntry("2026-10-01", .present), salaryEntry("2026-10-02", .absent),
                      salaryEntry("2026-10-30", .absent)], now: salaryDate("2026-10-02"))
        XCTAssertEqual(s.scheduledToDate, 2)
        XCTAssertEqual(s.future, 20)
        XCTAssertEqual(s.gross, 1000)
        XCTAssertEqual(s.lost, 1000)
        XCTAssertEqual(s.projectedGross, 21000)
        XCTAssertEqual(s.unpaidAbsences, 1)
    }

    func testPaidAbsencesAndHolidaysOnlyPayOnce() throws {
        var config = salaryConfig(22000)
        config.paidAbsences = true
        config.paidHolidays = ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-05"]
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
            entries: [salaryEntry("2026-10-01", .present), salaryEntry("2026-10-02", .absent),
                      salaryEntry("2026-10-06", .absent)], now: salaryDate("2026-10-30"))
        XCTAssertEqual(s.paidDays, 4)
        XCTAssertEqual(s.holidays, 1)
        XCTAssertEqual(s.paidAbsences, 2)
        XCTAssertEqual(s.unmarked, 19, "Paid holidays without attendance remain unmarked")
        XCTAssertEqual(s.lost, 0)
        XCTAssertEqual(s.gross, 4000)
    }

    func testHolidayOverridesUnpaidAbsence() throws {
        var config = salaryConfig(22000)
        config.paidHolidays = ["2026-10-01"]
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
            entries: [salaryEntry("2026-10-01", .absent)], now: salaryDate("2026-10-02"))
        XCTAssertEqual(s.lost, 0)
        XCTAssertEqual(s.gross, 1000)
        XCTAssertEqual(s.paidDays, 1)
        XCTAssertEqual(s.attendancePercentage, 0)
    }

    func testRoundingWholePeriodRecoversMonthlyTarget() throws {
        let config = salaryConfig()
        let entries = DateFormatting.days(from: salaryDate("2026-10-01"), to: salaryDate("2026-10-31"))
            .filter { config.workingWeekdays.contains(DateFormatting.weekday(of: $0)) }
            .map { AttendanceEntry(date: $0, status: .present) }
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
                                                entries: entries, now: salaryDate("2026-11-01"))
        XCTAssertEqual(s.gross, 30000)
        XCTAssertEqual(s.net, 30000)
        XCTAssertNil(s.projectedGross)
    }

    func testDeductionsBonusesAndNonnegativeNet() throws {
        var config = salaryConfig(22000)
        config.deductions = 2000; config.bonuses = 200
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
            entries: [salaryEntry("2026-10-01", .present), salaryEntry("2026-10-02", .absent)], now: salaryDate("2026-10-30"))
        XCTAssertEqual(s.gross, 1000)
        XCTAssertEqual(s.net, 0)
        config.deductions = 100
        let t = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
            entries: [salaryEntry("2026-10-01", .present), salaryEntry("2026-10-02", .absent)], now: salaryDate("2026-10-30"))
        XCTAssertEqual(t.net, 1100, "Absence loss must not be deducted twice")
    }

    func testStartDatesFilterPayableDaysButNotFullMonthDivisor() throws {
        var config = salaryConfig(22000)
        config.startDay = "2026-10-02"
        config.attendanceStartDay = "2026-10-05"
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
            entries: [salaryEntry("2026-10-01", .present), salaryEntry("2026-10-02", .present), salaryEntry("2026-10-05", .present)],
            now: salaryDate("2026-10-05"))
        XCTAssertEqual(s.scheduled, 22)
        XCTAssertEqual(s.scheduledToDate, 1)
        XCTAssertEqual(s.gross, 1000)
        XCTAssertEqual(s.unmarked, 0)
    }

    func testNoWorkingDaysAndNoEligibleDaysAreUnavailable() throws {
        var config = salaryConfig()
        config.startDay = "2027-01-01"
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
                                                entries: [], now: salaryDate("2026-10-30"))
        XCTAssertNil(s.gross)
        config.workingWeekdays = []
        XCTAssertThrowsError(try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
                                                            entries: [], now: salaryDate("2026-10-30")))
    }

    func testMonthBoundariesLeapYearAndCustomPeriod() throws {
        var config = salaryConfig()
        config.startDay = "2020-01-01"
        let feb = try SalaryCalculator.calculate(month: salaryDate("2024-02-01"), configuration: config,
                                                 entries: [], now: salaryDate("2024-03-01"))
        XCTAssertEqual(feb.scheduled, 21)
        XCTAssertEqual(feb.periodEnd, "2024-02-29")
        config.periodStartDay = 26
        let period = SalaryCalculator.period(salaryDate("2026-12-01"), configuration: config)
        XCTAssertEqual(DateFormatting.isoDay(period.start), "2026-12-26")
        XCTAssertEqual(DateFormatting.isoDay(period.end), "2027-01-25")
        XCTAssertEqual(SalaryCalculator.monthKey(SalaryCalculator.activeMonth(configuration: config, now: salaryDate("2027-01-01"))), "2026-12-01")
    }

    func testCustomPeriodIncludesBothBoundariesAndExcludesOutsideDates() throws {
        var config = salaryConfig(22000); config.periodStartDay = 26
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
            entries: [salaryEntry("2026-10-23", .present), salaryEntry("2026-10-26", .present),
                      salaryEntry("2026-11-25", .absent), salaryEntry("2026-11-26", .absent)],
            now: salaryDate("2026-11-26"))
        XCTAssertEqual(s.periodStart, "2026-10-26")
        XCTAssertEqual(s.periodEnd, "2026-11-25")
        XCTAssertEqual(s.present, 1)
        XCTAssertEqual(s.unpaidAbsences, 1)
        XCTAssertNil(s.projectedGross)
    }

    func testPastUnmarkedDaysAreExcludedFromProjection() throws {
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: salaryConfig(22000),
            entries: [salaryEntry("2026-10-01", .present)], now: salaryDate("2026-10-05"))
        XCTAssertEqual(s.unmarked, 2)
        XCTAssertEqual(s.future, 19)
        XCTAssertEqual(s.projectedGross, 20000)
        XCTAssertEqual(s.lost, 0)
    }

    func testCalendarDayMethodUsesPeriodLength() throws {
        var config = salaryConfig(31000); config.method = .calendarDays
        let s = try SalaryCalculator.calculate(month: salaryDate("2026-10-01"), configuration: config,
            entries: [salaryEntry("2026-10-01", .present)], now: salaryDate("2026-10-30"))
        XCTAssertEqual(s.dailyRate, 1000)
        XCTAssertEqual(s.gross, 1000)
    }

    func testValidationRejectsNegativeFractionalAndMalformedSettings() {
        var config = salaryConfig(-1)
        XCTAssertNotNil(config.validationMessage)
        config.monthlySalary = Decimal(string: "1.001")!
        XCTAssertNotNil(config.validationMessage)
        config.monthlySalary = 0; config.periodStartDay = 31
        XCTAssertNotNil(config.validationMessage)
        for value in ["", "-1", "abc", "12.345", "1,000", "1e3"] { XCTAssertNil(Money.parse(value)) }
        XCTAssertEqual(Money.parse("30000.50"), Decimal(string: "30000.5"))
    }
}

@MainActor
final class SalaryPersistenceTests: XCTestCase {
    private func settings() -> AttendanceSettings {
        AttendanceSettings(defaults: UserDefaults(suiteName: "salary-\(UUID())")!)
    }

    func testSalarySurvivesNewStoreAndAttendanceEditsRecalculateSnapshots() throws {
        let store = try AttendanceStore.inMemory(), settings = settings()
        try store.saveSalary(configuration: salaryConfig(22000), settings: settings, now: salaryDate("2026-10-02"))
        let record = try store.save(date: salaryDate("2026-10-01"), status: .present, reason: "", notes: "", settings: settings, now: salaryDate("2026-10-02"))
        XCTAssertEqual(store.salary.snapshots.first?.summary.gross, 1000)
        let reopened = AttendanceStore(container: store.container)
        XCTAssertEqual(reopened.salary.configuration?.monthlySalary, 22000)
        try store.delete(record)
        XCTAssertEqual(store.salary.snapshots.first?.summary.gross, 0)
        XCTAssertEqual(store.salary.snapshots.first?.summary.lost, 0)
    }

    func testClosedSnapshotDoesNotChangeWhenSalaryOrScheduleChanges() throws {
        let store = try AttendanceStore.inMemory(), settings = settings()
        try store.saveSalary(configuration: salaryConfig(22000), settings: settings, now: salaryDate("2026-10-02"))
        _ = try store.save(date: salaryDate("2026-10-01"), status: .present, reason: "", notes: "", settings: settings, now: salaryDate("2026-10-02"))
        settings.workingWeekdays = [2]
        try store.saveSalary(configuration: salaryConfig(50000), settings: settings, now: salaryDate("2026-11-02"))
        let oct = try XCTUnwrap(store.salary.snapshots.first { $0.month == "2026-10-01" })
        XCTAssertEqual(oct.configuration.monthlySalary, 22000)
        XCTAssertEqual(oct.configuration.workingWeekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(oct.summary.gross, 1000)
        _ = try store.save(date: salaryDate("2026-10-01"), status: .absent, reason: "Leave", notes: "", settings: settings, now: salaryDate("2026-11-02"))
        XCTAssertEqual(store.salary.snapshots.first { $0.month == "2026-10-01" }?.summary.lost, 1000)
        XCTAssertEqual(store.salary.snapshots.first { $0.month == "2026-10-01" }?.configuration.monthlySalary, 22000)
    }

    func testMissedMonthsCaptureKnownRulesAndEarlierMonthIsLabelled() throws {
        let store = try AttendanceStore.inMemory(), settings = settings()
        try store.saveSalary(configuration: salaryConfig(), settings: settings, now: salaryDate("2026-08-10"))
        try store.synchronizeSalary(settings: settings, now: salaryDate("2026-10-30"))
        XCTAssertEqual(Set(store.salary.snapshots.map(\.month)), ["2026-08-01", "2026-09-01", "2026-10-01"])
        XCTAssertFalse(try XCTUnwrap(store.salaryReport(month: salaryDate("2026-07-01"), settings: settings)).hasSnapshot)
        let before = store.salary
        try store.synchronizeSalary(settings: settings, now: salaryDate("2026-10-30"))
        XCTAssertEqual(store.salary, before, "Synchronizing unchanged settings should be idempotent")
    }

    func testBackupRoundTripMergeReplaceAndLegacyBackup() throws {
        let source = try AttendanceStore.inMemory(), settings = settings()
        try source.saveSalary(configuration: salaryConfig(), settings: settings, now: salaryDate("2026-10-30"))
        let data = try BackupService.generate(entries: [], settings: settings.snapshot, salary: source.salary)
        let parsed = try BackupService.parse(data: data, requireFullBackup: true)
        XCTAssertEqual(parsed.salary, source.salary)
        let target = try AttendanceStore.inMemory()
        try target.apply(entries: parsed.entries, strategy: .replaceAll, salary: parsed.salary, restoreSalary: true)
        XCTAssertEqual(target.salary.configuration, source.salary.configuration)
        XCTAssertTrue(ImportService.preview(parsed, existing: [], strategy: .merge).canApply)
        try target.saveSalary(configuration: salaryConfig(40000), settings: settings, now: salaryDate("2026-10-30"))
        try target.apply(entries: [], strategy: .merge, salary: parsed.salary, restoreSalary: true)
        XCTAssertEqual(target.salary.configuration?.monthlySalary, 40000)
        var legacy = BackupService.makeFile(entries: [], settings: .default, kind: BackupKind.full)
        legacy.formatVersion = 1
        let old = try BackupService.parse(data: BackupService.encode(legacy), requireFullBackup: true)
        XCTAssertNil(old.salary)
        try target.apply(entries: [], strategy: .merge, salary: nil, restoreSalary: true)
        XCTAssertNotNil(target.salary.configuration)
        try target.apply(entries: [], strategy: .replaceAll, salary: nil, restoreSalary: true)
        XCTAssertNil(target.salary.configuration)
    }

    func testSalaryPeriodCannotSilentlyOverlapHistory() throws {
        let store = try AttendanceStore.inMemory(), settings = settings()
        try store.saveSalary(configuration: salaryConfig(), settings: settings, now: salaryDate("2026-10-30"))
        var changed = salaryConfig(); changed.periodStartDay = 26
        XCTAssertThrowsError(try store.saveSalary(configuration: changed, settings: settings, now: salaryDate("2026-11-02")))
        XCTAssertEqual(store.salary.configuration?.periodStartDay, 1)
    }

    func testSalarySettingsPersistOnDiskAcrossContainers() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("salary-disk-\(UUID()).store")
        do {
            let container = try ModelContainer(for: Schema(versionedSchema: AttendanceSchemaV2.self),
                migrationPlan: AttendanceMigrationPlan.self, configurations: ModelConfiguration(url: url))
            let store = AttendanceStore(container: container)
            try store.saveSalary(configuration: salaryConfig(42000), settings: settings(), now: salaryDate("2026-10-30"))
        }
        let reopened = try ModelContainer(for: Schema(versionedSchema: AttendanceSchemaV2.self),
            migrationPlan: AttendanceMigrationPlan.self, configurations: ModelConfiguration(url: url))
        let store = AttendanceStore(container: reopened)
        XCTAssertEqual(store.salary.configuration?.monthlySalary, 42000)
        XCTAssertEqual(store.salary.snapshots.first?.month, "2026-10-01")
    }

    func testInvalidSalaryRestoreDoesNotChangeAttendance() throws {
        let store = try AttendanceStore.inMemory()
        try store.apply(entries: [salaryEntry("2026-10-01", .present)], strategy: .merge)
        var bad = SalaryArchive(); bad.configuration = salaryConfig(-1)
        XCTAssertThrowsError(try store.apply(entries: [], strategy: .replaceAll, salary: bad, restoreSalary: true))
        XCTAssertEqual(store.count, 1)
    }

    func testSalaryCSVContainsEstimates() throws {
        let store = try AttendanceStore.inMemory(), settings = settings()
        try store.saveSalary(configuration: salaryConfig(), settings: settings, now: salaryDate("2026-10-30"))
        let report = try XCTUnwrap(store.salaryReport(month: salaryDate("2026-10-01"), settings: settings))
        let csv = try ExportService.salaryCSVData(reports: [report])
        let text = String(decoding: csv, as: UTF8.self)
        XCTAssertTrue(text.contains("Estimated Net INR"))
        XCTAssertTrue(text.contains("30000"))
    }

    func testSalaryPDFHasOnePageAndFinancialDetails() throws {
        let store = try AttendanceStore.inMemory(), settings = settings()
        try store.saveSalary(configuration: salaryConfig(), settings: settings, now: salaryDate("2026-10-30"))
        let report = try XCTUnwrap(store.salaryReport(month: salaryDate("2026-10-01"), settings: settings))
        let url = try ReportService.makeSalaryPDF(report: report)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 1)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("Salary statement"))
        XCTAssertTrue(text.contains("ESTIMATE"))
        XCTAssertTrue(text.contains(Money.text(report.summary.net)))
        XCTAssertTrue(text.contains("not proof of payment"))
        XCTAssertFalse(text.contains("SAMPLE DATA"))
    }

    func testV1DatabaseMigratesWithoutLosingAttendance() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID()).store")
        do {
            let config = ModelConfiguration(url: url)
            let old = try ModelContainer(for: Schema(versionedSchema: AttendanceSchemaV1.self), configurations: config)
            let context = ModelContext(old)
            context.insert(AttendanceRecord(date: salaryDate("2026-10-01"), status: .present))
            try context.save()
        }
        let container = try ModelContainer(for: Schema(versionedSchema: AttendanceSchemaV2.self), migrationPlan: AttendanceMigrationPlan.self,
                                           configurations: ModelConfiguration(url: url))
        let store = AttendanceStore(container: container)
        XCTAssertEqual(store.count, 1)
        try store.saveSalary(configuration: salaryConfig(), settings: settings(), now: salaryDate("2026-10-30"))
        XCTAssertEqual(store.salary.configuration?.monthlySalary, 30000)
    }
}

@MainActor
final class CalendarHolidayTests: XCTestCase {
    private func settings() -> AttendanceSettings {
        AttendanceSettings(defaults: UserDefaults(suiteName: "holiday-\(UUID())")!)
    }

    func testMarkAndRemoveHolidayWithoutSalaryOrAttendance() throws {
        let store = try AttendanceStore.inMemory()
        let date = salaryDate("2026-10-01")
        try store.setPaidHoliday(on: date, enabled: true)
        XCTAssertTrue(store.isPaidHoliday(on: date))
        XCTAssertNil(store.salary.configuration)
        XCTAssertEqual(store.count, 0)
        let reopened = AttendanceStore(container: store.container)
        XCTAssertTrue(reopened.isPaidHoliday(on: date))
        try store.setPaidHoliday(on: date, enabled: false)
        XCTAssertFalse(store.isPaidHoliday(on: date))
        XCTAssertEqual(store.count, 0)
    }

    func testHistoricalCalendarHolidayAmendsHolidayRuleButKeepsSalaryAndAttendance() throws {
        let store = try AttendanceStore.inMemory(), settings = settings()
        try store.saveSalary(configuration: salaryConfig(22000), settings: settings, now: salaryDate("2026-10-02"))
        try store.save(date: salaryDate("2026-10-01"), status: .absent, reason: "Leave", notes: "", settings: settings, now: salaryDate("2026-10-02"))
        try store.saveSalary(configuration: salaryConfig(50000), settings: settings, now: salaryDate("2026-11-02"))
        try store.setPaidHoliday(on: salaryDate("2026-10-01"), enabled: true, now: salaryDate("2026-11-02"))
        let snapshot = try XCTUnwrap(store.salary.snapshots.first { $0.month == "2026-10-01" })
        XCTAssertEqual(snapshot.configuration.monthlySalary, 22000)
        XCTAssertEqual(snapshot.summary.gross, 1000)
        XCTAssertEqual(snapshot.summary.lost, 0)
        XCTAssertEqual(store.record(on: salaryDate("2026-10-01"))?.status, .absent)
        XCTAssertEqual(store.record(on: salaryDate("2026-10-01"))?.absenceReason, "Leave")
        try store.setPaidHoliday(on: salaryDate("2026-10-01"), enabled: false, now: salaryDate("2026-11-02"))
        XCTAssertEqual(store.salary.snapshots.first { $0.month == "2026-10-01" }?.summary.lost, 1000)
    }

    func testCalendarHolidaysRespectWorkingDaysAndFutureDates() throws {
        let store = try AttendanceStore.inMemory(), settings = settings()
        try store.saveSalary(configuration: salaryConfig(22000), settings: settings, now: salaryDate("2026-10-02"))
        try store.setPaidHoliday(on: salaryDate("2026-10-01"), enabled: true, now: salaryDate("2026-10-02"))
        try store.setPaidHoliday(on: salaryDate("2026-10-03"), enabled: true, now: salaryDate("2026-10-02"))
        try store.setPaidHoliday(on: salaryDate("2026-10-05"), enabled: true, now: salaryDate("2026-10-02"))
        let summary = try XCTUnwrap(store.salaryResult(month: salaryDate("2026-10-01"), settings: settings, now: salaryDate("2026-10-02")))
        XCTAssertEqual(summary.gross, 1000)
        XCTAssertEqual(summary.holidays, 1)
        XCTAssertEqual(summary.unmarked, 2)
        XCTAssertEqual(summary.lost, 0)
        XCTAssertEqual(store.count, 0)
    }

    func testMergedCalendarHolidayUpdatesMatchingSnapshotWithoutChangingSalary() throws {
        let source = try AttendanceStore.inMemory()
        try source.setPaidHoliday(on: salaryDate("2026-10-01"), enabled: true)
        let target = try AttendanceStore.inMemory()
        try target.saveSalary(configuration: salaryConfig(22000), settings: settings(), now: salaryDate("2026-10-30"))
        try target.apply(entries: [], strategy: .merge, salary: source.salary, restoreSalary: true)
        XCTAssertTrue(target.isPaidHoliday(on: salaryDate("2026-10-01")))
        let snapshot = try XCTUnwrap(target.salary.snapshots.first { $0.month == "2026-10-01" })
        XCTAssertEqual(snapshot.configuration.monthlySalary, 22000)
        XCTAssertEqual(snapshot.summary.gross, 1000)
        XCTAssertEqual(target.count, 0)
    }

    func testStandaloneHolidayBackupReplaceAndMerge() throws {
        let source = try AttendanceStore.inMemory()
        try source.setPaidHoliday(on: salaryDate("2026-10-01"), enabled: true)
        let data = try BackupService.generate(entries: [], settings: .default, salary: source.salary)
        let parsed = try BackupService.parse(data: data, requireFullBackup: true)
        let target = try AttendanceStore.inMemory()
        try target.apply(entries: [], strategy: .replaceAll, salary: parsed.salary, restoreSalary: true)
        XCTAssertTrue(target.isPaidHoliday(on: salaryDate("2026-10-01")))
        try target.setPaidHoliday(on: salaryDate("2026-10-02"), enabled: true)
        try target.apply(entries: [], strategy: .merge, salary: parsed.salary, restoreSalary: true)
        XCTAssertTrue(target.isPaidHoliday(on: salaryDate("2026-10-01")))
        XCTAssertTrue(target.isPaidHoliday(on: salaryDate("2026-10-02")))
        XCTAssertEqual(target.count, 0)
    }
}
