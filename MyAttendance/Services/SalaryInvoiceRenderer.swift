import Foundation
import CoreGraphics
import CoreText

/// One vector PDF renderer shared by iOS export and macOS layout verification.
/// There are no network, web-font or third-party rendering dependencies.
enum SalaryInvoiceRenderer {
    private static let ink = color(0.10, 0.15, 0.23)
    private static let muted = color(0.42, 0.47, 0.54)
    private static let blue = color(0.10, 0.35, 0.78)
    private static let green = color(0.12, 0.45, 0.34)
    private static let red = color(0.70, 0.24, 0.24)
    private static let line = color(0.88, 0.90, 0.93)
    private static let paperTint = color(0.96, 0.97, 0.99)
    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func data(report: SalaryReport, logo: CGImage? = nil,
                     generatedAt: Date = Date(), isPreview: Bool = false) throws -> Data {
        var bounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, [
                kCGPDFContextTitle: "MyAttendance Salary Statement",
                kCGPDFContextCreator: "MyAttendance",
                kCGPDFContextSubject: "Attendance-based salary estimate"
              ] as CFDictionary) else { throw ExportError.writeFailed("Couldn't start the salary PDF.") }
        context.beginPDFPage(nil)
        let pageHeight = bounds.height
        let margin: CGFloat = 44
        let width = bounds.width - margin * 2
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x, y: pageHeight - y - h, width: w, height: h)
        }
        func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor, radius: CGFloat = 0) {
            context.setFillColor(color)
            context.addPath(CGPath(roundedRect: rect(x, y, w, h), cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        func rule(_ y: CGFloat) { fill(margin, y, width, 0.65, line) }

        @discardableResult
        func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
                  size: CGFloat = 10, bold: Bool = false, color: CGColor = ink,
                  right: Bool = false) -> CGFloat {
            let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
            let font = bold ? CTFontCreateCopyWithSymbolicTraits(base, size, nil, .boldTrait, .boldTrait) ?? base : base
            var alignment: CTTextAlignment = right ? .right : .left
            let style = withUnsafePointer(to: &alignment) { pointer -> CTParagraphStyle in
                var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
                return CTParagraphStyleCreate(&setting, 1)
            }
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style
            ]
            let value = NSAttributedString(string: string, attributes: attributes)
            let setter = CTFramesetterCreateWithAttributedString(value as CFAttributedString)
            let sizeNeeded = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                                          CGSize(width: w, height: 1500), nil)
            let height = ceil(sizeNeeded.height) + 2
            let path = CGPath(rect: rect(x, y, w, height), transform: nil)
            context.saveGState()
            context.textMatrix = .identity
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
            context.restoreGState()
            return height
        }

        let s = report.summary
        if let logo { context.draw(logo, in: rect(margin - 4, 39, 42, 42)) }
        else {
            fill(margin, 44, 30, 30, blue, radius: 8)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(2.5)
            context.setLineCap(.round); context.setLineJoin(.round)
            context.move(to: CGPoint(x: margin + 8, y: pageHeight - 59))
            context.addLine(to: CGPoint(x: margin + 13, y: pageHeight - 64))
            context.addLine(to: CGPoint(x: margin + 23, y: pageHeight - 53)); context.strokePath()
        }
        text("MyAttendance", margin + 46, 45, 250, size: 17, bold: true)
        text("ATTENDANCE & SALARY", margin + 46, 68, 250, size: 7.5, color: muted)
        text("PERSONAL SALARY RECORD", 352, 47, 199, size: 7.5, bold: true, color: muted, right: true)
        text("MA-\(s.month.prefix(7).replacingOccurrences(of: "-", with: ""))", 352, 64, 199, size: 10, right: true)
        rule(97)

        text("Salary statement", margin, 116, 365, size: 29, bold: true)
        text(DateFormatting.monthYear(DateFormatting.parseIsoDay(s.month)!), margin, 157, 280, size: 11, color: muted)
        fill(451, 119, 100, 23, paperTint, radius: 6)
        text("ESTIMATE", 458, 125, 86, size: 8, bold: true, color: blue, right: true)
        text("Issued \(DateFormatting.isoDay(generatedAt))", 351, 158, 200, size: 9, color: muted, right: true)
        if isPreview { text("DESIGN PREVIEW - SAMPLE DATA", margin, 176, width, size: 8, bold: true, color: red) }

        fill(margin, 199, width, 95, paperTint, radius: 12)
        text("ESTIMATED NET SALARY", margin + 18, 215, 280, size: 8, bold: true, color: muted)
        text(Money.text(s.net), margin + 18, 235, 330, size: 31, bold: true)
        text("INR", 467, 219, 66, size: 9, bold: true, color: muted, right: true)
        text("\(s.paidDays) payable days", 380, 258, 153, size: 10, color: muted, right: true)

        text("SALARY PERIOD", margin, 314, 260, size: 7.5, bold: true, color: muted)
        text("\(s.periodStart)  to  \(s.periodEnd)", margin, 331, 280, size: 10)
        text("RATE BASIS", 353, 314, 198, size: 7.5, bold: true, color: muted, right: true)
        let basis = report.configuration.method == .scheduledWorkingDays ? "\(s.scheduled) scheduled working days" : "Calendar-day rate"
        text(basis, 353, 331, 198, size: 10, right: true)

        fill(margin, 363, width, 28, paperTint, radius: 4)
        text("DESCRIPTION", margin + 10, 372, 260, size: 7.5, bold: true, color: muted)
        text("DAYS", 342, 372, 42, size: 7.5, bold: true, color: muted, right: true)
        text("AMOUNT (INR)", 404, 372, 137, size: 7.5, bold: true, color: muted, right: true)

        func row(_ y: CGFloat, title: String, detail: String, days: String, amount: String, tint: CGColor = ink) {
            text(title, margin + 10, y, 280, size: 10, bold: true)
            text(detail, margin + 10, y + 17, 280, size: 8, color: muted)
            text(days, 342, y + 2, 42, size: 10, color: muted, right: true)
            text(amount, 396, y + 2, 145, size: 11, bold: true, color: tint, right: true)
            rule(y + 40)
        }
        row(404, title: "Confirmed gross earnings", detail: "Daily rate \(Money.text(s.dailyRate)) - payable attendance & holidays",
            days: String(s.paidDays), amount: Money.text(s.gross), tint: green)
        row(452, title: "Unpaid absences (reference)", detail: "Already excluded from gross - not deducted again",
            days: String(s.unpaidAbsences), amount: Money.text(s.lost), tint: red)
        row(500, title: "Other deductions", detail: "Configured once for this salary period", days: "-",
            amount: "- " + Money.text(s.deductions), tint: red)
        row(548, title: "Bonuses & additional earnings", detail: "Configured once for this salary period", days: "-",
            amount: "+ " + Money.text(s.bonuses), tint: green)
        text("Monthly salary target", margin + 10, 605, 260, size: 9, color: muted)
        text(Money.text(s.monthlySalary), 396, 603, 145, size: 11, right: true)

        fill(margin, 632, width, 42, paperTint, radius: 7)
        text("ATTENDANCE TO DATE", margin + 12, 641, 150, size: 7, bold: true, color: muted)
        text("\(s.present) present  /  \(s.paidAbsences) paid absence  /  \(s.holidays) holiday  /  \(s.unmarked) unmarked",
             margin + 12, 654, width - 24, size: 8.5)
        if let projected = s.projectedNet {
            text("Projected period-end net", margin, 691, 300, size: 9, color: muted)
            text(Money.text(projected), 386, 688, 165, size: 13, bold: true, color: blue, right: true)
            text("Assumes all \(s.future) remaining scheduled days are attended.", margin, 707, width, size: 8, color: muted)
        }
        let source = report.hasSnapshot ? "Saved period rules. Attendance edits recalculate this statement." : "Current salary settings used; no historical salary snapshot is available."
        text(source, margin, 737, width, size: 8, color: muted)
        text("Net = gross - other deductions + bonuses, floored at zero. Unmarked days cause no absence deductions. This is an attendance-based estimate, not proof of payment or an employer-issued payslip.",
             margin, 754, width, size: 7.5, color: muted)
        rule(799)
        text("MyAttendance  /  Local record", margin, 810, 350, size: 7, color: muted)
        text("1 / 1", 470, 810, 81, size: 7, color: muted, right: true)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
