import SwiftUI
import UniformTypeIdentifiers

/// Wraps raw JSON data so `.fileExporter` can offer the native "Save to Files" picker.
struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Backup, restore, import and export. Every action is started by the user; nothing
/// is restored or uploaded automatically.
struct BackupRestoreView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @EnvironmentObject private var router: AppRouter

    private enum ImportMode { case restore, importRecords }

    // Backup creation
    @State private var backupData: Data?
    @State private var backupFileName = ""
    @State private var backupShare: ShareItem?
    @State private var showFileExporter = false

    // Import / restore
    @State private var importMode: ImportMode = .restore
    @State private var showImporter = false
    @State private var pendingBox: PreviewBox?

    // Exports
    @State private var exportShare: ShareItem?

    // Feedback
    @State private var message: AlertMessage?

    private struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    var body: some View {
        Form {
            infoSection
            createSection
            restoreSection
            exportSection
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $showFileExporter,
                      document: JSONFileDocument(data: backupData ?? Data()),
                      contentType: .json,
                      defaultFilename: backupFileName) { result in
            switch result {
            case .success:
                backupSucceeded()
            case .failure(let error):
                message = AlertMessage(title: "Backup not saved", body: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importMode == .restore ? [.json] : [.json, .commaSeparatedText],
                      allowsMultipleSelection: false) { result in
            handlePicked(result)
        }
        .sheet(item: $backupShare) { item in
            ShareSheet(url: item.url) { completed in if completed { backupSucceeded() } }
        }
        .sheet(item: $exportShare) { item in ShareSheet(url: item.url) }
        .sheet(item: $pendingBox) { box in
            ImportPreviewSheet(result: box.result, isRestore: importMode == .restore) { pendingBox = nil }
        }
        .alert(item: $message) { Alert(title: Text($0.title), message: Text($0.body), dismissButton: .default(Text("OK"))) }
    }

    private struct PreviewBox: Identifiable {
        let id = UUID()
        let result: ImportParseResult
    }

    // MARK: - Sections

    private var infoSection: some View {
        Section {
            LabeledContent("Attendance records", value: "\(store.count)")
            LabeledContent("Last backup") {
                if let date = settings.lastBackupDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Everything stays on this iPhone. Backups are files you save or share yourself — nothing is uploaded.")
        }
    }

    private var createSection: some View {
        Section {
            Button {
                createBackup()
            } label: {
                Label("Create Backup", systemImage: "externaldrive.badge.plus")
            }
            if backupData != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(backupFileName) is ready", systemImage: "checkmark.seal")
                        .font(.subheadline)
                    HStack {
                        Button("Save to Files…") { showFileExporter = true }
                        Button("Share…") { shareBackup() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Creates a versioned JSON file with all attendance records, settings, salary settings and monthly snapshots. Files never overwrite an existing backup without asking.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                importMode = .restore; showImporter = true
            } label: { Label("Restore from Backup…", systemImage: "arrow.counterclockwise.circle") }
            Button {
                importMode = .importRecords; showImporter = true
            } label: { Label("Import Records (JSON or CSV)…", systemImage: "square.and.arrow.down") }
        } header: {
            Text("Restore & Import")
        } footer: {
            Text("You'll see a preview and choose Replace or Merge before anything changes. Replacing saves a safety backup of your current data first. CSV imports need Date and Status columns; absent rows need a reason.")
        }
    }

    private var exportSection: some View {
        Section {
            Button { export(.csv) } label: { Label("Export CSV", systemImage: "tablecells") }
            Button { export(.json) } label: { Label("Export JSON (report only)", systemImage: "curlybraces") }
            Button { export(.pdf) } label: { Label("Export Report (PDF)", systemImage: "doc.richtext") }
            NavigationLink { SalaryTrackerView() } label: {
                Label("Salary Reports (CSV & PDF)", systemImage: "indianrupeesign.circle")
            }
        } header: {
            Text("Export")
        } footer: {
            Text("JSON exports here are reports. To keep a restorable copy, use Create Backup.")
        }
    }

    // MARK: - Backup

    private func createBackup() {
        do {
            let data = try BackupService.generate(entries: store.entries(), settings: settings.snapshot, salary: store.salary)
            backupData = data
            backupFileName = BackupService.backupFileName()
            Haptics.tap(enabled: settings.hapticsEnabled)
        } catch {
            message = AlertMessage(title: "Backup failed", body: error.localizedDescription)
            Haptics.error(enabled: settings.hapticsEnabled)
        }
    }

    private func shareBackup() {
        guard let data = backupData else { return }
        do {
            let url = try BackupService.writeTemporary(data, fileName: backupFileName)
            backupShare = ShareItem(url: url)
        } catch {
            message = AlertMessage(title: "Couldn't prepare the backup", body: error.localizedDescription)
        }
    }

    private func backupSucceeded() {
        settings.lastBackupDate = Date()
        Haptics.success(enabled: settings.hapticsEnabled)
        router.showToast("Backup saved")
    }

    // MARK: - Export

    private enum ExportKind { case csv, json, pdf }

    private func export(_ kind: ExportKind) {
        let entries = store.entries()
        do {
            switch kind {
            case .csv:
                exportShare = ShareItem(url: try ExportService.exportCSV(entries: entries, range: nil))
            case .json:
                exportShare = ShareItem(url: try ExportService.exportJSON(entries: entries, range: nil))
            case .pdf:
                guard let first = entries.map(\.date).min() else { throw ExportError.nothingToExport }
                let url = try ReportService.makePDF(entries: entries, from: first, to: Date(),
                                                    rules: AttendanceRules(settings: settings))
                exportShare = ShareItem(url: url)
            }
        } catch {
            message = AlertMessage(title: "Export failed", body: error.localizedDescription)
        }
    }

    // MARK: - Import

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = AlertMessage(title: "Couldn't open file", body: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try BackupService.readFile(at: url)
                let parsed: ImportParseResult
                if importMode == .restore {
                    parsed = try BackupService.parse(data: data, requireFullBackup: true)
                } else {
                    parsed = try ImportService.parse(data: data, fileName: url.lastPathComponent)
                }
                pendingBox = PreviewBox(result: parsed)
            } catch {
                // Nothing has been changed: parsing happens entirely before any write.
                message = AlertMessage(title: "Can't use this file", body: error.localizedDescription)
                Haptics.error(enabled: settings.hapticsEnabled)
            }
        }
    }
}

// MARK: - Preview & confirmation

struct ImportPreviewSheet: View {
    let result: ImportParseResult
    let isRestore: Bool
    let onFinish: () -> Void

    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var strategy: RestoreStrategy = .merge
    @State private var restoreSettings = true
    @State private var confirmReplace = false
    @State private var errorMessage: String?
    @State private var summary: ImportSummary?

    private var preview: ImportPreview {
        ImportService.preview(result, existing: store.entries(), strategy: strategy)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    LabeledContent("Source", value: result.source)
                    LabeledContent("Valid records", value: "\(result.entries.count)")
                    LabeledContent("Date range", value: result.dateRangeText)
                    if isRestore {
                        LabeledContent("Salary snapshots", value: "\(result.salary?.snapshots.count ?? 0)")
                        LabeledContent("Calendar holiday dates", value: "\(result.salary?.calendarHolidays?.count ?? 0)")
                        Text("Replace restores salary data too; older backups clear salary data on Replace. Merge keeps local salary settings and matching period rules, adding missing snapshots. Calendar holiday dates are combined and applied to matching periods; other saved rules stay fixed. Summaries recalculate from merged attendance.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let exported = result.exportedAt {
                        LabeledContent("Created", value: exported.formatted(date: .abbreviated, time: .shortened))
                    }
                    if result.invalidCount > 0 {
                        LabeledContent("Invalid (will be skipped)", value: "\(result.invalidCount)")
                    }
                }

                if !result.issues.isEmpty {
                    Section("Problems found") {
                        ForEach(result.issues.prefix(8)) { issue in
                            VStack(alignment: .leading) {
                                Text(issue.location).font(.caption.weight(.semibold))
                                Text(issue.message).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if result.issues.count > 8 {
                            Text("…and \(result.issues.count - 8) more").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                if let summary {
                    Section("Done") {
                        LabeledContent("Imported", value: "\(summary.imported)")
                        LabeledContent("Updated", value: "\(summary.updated)")
                        LabeledContent("Skipped", value: "\(summary.skipped)")
                        LabeledContent("Invalid", value: "\(summary.invalid)")
                    }
                } else {
                    strategySection
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isRestore ? "Restore Backup" : "Import Records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(summary == nil ? "Cancel" : "Close") { dismiss(); onFinish() }
                }
            }
            .confirmationDialog("Replace all existing records?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Replace \(store.count) Records", role: .destructive) { apply() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A safety backup of your current data is saved first. This can't be undone from inside the app.")
            }
        }
    }

    private var strategySection: some View {
        let p = preview
        return Group {
            Section("How should these be applied?") {
                Picker("Strategy", selection: $strategy) {
                    ForEach(RestoreStrategy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch strategy {
                case .replaceAll:
                    Text("Your \(store.count) current record\(store.count == 1 ? "" : "s") will be removed and replaced by the \(p.plan.addCount) from this file.")
                        .font(.footnote)
                case .merge:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(p.plan.addCount) new date\(p.plan.addCount == 1 ? "" : "s") will be added.")
                        Text("\(p.plan.replaceCount) existing record\(p.plan.replaceCount == 1 ? "" : "s") will be replaced (the file's copy is newer).")
                        Text("\(p.plan.keepCount) existing record\(p.plan.keepCount == 1 ? "" : "s") will be kept (unchanged or newer here).")
                        if p.plan.duplicatesInFile > 0 {
                            Text("\(p.plan.duplicatesInFile) duplicate date\(p.plan.duplicatesInFile == 1 ? "" : "s") inside the file will be collapsed.")
                        }
                    }
                    .font(.footnote)
                }
            }

            if isRestore, result.settings != nil {
                Section {
                    Toggle("Also restore attendance settings", isOn: $restoreSettings)
                } footer: {
                    Text("Working days, reason/notes rules, tracking start date, calendar layout and reminder time. Salary data is always restored with the selected Merge or Replace strategy.")
                }
            }

            Section {
                Button(strategy == .replaceAll ? "Replace Records" : "Merge Records") {
                    if strategy == .replaceAll && (store.count > 0 || store.salary.configuration != nil || !store.salary.snapshots.isEmpty || !(store.salary.calendarHolidays ?? []).isEmpty) { confirmReplace = true } else { apply() }
                }
                .disabled(!p.canApply)
                if !p.canApply {
                    Text("There are no valid records or settings to apply.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func apply() {
        let current = preview
        do {
            // 1. Safety copy first. If it fails, abort before touching anything.
            if strategy == .replaceAll && (store.count > 0 || store.salary.configuration != nil || !store.salary.snapshots.isEmpty || !(store.salary.calendarHolidays ?? []).isEmpty) {
                try BackupService.writeSafetyBackup(entries: store.entries(), settings: settings.snapshot, salary: store.salary)
            }
            // 2. Atomic apply (rolled back by the store on failure).
            try store.apply(entries: result.entries, strategy: strategy, salary: result.salary, restoreSalary: isRestore)
            // 3. Settings only after data succeeded.
            if isRestore, restoreSettings, let snap = result.settings { settings.apply(snap) }

            summary = ImportService.summary(for: current)
            errorMessage = nil
            Haptics.success(enabled: settings.hapticsEnabled)
            router.showToast(isRestore ? "Backup restored" : "Import complete")
        } catch {
            errorMessage = "\(error.localizedDescription) Your existing records were not changed."
            Haptics.error(enabled: settings.hapticsEnabled)
        }
    }
}
