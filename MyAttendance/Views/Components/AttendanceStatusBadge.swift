import SwiftUI

extension AttendanceStatus {
    /// Every status has a distinct SF Symbol so meaning never depends on color alone.
    /// Colors come from `StatusPalette`, which adapts to light/dark.
    var symbol: String {
        switch self {
        case .present: return "checkmark.circle.fill"
        case .absent: return "xmark.circle.fill"
        }
    }
}

/// Green/red tuned separately for light and dark mode (no asset catalog needed).
enum StatusPalette {
    static func color(for status: AttendanceStatus?, scheme: ColorScheme) -> Color {
        switch status {
        case .present?:
            return scheme == .dark ? Color(red: 0.30, green: 0.80, blue: 0.47) : Color(red: 0.08, green: 0.55, blue: 0.27)
        case .absent?:
            return scheme == .dark ? Color(red: 1.00, green: 0.42, blue: 0.40) : Color(red: 0.80, green: 0.17, blue: 0.17)
        case nil:
            return .secondary
        }
    }
}

struct AttendanceStatusBadge: View {
    let status: AttendanceStatus?
    var compact = false
    @Environment(\.colorScheme) private var scheme

    private var title: String { status?.rawValue ?? "Not Marked" }
    private var symbol: String { status?.symbol ?? "circle.dashed" }
    private var tint: Color { StatusPalette.color(for: status, scheme: scheme) }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 3 : 5)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status: \(title)")
    }
}

/// Standard rounded card container used across tabs.
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }
}
