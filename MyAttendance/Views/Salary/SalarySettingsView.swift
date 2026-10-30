import SwiftUI

struct SalarySettingsView: View {
    @EnvironmentObject private var store: AttendanceStore
    @EnvironmentObject private var settings: AttendanceSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SalaryConfiguration()
    @State private var salaryText = ""
    @State private var deductionText = "0"
    @State private var bonusText = "0"
    @State private var holiday = DateFormatting.normalize(Date())
    @State private var error: String?
    @State private var loaded = false

    private var configuration: SalaryConfiguration? {
        guard let salary = Money.parse(salaryText), let deduction = Money.parse(deductionText),
              let bonus = Money.parse(bonusText) else { return nil }
        var config = draft.usingAttendance(settings)
        config.monthlySalary = salary; config.deductions = deduction; config.bonuses = bonus
        return config.validationMessage == nil ? config : nil
    }

    var body: some View {
        Form {
            Section {
                moneyField("Monthly salary (₹)", text: $salaryText)
                Picker("Calculation method", selection: $draft.method) {
                    ForEach(SalaryMethod.allCases) { Text($0.title).tag($0) }
                }
                Text(draft.method.explanation).font(.footnote).foregroundStyle(.secondary)
                Toggle("Absences are paid", isOn: $draft.paidAbsences)
            } header: { Text("Salary in INR") } footer: {
                Text("Enter amounts without commas, using up to two decimal places. ₹0 is valid; blank or negative amounts are not.")
            }
            Section {
                moneyField("Other deductions (₹)", text: $deductionText)
                moneyField("Bonuses / extra earnings (₹)", text: $bonusText)
            } header: { Text("Monthly adjustments") } footer: {
                Text("These amounts apply once per salary period, including partial periods. Net pay is an estimate and is capped at ₹0 if deductions exceed earnings.")
            }
            Section("Schedule & period") {
                NavigationLink { WorkingDaysSettingsView() } label: {
                    LabeledContent("Working days", value: draft.usingAttendance(settings).workingWeekdays.sorted().map {
                        DateFormatting.calendar.shortWeekdaySymbols[$0 - 1]
                    }.joined(separator: ", "))
                }
                Text("Uses the Work Schedule in Attendance Settings, Monday–Friday by default. Changing it updates the open period; closed snapshots keep their saved schedule.")
                    .font(.footnote).foregroundStyle(.secondary)
                DatePicker("Salary calculation starts", selection: Binding(
                    get: { DateFormatting.parseIsoDay(draft.startDay) ?? Date() },
                    set: { draft.startDay = DateFormatting.isoDay($0) }), displayedComponents: .date)
                Stepper("Period starts on day \(draft.periodStartDay)", value: $draft.periodStartDay, in: 1...28)
                    .disabled(store.salary.configuration != nil)
                Text("Day 1 uses calendar months. Day 26, for example, uses the 26th through the 25th of the next month. Months are labelled by the period's starting month. Choose the start day before your first save; it is fixed afterwards to prevent overlapping historical periods. The rate uses the full period; days before tracking begins cannot earn salary.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                DatePicker("Holiday date", selection: $holiday, displayedComponents: .date)
                Button("Add paid holiday") {
                    let key = DateFormatting.isoDay(holiday)
                    if !draft.paidHolidays.contains(key) { draft.paidHolidays.append(key); draft.paidHolidays.sort() }
                }
                ForEach(draft.paidHolidays, id: \.self) { key in
                    HStack {
                        Text(key)
                        Spacer()
                        Button(role: .destructive) { draft.paidHolidays.removeAll { $0 == key } } label: {
                            Image(systemName: "minus.circle")
                        }.accessibilityLabel("Remove holiday \(key)")
                    }
                }
            } header: { Text("Paid holidays") } footer: {
                Text("Only scheduled working days qualify. A paid holiday earns once, even if attendance is recorded. Holidays never create attendance records.")
            }
            Section {
                if configuration == nil {
                    Text("Enter valid salary, deductions and bonuses to enable Save.").foregroundStyle(.orange)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save Salary Settings", action: save).disabled(configuration == nil || store.salaryLoadError != nil)
            } footer: {
                Text("Changes apply to the open period and future periods. Closed monthly snapshots retain their salary rules. Attendance edits recalculate snapshot totals using those saved rules. All data stays on this iPhone.")
            }
        }
        .navigationTitle("Salary Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            if let config = store.salaryConfiguration(settings: settings) {
                draft = config
                salaryText = Money.raw(config.monthlySalary)
                deductionText = Money.raw(config.deductions)
                bonusText = Money.raw(config.bonuses)
            }
            else { draft.paidHolidays = store.salary.calendarHolidays ?? [] }
            error = store.salaryLoadError
            loaded = true
        }
    }

    private func moneyField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline)
            TextField("0.00", text: text).keyboardType(.decimalPad).monospacedDigit()
                .accessibilityLabel(title)
        }
    }

    private func save() {
        guard let config = configuration else { return }
        do { try store.saveSalary(configuration: config, settings: settings); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
