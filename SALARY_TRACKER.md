# Salary Tracker — Xcode integration and behavior

The files in this folder are complete updated source files. The Xcode project already includes the new files and keeps the five existing tabs. No package, backend, network service or subscription is required.

## Open and run

1. In the existing app, create a JSON backup before installing an update.
2. Open `MyAttendance.xcodeproj` from this folder. If Xcode was open while files changed, close and reopen the project.
3. Select the **MyAttendance** scheme and your iPhone or an iPhone simulator running iOS 17 or later.
4. For an iPhone, keep the same bundle identifier and signing team as your installed app, then press **Command–R**. The supplied project's signing team has been preserved. Using a different bundle identifier creates a separate installation with separate data.
5. Open **Settings → Salary → Salary Settings**. Enter salary, choose the calculation start date, configure the optional adjustments/holidays, and Save.
6. Open **Salary Tracker** from Dashboard, Reports or Settings. Use the arrows to view earlier salary months. The current period is the latest selectable month.
7. Run the complete iOS test suite with **Product → Test (Command–U)** after selecting an installed iPhone simulator runtime or test device.

If you regenerate the project, run `xcodegen generate` in this folder. `project.yml` includes app sources only under `MyAttendance` and XCTest sources only under `MyAttendanceTests`. No test source belongs to the app target. XcodeGen itself is only a project-generation tool and is not an app dependency.

The free Apple developer account installation limit discussed earlier still applies. Update the same app identifier; if Xcode reports the device app limit, run on a simulator or back up and remove an unneeded development app. Deleting an app deletes its local data.

## What changed

| File | Purpose |
| --- | --- |
| `MyAttendance/Models/SalaryModels.swift` | Decimal money helpers; validated salary settings; snapshot, summary and backup values; local SwiftData salary ledger. |
| `MyAttendance/Services/SalaryCalculator.swift` | One calculation service used throughout the app. Calendar/period boundaries, payable days, deductions, earnings and projections. |
| `MyAttendance/Services/SalaryExportService.swift` | Salary CSV and statement-PDF exports using the existing temp-file architecture. |
| `MyAttendance/Services/SalaryInvoiceRenderer.swift` | Premium vector PDF design, shared with macOS rendering tests. |
| `MyAttendance/Views/Salary/SalarySettingsView.swift` | Salary setup, adjustments, shared work schedule, paid holidays and period configuration. |
| `MyAttendance/Views/Salary/SalaryTrackerView.swift` | Month selector, summary cards, financial breakdown, actual-data charts, history and exports; shared overview card. |
| `MyAttendance/Models/SchemaVersions.swift` | Additive V1 → V2 SwiftData migration. The attendance model is unchanged. |
| `MyAttendance/Services/AttendanceStore.swift` | Salary persistence and snapshots using the existing model context; atomic attendance/salary restore; shared report lookup. |
| `MyAttendance/App/MyAttendanceApp.swift` | Open schema V2; capture salary periods on launch, foreground and attendance-schedule changes. No new app entry point. |
| `MyAttendance/Services/BackupService.swift` | JSON backup format 2 includes salary data and still reads format 1. |
| `MyAttendance/Services/ImportService.swift` | Carry optional salary data through restore preview; allow settings-only/empty-attendance backups. |
| `MyAttendance/Views/Settings/BackupRestoreView.swift` | Salary backup, restore preview, safety backup and salary report navigation. |
| `MyAttendance/Views/Settings/SettingsView.swift` | Salary section and distinct accent-color swatches. |
| `MyAttendance/Views/Settings/WorkingDaysSettingsView.swift` | Existing schedule editor shared between attendance and salary settings. |
| `MyAttendance/Views/Dashboard/DashboardView.swift` | Shared current-period salary overview and navigation. |
| `MyAttendance/Views/Reports/ReportsView.swift` | Same salary overview and navigation, including before any attendance is recorded. |
| `MyAttendance/Views/Components/AttendanceEditorView.swift`, `MyAttendance/Views/Calendar/*.swift` | Mark/remove calendar holidays and display holiday badges. |
| `MyAttendance/Views/Components/LaunchSplashView.swift`, `MyAttendance/App/LaunchScreen.storyboard`, `MyAttendance/Assets.xcassets` | Native launch screen, in-app splash, transparent brand logo, light/dark colors and supplied original assets. |
| `MyAttendanceTests/SalaryTests.swift` | Calculation, period-boundary, persistence, snapshots, backup/restore, export and migration tests. |
| `MyAttendanceTests/MyAttendanceTests.swift` | Existing backup version assertion updated to format 2. All existing tests retained. |
| `project.yml`, `MyAttendance.xcodeproj` | Register all files with the correct target; preserve signing team. |

## Financial rules

