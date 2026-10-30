import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable, Codable {
    case blue, indigo, teal, orange, pink
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .teal: return .teal
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}

enum CalendarLayout: String, CaseIterable, Identifiable, Codable {
    case grid, list
    var id: String { rawValue }
    var title: String { self == .grid ? "Month grid" : "Day list" }
}

/// The subset of settings that travel inside a backup. Reminder permission,
/// appearance and haptics are device preferences and are not restored.
struct SettingsSnapshot: Codable, Equatable {
    var workingWeekdays: [Int]
    var requireAbsenceReason: Bool
    var notesEnabled: Bool
    var trackingStartDate: String?   // yyyy-MM-dd
    var defaultCalendarLayout: CalendarLayout
    var reminderHour: Int
    var reminderMinute: Int

    static let `default` = SettingsSnapshot(
        workingWeekdays: [2, 3, 4, 5, 6],
        requireAbsenceReason: true,
        notesEnabled: true,
        trackingStartDate: nil,
        defaultCalendarLayout: .grid,
        reminderHour: 18,
        reminderMinute: 0
    )
}

/// UserDefaults-backed settings shared by every tab. Changes persist immediately.
final class AttendanceSettings: ObservableObject {

    static let defaultWorkingWeekdays: Set<Int> = [2, 3, 4, 5, 6] // Mon–Fri

    private let defaults: UserDefaults

    private enum Key {
        static let appearance = "settings.appearance"
        static let accent = "settings.accent"
        static let haptics = "settings.haptics"
        static let workingWeekdays = "settings.workingWeekdays"
        static let requireReason = "settings.requireReason"
        static let notesEnabled = "settings.notesEnabled"
        static let trackingStart = "settings.trackingStart"
        static let calendarLayout = "settings.calendarLayout"
        static let reminderEnabled = "settings.reminderEnabled"
        static let reminderHour = "settings.reminderHour"
        static let reminderMinute = "settings.reminderMinute"
        static let lastBackup = "settings.lastBackup"
    }

    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    @Published var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: Key.accent) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    @Published var workingWeekdays: Set<Int> {
        didSet { defaults.set(workingWeekdays.sorted(), forKey: Key.workingWeekdays) }
    }
    @Published var requireAbsenceReason: Bool { didSet { defaults.set(requireAbsenceReason, forKey: Key.requireReason) } }
    @Published var notesEnabled: Bool { didSet { defaults.set(notesEnabled, forKey: Key.notesEnabled) } }
    @Published var trackingStartDate: Date? {
        didSet {
            if let d = trackingStartDate {
                defaults.set(DateFormatting.isoDay(d), forKey: Key.trackingStart)
            } else {
                defaults.removeObject(forKey: Key.trackingStart)
            }
        }
    }
    @Published var defaultCalendarLayout: CalendarLayout { didSet { defaults.set(defaultCalendarLayout.rawValue, forKey: Key.calendarLayout) } }
    @Published var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: Key.reminderEnabled) } }
    @Published var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: Key.reminderHour) } }
    @Published var reminderMinute: Int { didSet { defaults.set(reminderMinute, forKey: Key.reminderMinute) } }
    @Published var lastBackupDate: Date? {
        didSet { defaults.set(lastBackupDate, forKey: Key.lastBackup) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        accent = AccentChoice(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .blue
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        if let stored = defaults.array(forKey: Key.workingWeekdays) as? [Int], !stored.isEmpty {
            workingWeekdays = Set(stored.filter { (1...7).contains($0) })
        } else {
            workingWeekdays = Self.defaultWorkingWeekdays
        }
        requireAbsenceReason = defaults.object(forKey: Key.requireReason) as? Bool ?? true
        notesEnabled = defaults.object(forKey: Key.notesEnabled) as? Bool ?? true
        if let s = defaults.string(forKey: Key.trackingStart) {
            trackingStartDate = DateFormatting.parseIsoDay(s)
        } else {
            trackingStartDate = nil
        }
        defaultCalendarLayout = CalendarLayout(rawValue: defaults.string(forKey: Key.calendarLayout) ?? "") ?? .grid
        remindersEnabled = defaults.bool(forKey: Key.reminderEnabled)
        reminderHour = defaults.object(forKey: Key.reminderHour) as? Int ?? 18
        reminderMinute = defaults.object(forKey: Key.reminderMinute) as? Int ?? 0
        lastBackupDate = defaults.object(forKey: Key.lastBackup) as? Date
    }

    // MARK: - Working-day rules

    func isWorkingDay(_ date: Date) -> Bool {
        workingWeekdays.contains(DateFormatting.weekday(of: date))
    }

    /// True when the date is on/after the first tracking day (if one is set).
    func isTracked(_ date: Date) -> Bool {
        guard let start = trackingStartDate else { return true }
        return DateFormatting.normalize(date) >= DateFormatting.normalize(start)
    }

    /// Whether the user may create a *new* entry for this date.
    func canRecord(on date: Date, now: Date = Date()) -> Bool {
        isWorkingDay(date) && !DateFormatting.isFuture(date, now: now) && isTracked(date)
    }

    func recordingBlockReason(for date: Date, now: Date = Date()) -> String? {
        if DateFormatting.isFuture(date, now: now) { return "Attendance can't be recorded for future dates." }
        if !isWorkingDay(date) { return "This isn't one of your working days." }
        if !isTracked(date) { return "This date is before your first tracking day." }
        return nil
    }

    // MARK: - Backup snapshot

    var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            workingWeekdays: workingWeekdays.sorted(),
            requireAbsenceReason: requireAbsenceReason,
            notesEnabled: notesEnabled,
            trackingStartDate: trackingStartDate.map(DateFormatting.isoDay),
            defaultCalendarLayout: defaultCalendarLayout,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
    }

    func apply(_ snapshot: SettingsSnapshot) {
        let valid = Set(snapshot.workingWeekdays.filter { (1...7).contains($0) })
        if !valid.isEmpty { workingWeekdays = valid }
        requireAbsenceReason = snapshot.requireAbsenceReason
        notesEnabled = snapshot.notesEnabled
        trackingStartDate = snapshot.trackingStartDate.flatMap(DateFormatting.parseIsoDay)
        defaultCalendarLayout = snapshot.defaultCalendarLayout
        if (0...23).contains(snapshot.reminderHour) { reminderHour = snapshot.reminderHour }
        if (0...59).contains(snapshot.reminderMinute) { reminderMinute = snapshot.reminderMinute }
    }
}
