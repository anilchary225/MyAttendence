# MyAttendance

Personal iPhone attendance tracker. SwiftUI + SwiftData + Swift Charts, iOS 17+, fully offline, no third-party dependencies.

> **Salary Tracker added.** See [Salary Tracker integration and rules](SALARY_TRACKER.md) for setup, snapshot policy, backup compatibility and Xcode instructions.
>
> **Validation (30 October 2026):** The updated iOS app and XCTest bundle build with Xcode 27.1. A temporary macOS harness passed 86 shared-service tests (0 failures), covering the existing attendance features plus salary calculations, persistence, backups and V1 → V2 migration. The harness includes the actual salary PDF renderer and PDFKit checks; the PDF preview was rendered and visually inspected. SwiftUI screens and iOS test execution have not been run on an iPhone or simulator here because there is no usable installed iOS simulator runtime.

## Create the Xcode project

The supplied `MyAttendance.xcodeproj` is ready to open in Xcode. To recreate it from the source folders, use either route below.

**A. XcodeGen (fastest)**
```
brew install xcodegen
cd MyAttendance      # folder containing project.yml
xcodegen
open MyAttendance.xcodeproj
```

**B. By hand**
1. Xcode → File → New → Project → iOS App. Product name `MyAttendance`, Interface SwiftUI, Storage **None**, Language Swift. Deployment target iOS 17.0.
2. Delete the generated `MyAttendanceApp.swift` and `ContentView.swift` (the app has its own `@main`).
3. Drag the folders `App`, `Models`, `Services`, `Utilities`, `Views` into the app target ("Create groups", target checked).
4. Add a Unit Testing Bundle target `MyAttendanceTests` and add `MyAttendanceTests/MyAttendanceTests.swift` to it.
5. Set **Swift Language Version to 5** in Build Settings (the code uses `nonisolated(unsafe)` and is written for Swift 5 mode).

No extra permissions or capabilities are required. Launch-screen settings are included in the supplied project. Notifications need no usage string.

## Run on a physical iPhone
1. Plug in the iPhone, enable Developer Mode (Settings → Privacy & Security).
2. Xcode → select the target → Signing & Capabilities → choose your (free) Personal Team; change the bundle ID if it's taken.
3. Pick your iPhone as the run destination, press ⌘R, and trust the developer profile on the phone if asked (Settings → General → VPN & Device Management).
4. Free-team installs expire after 7 days; re-run from Xcode to renew. Back up before reinstalling, since deleting the app deletes its data.

## Run tests
Product → Test (⌘U), or
`xcodebuild test -scheme MyAttendance -destination 'platform=iOS Simulator,name=iPhone 15'`

## Manual test script
1. **Mark** — Dashboard → Mark Attendance → Present → Save. Status shows Present; the button becomes Edit.
2. **Absent validation** — Calendar → tap a past weekday → Absent. Save stays disabled until a reason is typed; whitespace doesn't count.
3. **No duplicates** — tap the same day again, change status, Save. History still shows one row for that date.
4. **Weekend/future** — Tap a Saturday and a future date: the editor explains why it's locked.
5. **Persistence** — force-quit and relaunch; records and settings remain.
6. **Backup** — Settings → Backup, Restore & Export → Create Backup → Save to Files… (or Share…). "Last backup" updates only after a save/share completes.
7. **CSV** — same screen → Export CSV → Save to Files. Open in Numbers/Excel; check quoting.
8. **Restore** — Clear All Attendance Data (confirm) → Restore from Backup… → pick the file → check the preview counts → Replace or Merge. Records return.
9. **Bad file** — try restoring a random JSON or a CSV in Restore: it must be rejected with a message and no change.
10. **Reminders** — Settings → turn on reminders (permission prompt appears now, not before). Set a time 2 minutes ahead and background the app; mark the day first and confirm no notification arrives.

## Formats
- **Percentage** = present ÷ (present + absent) × 100 over working days that are not weekends/non-working, not in the future, and on/after the tracking start. Unmarked days are excluded.
- **Backup JSON** (`kind: fullBackup`): `appIdentifier`, `formatVersion` (2; reads older format 1), `kind`, `exportedAt`, `appVersion`, `settings`, `records[]`, `metadata`, and optional `salary` (settings, calendar holiday dates and monthly snapshots). Dates are `yyyy-MM-dd` strings so time zones never shift them.
- **Report JSON** (`kind: reportExport`): same shape without settings; importable as records but not restorable as a full backup.
- **CSV columns**: Date, Weekday, Status, Absence Reason, Notes, Created At, Updated At. Import needs Date and Status; invalid rows are skipped and reported; absent rows need a reason; duplicate dates keep the later Updated At.

## Known limitations
- iPhone/simulator runtime and visual verification are still required (see validation above).
- Reminders are scheduled for the next 14 days each time the app opens or data changes; if you don't open the app for over two weeks, they stop until you do.
- Saved backups can't be created silently in a fixed folder; iOS requires the picker/share sheet each time.
- Safety backups before Replace go to the app's Documents/SafetyBackups folder (visible in Files only if you enable file sharing, which isn't enabled).
- Accent color is applied via `.tint`; some system controls ignore it.
- Schema V2 adds the salary ledger with a V1 → V2 migration. Freeze existing schemas before future changes to stored models.