- Currency is INR. Money uses `Decimal`; values entered by the user accept at most two decimal places. Negative, blank, nonnumeric, excessively large or malformed values cannot be saved. Zero salary is valid and does not generate a misleading percentage of salary earned.
- Default rate = monthly target ÷ all scheduled working days in the selected salary period. A day-1 period is a calendar month. The denominator is the full period even if salary/attendance tracking starts partway through it.
- Optional calendar-day rate = monthly target ÷ all calendar days in the period, with earnings still restricted to payable working days. The UI explicitly explains that this method can earn less than the monthly target even with full attendance.
- The work schedule is the existing attendance schedule, Monday–Friday by default. The later of attendance tracking start and salary calculation start controls payable eligibility.
- Present days are payable. Absences are payable only when paid absences are enabled or the date is a configured paid holiday. A holiday is paid only on an eligible scheduled working day and is never paid twice.
- Paid holidays do not create attendance records. A holiday without an attendance entry remains an unmarked day in attendance counts and earns holiday pay. A recorded absence on a paid holiday counts as a paid absence, with no loss.
- Unmarked days never cause absence deductions. Future attendance entries, including imported entries, do not become confirmed earnings/losses before their date.
- Confirmed gross = precise rate × payable days to date. Loss = precise rate × recorded unpaid absence days. Gross already excludes unpaid absences: loss is not deducted twice.
- Totals round to two decimal places only after multiplication. A full 22-day month at ₹30,000 therefore earns exactly ₹30,000 even though the displayed daily rate is ₹1,363.64. Individual rounded daily chart bars can differ from a rounded monthly total by a few paise.
- Other deductions and bonuses are recurring period amounts, applied once in full even to partial periods. Estimated net = max(₹0, confirmed gross − other deductions + bonuses). The UI explains the zero floor.
- Current-period projected gross = precise rate × (confirmed payable days + remaining future scheduled days). Projected net applies the period adjustments once. Past unmarked days are not silently filled in. No projection is shown for a closed period or before any eligible working day has elapsed.
- With no eligible scheduled days to date, confirmed earnings and net estimates are unavailable. A valid period's daily rate can still be shown. Invalid schedules/settings never divide by zero.
- Attendance percentage = present ÷ recorded eligible working days, independent of whether those absences are paid. It is unavailable when no working day has been recorded.
- Figures are attendance-based estimates, never a claim of bank deposits, payroll payment or salary received.

## Salary periods and history

Choose a start day from 1 to 28 during initial setup. Day 26 means the 26th through the 25th of the next month, labelled by the starting month. The start day is fixed after the first save to prevent overlapping historical periods. Salary amounts, calculation method, paid-absence rules, adjustments, holiday dates and calculation start date remain editable.

Snapshots are created for the open period when salary is saved. On later launches/foregrounding the store fills missing periods from the month the app first knew those salary rules. It does not invent older historical salary settings.

Open-period rules follow current salary settings and the shared work schedule. Once a period ends, its settings are frozen. Changing today's salary cannot rewrite those rules. Snapshot values include the month, applicable settings, schedule, day counts, daily rate, gross, absence loss, adjustments and net estimate.

Attendance remains the sole source of truth. Editing, deleting, importing, restoring or clearing attendance recalculates snapshot totals using each snapshot's saved rules. This is an intentionally recalculating attendance ledger, not an immutable payroll receipt. Clearing all attendance keeps salary settings and snapshot rules; holiday earnings may remain for explicitly configured paid holidays.

Earlier months without snapshots are prominently labelled **Estimate using current salary settings; no historical snapshot**. You can save a snapshot for such a month after reviewing the settings-basis explanation. Saving freezes the rules used in that estimate, without inventing a historical salary change. Existing saved snapshots cannot be overwritten through this action.

## Backup and restore

Full JSON backups use format **2** and add an optional `salary` object with current settings, the effective month, and snapshots. Missing salary fields decode normally, so original format-1 backups remain readable. Salary backup data is validated before database writes. A future unsupported backup version is still rejected.

- **Replace All:** attendance and salary are replaced in one database transaction. A safety backup includes current salary data before replacing local data. Restoring an older backup with no salary fields clears salary settings/history; the preview explains this.
- **Merge:** attendance keeps its existing newer-record rules. Existing local salary settings and matching month settings are retained. Calendar holiday dates are combined and explicitly amend applicable holiday rules without changing saved salary amounts or other financial settings. Missing incoming snapshots are added, and all totals are recalculated from the resulting attendance. If no local salary settings exist, incoming settings are adopted.
- Attendance-settings restoration remains optional. Salary data always follows the selected restore strategy. The open salary period uses the resulting shared attendance work schedule; closed snapshots retain their own saved schedules.
- **Import Records** remains attendance-only. Importing a full backup through the records-import action does not silently change salary settings/history.
- Empty-attendance backups can still restore salary and settings. A completely empty legacy backup with attendance settings can also be restored.

