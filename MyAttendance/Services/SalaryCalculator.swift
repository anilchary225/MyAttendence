import Foundation

/// Pure calculation layer. Rates retain Decimal precision; totals are rounded
/// only after multiplication to avoid a full month losing a few paise.
enum SalaryCalculator {
    static func monthKey(_ month: Date) -> String { DateFormatting.isoDay(DateFormatting.startOfMonth(month)) }

    static func period(_ month: Date, configuration: SalaryConfiguration) -> (start: Date, end: Date) {
        let cal = DateFormatting.calendar
        let start = cal.date(byAdding: .day, value: configuration.periodStartDay - 1,
                             to: DateFormatting.startOfMonth(month))!
        let next = cal.date(byAdding: .day, value: configuration.periodStartDay - 1,
                            to: DateFormatting.addingMonths(1, to: month))!
        return (start, cal.date(byAdding: .day, value: -1, to: next)!)
    }

    static func activeMonth(configuration: SalaryConfiguration, now: Date = Date()) -> Date {
        let month = DateFormatting.startOfMonth(now)
        return DateFormatting.normalize(now) < period(month, configuration: configuration).start
            ? DateFormatting.addingMonths(-1, to: month) : month
    }

    static func calculate(month: Date, configuration c: SalaryConfiguration,
                          entries: [AttendanceEntry], now: Date = Date()) throws -> SalarySummary {
        if let message = c.validationMessage { throw SalaryError.invalid(message) }
        let period = period(month, configuration: c)
        let allDays = DateFormatting.days(from: period.start, to: period.end)
        let scheduled = allDays.filter { c.workingWeekdays.contains(DateFormatting.weekday(of: $0)) }
        let today = DateFormatting.normalize(now)
        let start = max(DateFormatting.parseIsoDay(c.startDay)!,
                        c.attendanceStartDay.flatMap(DateFormatting.parseIsoDay) ?? .distantPast)
        let byDay = Dictionary(MergePlanner.dedupe(entries).entries.map { (DateFormatting.isoDay($0.date), $0) },
                               uniquingKeysWith: { first, _ in first })
        let holidays = Set(c.paidHolidays)
        var s = SalarySummary(month: monthKey(month), periodStart: DateFormatting.isoDay(period.start),
                              periodEnd: DateFormatting.isoDay(period.end), monthlySalary: c.monthlySalary,
                              deductions: c.deductions, bonuses: c.bonuses)
        s.scheduled = scheduled.count
        // No eligible period or zero scheduled days: no money, including bonuses, is inferred.
        guard !scheduled.isEmpty else { return s }
        let denominator = c.method == .scheduledWorkingDays ? scheduled.count : allDays.count
        let rate = c.monthlySalary / Decimal(denominator)
        s.dailyRate = Money.round(rate)
        for date in scheduled where date >= start {
            let key = DateFormatting.isoDay(date)
            if date > today { s.future += 1; continue }
            s.scheduledToDate += 1
            var state: String
            var impact: Decimal = 0
            if byDay[key]?.status == .present {
                s.present += 1; state = "Present"; impact = rate
            } else if holidays.contains(key) {
                // A holiday overrides absence deductions, without creating attendance.
                if byDay[key]?.status == .absent { s.paidAbsences += 1 }
                else { s.holidays += 1; s.unmarked += 1 }
                state = "Paid holiday"; impact = rate
            } else if byDay[key]?.status == .absent {
                if c.paidAbsences { s.paidAbsences += 1; state = "Paid absence"; impact = rate }
                else { s.unpaidAbsences += 1; state = "Unpaid absence"; impact = -rate }
            } else { s.unmarked += 1; state = "Unmarked" }
            s.days.append(SalaryDay(date: key, state: state, impact: Money.round(impact)))
        }
        guard scheduled.contains(where: { $0 >= start && $0 <= today }) else { return s }
        s.gross = Money.round(rate * Decimal(s.paidDays))
        s.lost = Money.round(rate * Decimal(s.unpaidAbsences))
        s.net = max(0, Money.round(s.gross! - c.deductions + c.bonuses))
        if period.start <= today && today <= period.end {
            s.projectedGross = Money.round(rate * Decimal(s.paidDays + s.future))
            s.projectedNet = max(0, Money.round(s.projectedGross! - c.deductions + c.bonuses))
        }
        return s
    }
}
