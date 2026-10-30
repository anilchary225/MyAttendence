import SwiftUI

/// One day in the month grid. Color is always paired with a symbol or text so it
/// stays readable with color-blind or increased-contrast settings.
struct AttendanceDayCell: View {
    let date: Date
    let status: AttendanceStatus?
    let isNonWorking: Bool
    let isFuture: Bool
    let isToday: Bool
    var compact = false
    var isPaidHoliday = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    private var tint: Color { StatusPalette.color(for: status, scheme: scheme) }

    private var stateText: String {
        if let status { return status.rawValue }
        if isFuture { return "Future date" }
        if isNonWorking { return "Non-working day" }
        return "Not marked"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 6 : 10, style: .continuous)
                .fill(background)
            RoundedRectangle(cornerRadius: compact ? 6 : 10, style: .continuous)
                .strokeBorder(border, lineWidth: isToday ? 2 : (status == nil && !isNonWorking && !isFuture ? 1 : 0))

            VStack(spacing: compact ? 0 : 2) {
                Text(DateFormatting.dayNumber(date))
                    .font(compact ? .caption2.weight(isToday ? .bold : .regular)
                                  : .subheadline.weight(isToday ? .bold : .medium))
                    .foregroundStyle(textColor)
                if !compact {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(status == nil ? Color.secondary.opacity(0.6) : tint)
                        .opacity(symbol.isEmpty ? 0 : 1)
                        .frame(height: 12)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isPaidHoliday {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: compact ? 6 : 9, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(compact ? 2 : 4)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(compact ? 1 : 0.92, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DateFormatting.fullDate(date)), \(stateText)\(isPaidHoliday ? ", paid holiday" : "")\(isToday ? ", today" : "")")
        .accessibilityAddTraits(.isButton)
    }

    private var symbol: String {
        if let status { return status.symbol }
        if isFuture || isNonWorking { return "" }
        return "circle.dashed"
    }

    private var background: Color {
        if status != nil { return tint.opacity(scheme == .dark ? 0.22 : 0.14) }
        if isPaidHoliday { return Color.orange.opacity(scheme == .dark ? 0.18 : 0.1) }
        if isFuture || isNonWorking { return Color.secondary.opacity(0.06) }
        return Color(.tertiarySystemGroupedBackground)
    }

    private var border: Color {
        if isToday { return .accentColor }
        return Color.secondary.opacity(0.35)
    }

    private var textColor: Color {
        if status != nil { return tint }
        if isFuture || isNonWorking { return Color.secondary.opacity(0.7) }
        return .primary
    }
}
