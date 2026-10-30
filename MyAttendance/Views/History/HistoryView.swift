import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @EnvironmentObject private var router: AppRouter

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All", present = "Present", absent = "Absent"
        var id: String { rawValue }
    }

    @State private var statusFilter: StatusFilter = .all
    @State private var year: Int?
    @State private var month: Int?
    @State private var search = ""
    @State private var newestFirst = true
    @State private var pendingDelete: Date?
    @State private var errorMessage: String?

    private var years: [Int] {
        Array(Set(store.records.map { DateFormatting.yearNumber($0.date) })).sorted(by: >)
    }

    private var filtered: [AttendanceEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = store.records.map(AttendanceEntry.init).filter { entry in
            switch statusFilter {
            case .all: break
            case .present: if entry.status != .present { return false }
            case .absent: if entry.status != .absent { return false }
            }
            if let year, DateFormatting.yearNumber(entry.date) != year { return false }
            if let month, DateFormatting.monthNumber(entry.date) != month { return false }
            if !query.isEmpty {
                let hit = entry.absenceReason.localizedCaseInsensitiveContains(query)
                    || entry.notes.localizedCaseInsensitiveContains(query)
                if !hit { return false }
            }
            return true
        }
        return list.sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
    }

    private var hasActiveFilters: Bool {
        statusFilter != .all || year != nil || month != nil || !search.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                let items = filtered
                if store.records.isEmpty {
                    EmptyStateView(systemImage: "tray",
                                   title: "No attendance yet",
                                   message: "Mark today from the Dashboard, or tap a date in the Calendar. You can also import records from Settings.",
                                   actionTitle: "Open Calendar") { router.selectedTab = .calendar }
                        .listRowBackground(Color.clear)
                } else if items.isEmpty {
                    EmptyStateView(systemImage: "magnifyingglass",
                                   title: "No matching records",
                                   message: "Try a different search or clear the filters.",
                                   actionTitle: "Clear Filters", action: clearFilters)
                        .listRowBackground(Color.clear)
                } else {
                    Section("\(items.count) record\(items.count == 1 ? "" : "s")") {
                        ForEach(items, id: \.date) { entry in
                            Button { router.openEditor(for: entry.date) } label: { RecordRow(entry: entry) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { pendingDelete = entry.date } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { router.openEditor(for: entry.date) } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }.tint(.accentColor)
                                }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .searchable(text: $search, prompt: "Search reasons and notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .confirmationDialog("Delete this record?",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Record", role: .destructive) { deletePending() }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                if let d = pendingDelete { Text("\(DateFormatting.fullDate(d)) will go back to Not Marked.") }
            }
            .alert("Couldn't delete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort", selection: $newestFirst) {
                Text("Newest first").tag(true)
                Text("Oldest first").tag(false)
            }
            Picker("Year", selection: $year) {
                Text("All years").tag(Int?.none)
                ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            Picker("Month", selection: $month) {
                Text("All months").tag(Int?.none)
                ForEach(1...12, id: \.self) { m in
                    Text(DateFormatting.calendar.monthSymbols[m - 1]).tag(Int?.some(m))
                }
            }
            if hasActiveFilters {
                Button("Clear Filters", systemImage: "xmark.circle", action: clearFilters)
            }
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill"
                                               : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Sort and filter")
    }

    private func clearFilters() {
        statusFilter = .all; year = nil; month = nil; search = ""
    }

    private func deletePending() {
        guard let date = pendingDelete, let record = store.record(on: date) else { pendingDelete = nil; return }
        pendingDelete = nil
        do {
            try store.delete(record)
            Haptics.success(enabled: settings.hapticsEnabled)
            router.showToast("Record deleted")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
