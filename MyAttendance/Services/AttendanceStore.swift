import Foundation
import SwiftData
import SwiftUI

enum AttendanceError: LocalizedError, Equatable {
    case missingReason
    case notAllowed(String)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .missingReason:
            return "Please enter a reason for the absence."
        case .notAllowed(let message):
            return message
        case .persistence(let message):
            return "Couldn't save your attendance data: \(message)"
        }
    }
}

enum RestoreStrategy: String, CaseIterable, Identifiable {
    case replaceAll
    case merge
    var id: String { rawValue }
    var title: String { self == .replaceAll ? "Replace all records" : "Merge with existing" }
}

/// Outcome of comparing incoming entries with what's stored. Pure value type so
/// it can be previewed in the UI and unit-tested without SwiftData.
struct MergePlan: Equatable {
    var toAdd: [AttendanceEntry] = []
    var toReplace: [AttendanceEntry] = []     // incoming wins (newer updatedAt)
    var toKeep: [AttendanceEntry] = []        // existing retained (same or newer)
    var duplicatesInFile = 0

    var addCount: Int { toAdd.count }
    var replaceCount: Int { toReplace.count }
    var keepCount: Int { toKeep.count }
}

enum MergePlanner {
    /// Collapses duplicate dates inside the incoming list. The entry with the later
    /// `updatedAt` wins; on a tie the first occurrence is kept. Deterministic.
    static func dedupe(_ incoming: [AttendanceEntry]) -> (entries: [AttendanceEntry], duplicates: Int) {
        var byDate: [Date: AttendanceEntry] = [:]
        var order: [Date] = []
        var duplicates = 0
        for entry in incoming {
            let key = DateFormatting.normalize(entry.date)
            if let existing = byDate[key] {
                duplicates += 1
                if entry.updatedAt > existing.updatedAt { byDate[key] = entry }
            } else {
                byDate[key] = entry
                order.append(key)
            }
        }
        return (order.compactMap { byDate[$0] }, duplicates)
    }

    static func plan(existing: [AttendanceEntry], incoming: [AttendanceEntry]) -> MergePlan {
        let (unique, dupes) = dedupe(incoming)
        var existingByDate: [Date: AttendanceEntry] = [:]
        for e in existing { existingByDate[DateFormatting.normalize(e.date)] = e }

        var plan = MergePlan()
        plan.duplicatesInFile = dupes
        for entry in unique {
            let key = DateFormatting.normalize(entry.date)
            if let current = existingByDate[key] {
                if entry.updatedAt > current.updatedAt && !sameContent(entry, current) {
                    plan.toReplace.append(entry)
                } else {
                    plan.toKeep.append(current)
                }
            } else {
                plan.toAdd.append(entry)
            }
        }
        return plan
    }

    private static func sameContent(_ a: AttendanceEntry, _ b: AttendanceEntry) -> Bool {
        a.status == b.status && a.absenceReason == b.absenceReason && a.notes == b.notes
    }
}

/// Single source of truth for attendance data. Owns its own non-autosaving
/// `ModelContext` so multi-record operations are atomic: either `save()` succeeds
/// or `rollback()` leaves the database untouched.
@MainActor
final class AttendanceStore: ObservableObject {

    let container: ModelContainer
    private let context: ModelContext

    /// All records, newest first. Every tab reads this.
    @Published private(set) var salary = SalaryArchive()
    @Published private(set) var salaryLoadError: String?

    @Published private(set) var records: [AttendanceRecord] = []

