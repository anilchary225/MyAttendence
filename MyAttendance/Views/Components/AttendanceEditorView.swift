import SwiftUI

/// Reusable attendance editor, presented as a sheet by the root view.
/// A date with no record starts "Not Marked"; nothing is saved until you choose a status and tap Save.
struct AttendanceEditorView: View {
    let date: Date

    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var status: AttendanceStatus?
    @State private var reason = ""
    @State private var notes = ""
    @State private var original: Snapshot?
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var showDiscard = false
    @State private var showDelete = false
    @FocusState private var reasonFocused: Bool

    private struct Snapshot: Equatable {
        var status: AttendanceStatus?
        var reason: String
        var notes: String
    }

    static let suggestions = ["Sick leave", "Personal reasons", "Family emergency",
                              "Public holiday", "Travel", "Work from home", "Other"]

    private var existing: AttendanceRecord? { store.record(on: date) }
    private var blockReason: String? {
        existing == nil ? settings.recordingBlockReason(for: date) : nil
    }
    private var current: Snapshot { Snapshot(status: status, reason: reason, notes: notes) }
    private var isDirty: Bool { loaded && current != original }
    private var reasonIsRequired: Bool { status == .absent && settings.requireAbsenceReason }
    private var reasonMissing: Bool {
        reasonIsRequired && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canSave: Bool { blockReason == nil && status != nil && !reasonMissing && isDirty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Date") {
                        Text(DateFormatting.fullDate(date))
                            .multilineTextAlignment(.trailing)
                    }
                    if DateFormatting.isSameDay(date, Date()) {
                        Label("Today", systemImage: "sun.max").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        do {
                            let enabled = !store.isPaidHoliday(on: date)
                            try store.setPaidHoliday(on: date, enabled: enabled)
                            router.showToast(enabled ? "Paid holiday saved" : "Paid holiday removed")
                            errorMessage = nil
                        } catch { errorMessage = error.localizedDescription }
                    } label: {
                        Label(store.isPaidHoliday(on: date) ? "Remove Paid Holiday" : "Mark as Paid Holiday",
                              systemImage: store.isPaidHoliday(on: date) ? "sun.max.fill" : "sun.max")
                    }
                    .disabled(store.salaryLoadError != nil)
                    if store.isPaidHoliday(on: date) {
                        Label("Paid holiday", systemImage: "sun.max.fill").foregroundStyle(.orange)
                    }
                } header: { Text("Holiday") } footer: {
                    Text("Holiday changes save immediately, separately from attendance. Holidays do not mark Present or Absent. Salary pays eligible scheduled working days only. Editing a historical holiday updates that period's holiday rule while preserving its saved salary settings.")
                }

                if let blockReason {
                    Section {
                        Label(blockReason, systemImage: "lock.fill").foregroundStyle(.secondary)
                    } footer: {
                        Text("Nothing is marked automatically. This day stays Not Marked.")
                    }
                } else {
                    Section("Attendance") {
                        statusChoice
                        if status == nil {
                            Text("Not marked yet — choose a status to record this day.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    if status == .absent {
                        Section {
                            TextField("Reason for absence", text: $reason)
                                .focused($reasonFocused)
                                .submitLabel(.done)
                                .accessibilityLabel("Absence reason")
                            suggestionChips
                        } header: {
                            Text(settings.requireAbsenceReason ? "Reason (required)" : "Reason")
                        } footer: {
                            if reasonMissing {
                                Text("Please enter a reason for the absence.")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if settings.notesEnabled || !notes.isEmpty {
                        Section("Notes (optional)") {
                            TextField("Add a note", text: $notes, axis: .vertical)
                                .lineLimit(2...6)
                        }
                    }
                }

                if let existing {
                    Section("Record details") {
                        LabeledContent("Created", value: existing.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Last updated", value: existing.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    Section {
                        Button("Delete Record", role: .destructive) { showDelete = true }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Mark Attendance" : "Edit Attendance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isDirty ? "Cancel" : "Done") { isDirty ? (showDiscard = true) : dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog("Delete this attendance record?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete Record", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The day will go back to Not Marked.")
            }
        }
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: load)
        .presentationDetents([.medium, .large])
    }

    // MARK: - Pieces

    private var statusChoice: some View {
        HStack(spacing: 12) {
            ForEach(AttendanceStatus.allCases) { option in
                Button {
                    status = option
                    errorMessage = nil
                    Haptics.tap(enabled: settings.hapticsEnabled)
                    if option == .present { reasonFocused = false }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.title2)
                        Text(option.rawValue).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(status == option ? Color.white : StatusPalette.color(for: option, scheme: scheme))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(status == option ? StatusPalette.color(for: option, scheme: scheme)
                                                   : StatusPalette.color(for: option, scheme: scheme).opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.rawValue)
                .accessibilityAddTraits(status == option ? [.isSelected] : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        // Suggestions only prefill the text field; "Other" just focuses it
                        // so you must still type a reason.
                        if suggestion == "Other" {
                            reasonFocused = true
                        } else {
                            reason = suggestion
                        }
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
        }
        .accessibilityLabel("Reason suggestions")
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        if let existing {
            status = existing.status
            reason = existing.absenceReason
            notes = existing.notes
        }
        original = current
        loaded = true
    }

    private func save() {
        guard let status else { return }
        do {
            try store.save(date: date, status: status, reason: reason, notes: notes, settings: settings)
            NotificationService.cancelReminder(for: date)
            Haptics.success(enabled: settings.hapticsEnabled)
            router.showToast("Saved \(status.rawValue.lowercased()) for \(DateFormatting.mediumDate(date))")
            original = current
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error(enabled: settings.hapticsEnabled)
        }
    }

    private func delete() {
        guard let existing else { return }
        do {
            try store.delete(existing)
            Haptics.success(enabled: settings.hapticsEnabled)
            router.showToast("Record deleted")
            original = current   // clear dirty state so the sheet can close
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
