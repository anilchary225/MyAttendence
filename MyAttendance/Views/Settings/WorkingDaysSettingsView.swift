import SwiftUI

/// Shared by Attendance Settings and Salary Settings; there is only one schedule.
struct WorkingDaysSettingsView: View {
    @EnvironmentObject private var settings: AttendanceSettings
    private let weekdays: [(name: String, number: Int)] = [
        ("Monday", 2), ("Tuesday", 3), ("Wednesday", 4), ("Thursday", 5),
        ("Friday", 6), ("Saturday", 7), ("Sunday", 1)
    ]

    var body: some View {
        Form {
            Section {
                ForEach(weekdays, id: \.number) { day in
                    Toggle(day.name, isOn: Binding(
                        get: { settings.workingWeekdays.contains(day.number) },
                        set: { on in
                            var days = settings.workingWeekdays
                            if on { days.insert(day.number) }
                            else if days.count > 1 { days.remove(day.number) }
                            settings.workingWeekdays = days
                        }))
                }
            } footer: {
                Text("At least one working day is required. Attendance and salary use this same schedule. Existing non-working-day records remain visible; closed salary snapshots retain their saved schedules.")
            }
            Section {
                Button("Reset to Monday–Friday") {
                    settings.workingWeekdays = AttendanceSettings.defaultWorkingWeekdays
                }
            }
        }
        .navigationTitle("Work Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}