    init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        reload()
    }

    /// In-memory store for previews and tests.
    static func inMemory() throws -> AttendanceStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AttendanceRecord.self, SalaryLedger.self, configurations: config)
        return AttendanceStore(container: container)
    }

    // MARK: - Fetch

    func reload() {
        let descriptor = FetchDescriptor<AttendanceRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        records = (try? context.fetch(descriptor)) ?? []
        do {
            if let ledger = try context.fetch(FetchDescriptor<SalaryLedger>()).first {
                salary = try JSONDecoder().decode(SalaryArchive.self, from: ledger.payload)
                try salary.validate()
            } else { salary = SalaryArchive() }
            salaryLoadError = nil
        } catch { salaryLoadError = "Couldn't read salary data: \(error.localizedDescription)" }
    }

    var count: Int { records.count }

    func record(on date: Date) -> AttendanceRecord? {
        let key = DateFormatting.normalize(date)
        return records.first { $0.date == key }
    }

    func hasRecord(on date: Date) -> Bool { record(on: date) != nil }

    func entries() -> [AttendanceEntry] {
        records.map(AttendanceEntry.init)
    }

    func entries(from start: Date, to end: Date) -> [AttendanceEntry] {
        let s = DateFormatting.normalize(start), e = DateFormatting.normalize(end)
        return records.filter { $0.date >= s && $0.date <= e }.map(AttendanceEntry.init)
    }

    // MARK: - Validation

    /// Pure validation used by the editor and the import services.
    nonisolated static func validate(status: AttendanceStatus, reason: String, requireReason: Bool) throws {
        if status == .absent && requireReason &&
            reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AttendanceError.missingReason
        }
    }

    // MARK: - Add / update (upsert by normalized date)

    /// Creates a record or updates the existing one for that date. Never inserts a duplicate.
    @discardableResult
    func save(date: Date,
              status: AttendanceStatus,
              reason: String,
              notes: String,
              settings: AttendanceSettings,
              now: Date = Date()) throws -> AttendanceRecord {
        let key = DateFormatting.normalize(date)
        let existing = record(on: key)

        // New entries must obey working-day/future/tracking rules; editing an
        // imported weekend record is allowed so it can be corrected.
        if existing == nil, let block = settings.recordingBlockReason(for: key, now: now) {
            throw AttendanceError.notAllowed(block)
        }
        if DateFormatting.isFuture(key, now: now) {
            throw AttendanceError.notAllowed("Attendance can't be recorded for future dates.")
        }
        try Self.validate(status: status, reason: reason, requireReason: settings.requireAbsenceReason)

        let cleanReason = status == .absent ? reason.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let cleanNotes = settings.notesEnabled || existing != nil
            ? notes.trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let result: AttendanceRecord
        if let existing {
            existing.status = status
            existing.absenceReason = cleanReason
            existing.notes = cleanNotes
            existing.updatedAt = now
            result = existing
        } else {
            let new = AttendanceRecord(date: key, status: status, absenceReason: cleanReason,
                                       notes: cleanNotes, createdAt: now, updatedAt: now)
            context.insert(new)
            result = new
        }
        try commit(now: now)
        return result
    }

    // MARK: - Delete

    func delete(_ record: AttendanceRecord) throws {
        context.delete(record)
        try commit()
    }

    func deleteAll() throws {
        for r in records { context.delete(r) }
        try commit()
    }

    // MARK: - Bulk apply (restore / import)

    /// Applies entries atomically. On any failure the context is rolled back and
    /// existing data is left exactly as it was.
    @discardableResult
    func apply(entries incoming: [AttendanceEntry], strategy: RestoreStrategy,
               salary incomingSalary: SalaryArchive? = nil, restoreSalary: Bool = false) throws -> MergePlan {
        try incomingSalary?.validate()
        let existing = entries()
        let plan: MergePlan
        switch strategy {
        case .replaceAll:
            let (unique, dupes) = MergePlanner.dedupe(incoming)
            var p = MergePlan()
            p.toAdd = unique
            p.duplicatesInFile = dupes
            plan = p
        case .merge:
            plan = MergePlanner.plan(existing: existing, incoming: incoming)
        }

        if strategy == .replaceAll {
            for r in records { context.delete(r) }
        }
        for entry in plan.toAdd { context.insert(Self.makeRecord(entry)) }
        if strategy == .merge {
            for entry in plan.toReplace {
                guard let target = record(on: entry.date) else { continue }
                target.status = entry.status
                target.absenceReason = entry.absenceReason
                target.notes = entry.notes
                target.createdAt = min(target.createdAt, entry.createdAt)
                target.updatedAt = entry.updatedAt
            }
        }
        do {
            if restoreSalary {
                var archive = salary
                if strategy == .replaceAll { archive = incomingSalary ?? SalaryArchive() }
                else if let incomingSalary {
                    // Merge retains local period rules and current settings; adds missing periods.
                    if archive.configuration == nil {
                        archive.configuration = incomingSalary.configuration
                        archive.effectiveMonth = incomingSalary.effectiveMonth
                    }
                    let localHolidays = archive.calendarHolidays ?? archive.configuration?.paidHolidays ?? []
                    let incomingHolidays = incomingSalary.calendarHolidays ?? incomingSalary.configuration?.paidHolidays ?? []
                    archive.calendarHolidays = Array(Set(localHolidays + incomingHolidays)).sorted()
                    let keys = Set(archive.snapshots.map(\.month))
                    archive.snapshots += incomingSalary.snapshots.filter { !keys.contains($0.month) }
                    // Calendar holiday dates merge as explicit date edits. Preserve
                    // all other saved salary rules, including monthly amounts.
                    for index in archive.snapshots.indices {
                        let snapshot = archive.snapshots[index]
                        let period = SalaryCalculator.period(DateFormatting.parseIsoDay(snapshot.month)!, configuration: snapshot.configuration)
                        let added = (archive.calendarHolidays ?? []).filter {
                            guard let date = DateFormatting.parseIsoDay($0) else { return false }
                            return date >= period.start && date <= period.end
                        }
                        archive.snapshots[index].configuration.paidHolidays = Array(Set(snapshot.configuration.paidHolidays + added)).sorted()
                    }
                    if var config = archive.configuration {
                        config.paidHolidays = archive.calendarHolidays ?? config.paidHolidays
                        archive.configuration = config
                    }
                }
                try stageSalary(archive)
            }
            try commit()
        } catch { context.rollback(); reload(); throw error }
        return plan
    }

    private static func makeRecord(_ e: AttendanceEntry) -> AttendanceRecord {
        AttendanceRecord(date: e.date, status: e.status, absenceReason: e.absenceReason,
                         notes: e.notes, createdAt: e.createdAt, updatedAt: e.updatedAt)
    }

    // MARK: - Summaries

    func summary(from start: Date, to end: Date, settings: AttendanceSettings, now: Date = Date()) -> AttendanceSummary {
        AttendanceCalculator.summary(entries: entries(), from: start, to: end,
                                     rules: AttendanceRules(settings: settings, now: now))
    }

    func monthSummary(_ month: Date, settings: AttendanceSettings, now: Date = Date()) -> AttendanceSummary {
        summary(from: DateFormatting.startOfMonth(month), to: DateFormatting.endOfMonth(month),
                settings: settings, now: now)
    }

    // MARK: - Salary settings and period history

    func salaryConfiguration(settings: AttendanceSettings) -> SalaryConfiguration? {
        guard var config = salary.configuration?.usingAttendance(settings) else { return nil }
        config.paidHolidays = salary.calendarHolidays ?? config.paidHolidays
        return config
    }

    func isPaidHoliday(on date: Date) -> Bool {
        let key = DateFormatting.isoDay(date)
        if let snapshot = salary.snapshots.first(where: {
            let period = SalaryCalculator.period(DateFormatting.parseIsoDay($0.month)!, configuration: $0.configuration)
            return date >= period.start && DateFormatting.normalize(date) <= period.end
        }) { return snapshot.configuration.paidHolidays.contains(key) }
        return (salary.calendarHolidays ?? salary.configuration?.paidHolidays ?? []).contains(key)
    }

    /// Explicit calendar holiday edits amend only the holiday rule of matching
    /// snapshots. Their saved salary, method, schedule and adjustments stay fixed.
    func setPaidHoliday(on date: Date, enabled: Bool, now: Date = Date()) throws {
        if let error = salaryLoadError { throw SalaryError.invalid(error) }
        let key = DateFormatting.isoDay(date)
        var archive = salary
        var holidays = Set(archive.calendarHolidays ?? archive.configuration?.paidHolidays ?? [])
        if enabled { holidays.insert(key) } else { holidays.remove(key) }
        archive.calendarHolidays = holidays.sorted()
        if var config = archive.configuration {
            config.paidHolidays = holidays.sorted()
            archive.configuration = config
        }
        for index in archive.snapshots.indices {
            let snapshot = archive.snapshots[index]
            let period = SalaryCalculator.period(DateFormatting.parseIsoDay(snapshot.month)!, configuration: snapshot.configuration)
            guard DateFormatting.normalize(date) >= period.start && DateFormatting.normalize(date) <= period.end else { continue }
            var savedHolidays = Set(snapshot.configuration.paidHolidays)
            if enabled { savedHolidays.insert(key) } else { savedHolidays.remove(key) }
            archive.snapshots[index].configuration.paidHolidays = savedHolidays.sorted()
        }
        try saveSalaryArchive(archive, now: now)
    }

    func salaryResult(month: Date, settings: AttendanceSettings, now: Date = Date()) throws -> SalarySummary? {
        if let error = salaryLoadError { throw SalaryError.invalid(error) }
        let key = SalaryCalculator.monthKey(month)
        guard let config = salary.snapshots.first(where: { $0.month == key })?.configuration
                ?? salaryConfiguration(settings: settings) else { return nil }
        return try SalaryCalculator.calculate(month: month, configuration: config, entries: entries(), now: now)
    }

    /// Backfills only periods for which the app actually knew the salary rules.
    /// Earlier months stay explicitly labelled as estimates using current settings.
    private func capturingPeriods(_ original: SalaryArchive, now: Date) throws -> SalaryArchive {
        var archive = original
        guard let config = archive.configuration,
              let first = archive.effectiveMonth.flatMap(DateFormatting.parseIsoDay) else { return archive }
        let active = SalaryCalculator.activeMonth(configuration: config, now: now)
        var cursor = first
        var count = 0
        while cursor <= active {
            guard count < 2400 else { throw SalaryError.invalid("Salary history exceeds 200 years.") }
            let key = SalaryCalculator.monthKey(cursor)
            if !archive.snapshots.contains(where: { $0.month == key }) {
                let summary = try SalaryCalculator.calculate(month: cursor, configuration: config, entries: entries(), now: now)
                archive.snapshots.append(SalarySnapshot(month: key, configuration: config, summary: summary, savedAt: now))
            }
            cursor = DateFormatting.addingMonths(1, to: cursor)
            count += 1
        }
        return archive
    }

    func synchronizeSalary(settings: AttendanceSettings, now: Date = Date()) throws {
        if let error = salaryLoadError { throw SalaryError.invalid(error) }
        guard let config = salaryConfiguration(settings: settings) else { return }
        var archive = try capturingPeriods(salary, now: now)
        archive.configuration = config
        try updateOpenPeriod(&archive, configuration: config, now: now)
        if archive != salary { try saveSalaryArchive(archive, now: now) }
    }

    func saveSalary(configuration: SalaryConfiguration, settings: AttendanceSettings, now: Date = Date()) throws {
        if let error = salaryLoadError { throw SalaryError.invalid(error) }
        let config = configuration.usingAttendance(settings)
        if let existing = salary.configuration, existing.periodStartDay != config.periodStartDay {
            throw SalaryError.invalid("The salary period start day is fixed after setup to prevent overlapping saved periods.")
        }
        if let message = config.validationMessage { throw SalaryError.invalid(message) }
        var archive = try capturingPeriods(salary, now: now)
        archive.configuration = config
        archive.calendarHolidays = config.paidHolidays
        archive.effectiveMonth = SalaryCalculator.monthKey(SalaryCalculator.activeMonth(configuration: config, now: now))
        try updateOpenPeriod(&archive, configuration: config, now: now)
        try saveSalaryArchive(archive, now: now)
    }

    private func updateOpenPeriod(_ archive: inout SalaryArchive, configuration: SalaryConfiguration, now: Date) throws {
        let active = SalaryCalculator.activeMonth(configuration: configuration, now: now)
        let key = SalaryCalculator.monthKey(active)
        // A period already closed under its saved rules is never overwritten.
        if let existing = archive.snapshots.first(where: { $0.month == key }),
           SalaryCalculator.period(active, configuration: existing.configuration).end < DateFormatting.normalize(now) { return }
        let summary = try SalaryCalculator.calculate(month: active, configuration: configuration, entries: entries(), now: now)
        let savedAt = archive.snapshots.first(where: { $0.month == key })?.savedAt ?? now
        archive.snapshots.removeAll { $0.month == key }
        archive.snapshots.append(SalarySnapshot(month: key, configuration: configuration, summary: summary,
                                                savedAt: savedAt))
    }

    func saveHistoricalSalary(month: Date, settings: AttendanceSettings, now: Date = Date()) throws {
        guard let config = salaryConfiguration(settings: settings) else { return }
        let key = SalaryCalculator.monthKey(month)
        guard !salary.snapshots.contains(where: { $0.month == key }) else { return }
        var archive = salary
        let summary = try SalaryCalculator.calculate(month: month, configuration: config, entries: entries(), now: now)
        archive.snapshots.append(SalarySnapshot(month: key, configuration: config, summary: summary, savedAt: now))
        try saveSalaryArchive(archive, now: now)
    }

    private func stageSalary(_ archive: SalaryArchive) throws {
        try archive.validate()
        let payload = try JSONEncoder().encode(archive)
        if let ledger = try context.fetch(FetchDescriptor<SalaryLedger>()).first { ledger.payload = payload }
        else { context.insert(SalaryLedger(payload: payload)) }
    }

    private func saveSalaryArchive(_ archive: SalaryArchive, now: Date) throws {
        do { try stageSalary(archive); try commit(now: now) }
        catch { context.rollback(); reload(); throw error }
    }

    // MARK: - Persistence

    private func commit(now: Date = Date()) throws {
        do {
            if let error = salaryLoadError { throw SalaryError.invalid(error) }
            if let ledger = try context.fetch(FetchDescriptor<SalaryLedger>()).first {
                var archive = try JSONDecoder().decode(SalaryArchive.self, from: ledger.payload)
                let all = try context.fetch(FetchDescriptor<AttendanceRecord>()).map(AttendanceEntry.init)
                for index in archive.snapshots.indices {
                    let snapshot = archive.snapshots[index]
                    archive.snapshots[index].summary = try SalaryCalculator.calculate(
                        month: DateFormatting.parseIsoDay(snapshot.month)!, configuration: snapshot.configuration,
                        entries: all, now: now)
                }
                try stageSalary(archive)
            }
            try context.save()
            reload()
        } catch {
            context.rollback()
            reload()
            throw AttendanceError.persistence(error.localizedDescription)
        }
    }
}
