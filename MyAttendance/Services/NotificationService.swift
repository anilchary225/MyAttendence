import Foundation
import UserNotifications

/// Local-only reminders. Instead of one repeating notification (which can't know
/// whether you've already marked the day), we schedule non-repeating notifications
/// for the next few working days that are still unmarked, and reschedule whenever
/// the app opens or data changes. Marking today cancels today's pending reminder.
enum NotificationService {

    static let identifierPrefix = "myattendance.reminder."
    static let horizonDays = 14

    // MARK: - Planning (pure, unit-testable)

    /// Fire dates for reminders: working days, not marked, not before tracking start,
    /// and whose reminder time is still in the future.
    static func plannedFireDates(now: Date,
                                 workingWeekdays: Set<Int>,
                                 trackingStart: Date?,
                                 hour: Int,
                                 minute: Int,
                                 markedDates: Set<Date>,
                                 horizon: Int = horizonDays) -> [Date] {
        let cal = DateFormatting.calendar
        let today = DateFormatting.normalize(now)
        var result: [Date] = []
        for offset in 0..<horizon {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            guard workingWeekdays.contains(DateFormatting.weekday(of: day)) else { continue }
            if let start = trackingStart, day < DateFormatting.normalize(start) { continue }
            if markedDates.contains(day) { continue }
            guard let fire = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > now else { continue }
            result.append(fire)
        }
        return result
    }

    static func identifier(for fireDate: Date) -> String {
        identifierPrefix + DateFormatting.isoDay(fireDate)
    }

    // MARK: - Permission

    /// Called only when the user switches reminders on.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Scheduling

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Replaces all pending reminders. Does nothing (and clears) if reminders are off
    /// or permission isn't granted.
    static func reschedule(enabled: Bool,
                           workingWeekdays: Set<Int>,
                           trackingStart: Date?,
                           hour: Int,
                           minute: Int,
                           markedDates: Set<Date>,
                           now: Date = Date()) async {
        await cancelAll()
        guard enabled else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let center = UNUserNotificationCenter.current()
        let dates = plannedFireDates(now: now, workingWeekdays: workingWeekdays,
                                     trackingStart: trackingStart, hour: hour, minute: minute,
                                     markedDates: markedDates)
        for fire in dates {
            let content = UNMutableNotificationContent()
            content.title = "Mark today's attendance"
            content.body = "You haven't recorded attendance for today yet."
            content.sound = .default

            let comps = DateFormatting.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: identifier(for: fire), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Removes today's reminder right after attendance is saved.
    static func cancelReminder(for day: Date) {
        let id = identifierPrefix + DateFormatting.isoDay(day)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
