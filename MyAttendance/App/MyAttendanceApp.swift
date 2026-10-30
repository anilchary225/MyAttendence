import SwiftUI
import SwiftData

/// Builds the persistent store once. If the database can't be opened we show an
/// error screen instead of crashing or silently starting with empty data.
@MainActor
final class AppBootstrap: ObservableObject {
    let store: AttendanceStore?
    let errorMessage: String?

    init() {
        do {
            let container = try ModelContainer(for: Schema(versionedSchema: AttendanceSchemaV2.self),
                                               migrationPlan: AttendanceMigrationPlan.self)
            store = AttendanceStore(container: container)
            errorMessage = nil
        } catch {
            store = nil
            errorMessage = error.localizedDescription
        }
    }
}

@main
struct MyAttendanceApp: App {
    @StateObject private var bootstrap = AppBootstrap()
    @StateObject private var settings = AttendanceSettings()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            if let store = bootstrap.store {
                RootView()
                    .environmentObject(store)
                    .environmentObject(settings)
                    .environmentObject(router)
                    .preferredColorScheme(settings.appearance.colorScheme)
                    .tint(settings.accent.color)
            } else {
                StorageErrorView(message: bootstrap.errorMessage ?? "Unknown error")
            }
        }
    }
}

private struct StorageErrorView: View {
    let message: String
    var body: some View {
        EmptyStateView(
            systemImage: "externaldrive.badge.exclamationmark",
            title: "Couldn't open your attendance data",
            message: "Your data has not been changed or deleted. Restart the app; if this keeps happening, restore from a backup in Files.\n\n\(message)")
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLaunchSplash = true
    @State private var launchSplashOpacity = 1.0

    var body: some View {
        ZStack {
            appTabs
                .allowsHitTesting(!showLaunchSplash)
            if showLaunchSplash {
                LaunchSplashView()
                    .ignoresSafeArea()
                    .opacity(launchSplashOpacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: launchSplashOpacity)
                    .zIndex(10)
            }
        }
        .task {
            guard showLaunchSplash else { return }
            do {
                // Let the already-mounted tab and navigation controllers settle.
                try await Task.sleep(nanoseconds: 350_000_000)
                launchSplashOpacity = 0
                if !reduceMotion { try await Task.sleep(nanoseconds: 240_000_000) }
                // Removal is not animated: only the splash opacity ever changes.
                showLaunchSplash = false
            } catch { /* A cancelled root task must not dismiss a new launch. */ }
        }
        .sheet(item: $router.editorTarget) { target in
            AttendanceEditorView(date: target.date)
        }
        .overlay(alignment: .top) {
            if let toast = router.toast, !showLaunchSplash {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: router.toast)
        .task { synchronizeSalary(); await rescheduleReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { synchronizeSalary(); Task { await rescheduleReminders() } }
        }
        .onChange(of: store.count) { _, _ in Task { await rescheduleReminders() } }
        .onChange(of: reminderSignature) { _, _ in synchronizeSalary(); Task { await rescheduleReminders() } }
    }

    private var appTabs: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                .tag(AppTab.dashboard)
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.reports)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }

    private func synchronizeSalary() {
        do { try store.synchronizeSalary(settings: settings) }
        catch { router.showToast(error.localizedDescription) }
    }

    /// Changes whenever anything that affects reminder scheduling changes.
    private var reminderSignature: String {
        let days = settings.workingWeekdays.sorted().map(String.init).joined(separator: ",")
        let start = settings.trackingStartDate.map(DateFormatting.isoDay) ?? "-"
        return "\(settings.remindersEnabled)|\(settings.reminderHour):\(settings.reminderMinute)|\(days)|\(start)"
    }

    private func rescheduleReminders() async {
        await NotificationService.reschedule(
            enabled: settings.remindersEnabled,
            workingWeekdays: settings.workingWeekdays,
            trackingStart: settings.trackingStartDate,
            hour: settings.reminderHour,
            minute: settings.reminderMinute,
            markedDates: Set(store.records.map(\.date)))
    }
}