Salary restores and attendance writes share the existing non-autosaving SwiftData context, with rollback on failure. Existing settings in UserDefaults are applied only after a successful database restore, as before.

## Export

Existing attendance CSV, JSON and PDF formats/actions remain available. Salary exports are separate, clearly named reports available inside Salary Tracker and from Settings → Backup, Restore & Export → Salary Reports.

- Selected-period salary CSV includes INR amounts, period dates, all day counts, confirmed and projected values, method, work schedule, start date, paid-absence rule, holiday dates and settings basis.
- **Export all saved salary months (CSV)** exports the snapshot history, recalculated from attendance using saved rules.
- Salary PDF uses a premium invoice-style salary-statement layout with the new logo, period reference, INR amounts, a prominent estimated-net total, itemized earnings/deductions/bonuses, attendance counts, projections and settings-basis explanation. It remains clearly marked as an estimate.
- Unavailable monetary values are blank in CSV and labelled unavailable in the app/PDF. Zero remains a real zero.

## Migration

Schema V1 still contains the unchanged `AttendanceRecord`. Schema V2 adds `SalaryLedger` and uses a lightweight migration stage. The app does not delete or reset a database when migration/opening fails; its existing storage-error screen remains in place. Future edits to the attendance model must freeze the old schema before changing its stored properties.

The migration uses [Apple's SwiftData schema migration APIs](https://developer.apple.com/documentation/swiftdata/schemamigrationplan).

## Validation

See the final validation notes in README.md. The iOS app and test bundle are built with the installed Xcode; execution on an iPhone or iOS simulator remains a separate runtime check. Shared-service tests run on macOS without an iOS simulator and now include the actual Core Graphics/Core Text PDF renderer and PDFKit content/page checks. The SwiftUI screens remain subject to iPhone visual verification. The exported sample PDF was rendered to an image and visually inspected.

## Quick iPhone acceptance check

1. Back up; install the update over the existing app. Existing attendance and tabs should remain.
2. Set salary to ₹30,000; choose a calculation start date covering October 2026; keep Mon–Fri and day 1. October has 22 scheduled working days and displays ₹1,363.64/day.
3. Mark a working day Present. Confirm gross increases on Dashboard, Salary Tracker and Reports.
4. Mark another working day Absent with a reason. Confirm salary loss increases, then enable paid absences and confirm the same day becomes payable. The editor's existing reason rule stays in effect.
5. Delete an attendance entry. It should become unmarked with no absence loss. Weekends should not count toward loss.
6. Configure a paid working-day holiday; verify it earns once and creates no attendance entry.
7. Check a previous month, the current-period projection and the salary-settings-basis label. Save a historical snapshot, change current salary, and verify the closed month retains its saved salary rules.
8. Export salary CSV and PDF, save a JSON backup, then test Merge and Replace using the restore preview. Confirm salary settings and snapshots survive reopening the app.
9. Reopen the app without a network connection; all attendance and salary functions should remain available.

## Calendar holidays

Tap a day in Calendar (or the Dashboard calendar), then use **Mark as Paid Holiday**. Tap **Remove Paid Holiday** to undo it. A sun badge appears in both month-grid and list layouts. Holiday edits save immediately; tap **Done** to close without creating attendance. Attendance still has its separate Present/Absent Save action and existing absence-reason validation.

Holidays can be marked before salary setup, including future dates and weekends. They persist in the local ledger and full JSON backups. Only eligible scheduled working days earn holiday pay; future holidays do not become confirmed earnings early, and weekend holidays do not earn pay under a Mon–Fri schedule. They never create Present or Absent entries.

An explicit historical calendar holiday edit changes only the matching snapshot's holiday rule and recalculates its totals. The saved monthly salary, calculation method, work schedule, deductions and bonuses remain unchanged. This is the deliberate exception to frozen snapshot rules. Holiday dates merged from backups follow the same explicit-date behavior. Safety backups and replacement confirmation also protect holiday-only data when no attendance or salary configuration exists yet.

## Branding and PDF preview

See `BRAND_ASSETS.md` for the uploaded-asset reference, generated transparent logo, generation prompt, splash-screen behavior and accent-color fix. The original uploaded assets are backed up in `MyAttendance-OriginalUploadedAssets.zip`; the generated mark is used consistently for the app icon, launch, splash and invoice/PDF branding.

`output/pdf/Salary-Statement-Preview.pdf` demonstrates the same native renderer used by the app. It is visibly labelled **DESIGN PREVIEW - SAMPLE DATA**; its figures are test fixtures, not your personal salary or attendance. The app's normal exports use only your stored data and do not show the sample label. No sample records have been inserted into the app.
