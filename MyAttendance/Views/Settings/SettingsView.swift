import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @EnvironmentObject private var router: AppRouter

    @State private var showClearConfirm = false
    @State private var clearAcknowledged = false
    @State private var errorMessage: String?
    @State private var notificationsDenied = false

    // Mon…Sun order with Foundation weekday numbers (1 = Sunday).
    private let weekdayOrder: [(name: String, number: Int)] = [
        ("Monday", 2), ("Tuesday", 3), ("Wednesday", 4), ("Thursday", 5),
        ("Friday", 6), ("Saturday", 7), ("Sunday", 1)
    ]

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                Section("Salary") {
                    NavigationLink("Salary Settings") { SalarySettingsView() }
                    NavigationLink("Salary Tracker") { SalaryTrackerView() }
                }
                attendanceSection
                remindersSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $router.showBackupScreen) {
                BackupRestoreView()
            }
            .confirmationDialog("Clear all attendance data?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Delete \(store.count) Records", role: .destructive, action: clearAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every attendance record on this iPhone. Create a backup first — it can't be undone.")
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .alert("Notifications are off", isPresented: $notificationsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allow notifications for MyAttendance in iOS Settings to receive reminders.")
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            NavigationLink {
                accentColorScreen
            } label: {
                HStack {
                    Text("Accent color")
                    Spacer()
                    Circle().fill(settings.accent.color).frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(settings.accent.title).foregroundStyle(.secondary)
                }
            }
            Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
        }
    }

    private var accentColorScreen: some View {
        List {
            Section {
                ForEach(AccentChoice.allCases) { choice in
                    Button {
                        settings.accent = choice
                        Haptics.tap(enabled: settings.hapticsEnabled)
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(choice.color.gradient)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                                .accessibilityHidden(true)
                            Text(choice.title).foregroundStyle(.primary)
                            Spacer()
                            if settings.accent == choice {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(choice.color)
                            }
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(settings.accent == choice ? .isSelected : [])
                }
            } footer: {
                Text("Choose the color used for buttons and highlights throughout the app.")
            }
        }
        .navigationTitle("Accent Color")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Attendance

    private var attendanceSection: some View {
        Section {
            NavigationLink {
                WorkingDaysSettingsView()
            } label: {
                LabeledContent("Work schedule", value: scheduleSummary)
            }
            LabeledContent("Week starts", value: "Monday")
            Toggle("Require absence reason", isOn: $settings.requireAbsenceReason)
            Toggle("Notes field", isOn: $settings.notesEnabled)

            Toggle("Set first tracking day", isOn: Binding(
                get: { settings.trackingStartDate != nil },
                set: { settings.trackingStartDate = $0 ? DateFormatting.normalize(Date()) : nil }))
            if settings.trackingStartDate != nil {
                DatePicker("First day",
                           selection: Binding(get: { settings.trackingStartDate ?? Date() },
                                              set: { settings.trackingStartDate = DateFormatting.normalize($0) }),
                           in: ...Date(), displayedComponents: .date)
            }
            Picker("Default calendar view", selection: $settings.defaultCalendarLayout) {
                ForEach(CalendarLayout.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Attendance")
        } footer: {
            Text("Only working days count toward your percentage. Weekends are never marked automatically, and days before your first tracking day are ignored.")
        }
    }

    private var scheduleSummary: String {
        if settings.workingWeekdays == AttendanceSettings.defaultWorkingWeekdays { return "Mon–Fri" }
        let names = weekdayOrder.filter { settings.workingWeekdays.contains($0.number) }.map { String($0.name.prefix(3)) }
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            Toggle("Remind me to mark attendance", isOn: Binding(
                get: { settings.remindersEnabled },
                set: { setReminders($0) }))
            if settings.remindersEnabled {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Off by default. Reminders are local to this iPhone, skip non-working days, and stop for any day you've already marked. They never mark attendance for you.")
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                DateFormatting.calendar.date(bySettingHour: settings.reminderHour,
                                             minute: settings.reminderMinute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = DateFormatting.calendar.dateComponents([.hour, .minute], from: date)
                settings.reminderHour = c.hour ?? 18
                settings.reminderMinute = c.minute ?? 0
            })
    }

    private func setReminders(_ on: Bool) {
        guard on else {
            settings.remindersEnabled = false     // RootView cancels pending reminders immediately
            return
        }
        Task {
            // Permission is requested only now, when the user turns reminders on.
            let granted = await NotificationService.requestAuthorization()
            await MainActor.run {
                settings.remindersEnabled = granted
                if !granted { notificationsDenied = true }
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            NavigationLink {
                BackupRestoreView()
            } label: {
                Label("Backup, Restore & Export", systemImage: "externaldrive")
            }
            LabeledContent("Attendance records", value: "\(store.count)")
            LabeledContent("Last backup") {
                if let d = settings.lastBackupDate {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
            Button("Clear All Attendance Data…", role: .destructive) { showClearConfirm = true }
                .disabled(store.count == 0)
        } header: {
            Text("Data")
        } footer: {
            Text("Back up before clearing. Clearing removes records only; your settings are kept.")
        }
    }

    private func clearAll() {
        do {
            try store.deleteAll()
            Haptics.warning(enabled: settings.hapticsEnabled)
            router.showToast("All attendance data cleared")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "MyAttendance")
            LabeledContent("Version", value: "\(BackupService.appVersion) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
            NavigationLink("Privacy & Storage") {
                aboutText(title: "Privacy & Storage", text: """
                All attendance data is stored only on this iPhone using SwiftData. MyAttendance has no account, no server, no analytics and no ads, and works fully offline.

                Nothing leaves your device unless you choose to export, back up or share a file.
                """)
            }
            NavigationLink("How Backup & Restore Work") {
                aboutText(title: "Backup & Restore", text: """
                Create Backup produces a versioned JSON file with all records and attendance settings. Save it to Files or share it — you choose where it goes, and existing files are never overwritten silently.

                Restore reads a backup, validates every record, and shows a preview. You then choose Replace (a safety backup of current data is saved first) or Merge (matching dates are compared; the newer entry wins). If anything fails, your existing data is left untouched.

                Deleting the app deletes its data, so keep a backup in Files or iCloud Drive.
                """)
            }
        }
    }

    private func aboutText(title: String, text: String) -> some View {
        ScrollView {
            Text(text).padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
