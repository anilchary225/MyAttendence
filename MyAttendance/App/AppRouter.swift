import SwiftUI

enum AppTab: Hashable {
    case dashboard, calendar, history, reports, settings
}

/// Identifiable wrapper so one root-level sheet can present the editor for any date.
struct EditorTarget: Identifiable, Equatable {
    let date: Date
    var id: Date { date }
}

/// Cross-tab navigation and lightweight feedback ("Saved") shared by all tabs.
@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .dashboard
    @Published var editorTarget: EditorTarget?
    @Published var showBackupScreen = false
    @Published var toast: String?

    func openEditor(for date: Date) {
        editorTarget = EditorTarget(date: DateFormatting.normalize(date))
    }

    func openBackup() {
        selectedTab = .settings
        showBackupScreen = true
    }

    func showToast(_ message: String) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self?.toast == message { self?.toast = nil }
        }
    }
}
