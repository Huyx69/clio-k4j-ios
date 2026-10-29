import SwiftUI

/// Palette inspirée du tableau de bord Clio 2 (fond nuit, accent orange LCD).
enum Theme {
    static let bg      = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let panel   = Color(red: 0.078, green: 0.090, blue: 0.110)
    static let line    = Color(red: 0.145, green: 0.165, blue: 0.192)
    static let fg      = Color(red: 0.913, green: 0.902, blue: 0.882)
    static let muted   = Color(red: 0.541, green: 0.561, blue: 0.592)
    static let lcd     = Color(red: 1.000, green: 0.420, blue: 0.172)
    static let ok      = Color(red: 0.298, green: 0.765, blue: 0.541)
    static let warn    = Color(red: 0.949, green: 0.702, blue: 0.239)
    static let bad     = Color(red: 0.937, green: 0.325, blue: 0.314)
    static let lcdBg1  = Color(red: 0.102, green: 0.059, blue: 0.035)
    static let lcdBg2  = Color(red: 0.071, green: 0.043, blue: 0.027)
}

struct Pill: View {
    let level: Int   // 0 off, 1 busy, 2 ok, 3 err
    let text: String
    private var color: Color {
        [Theme.muted, Theme.warn, Theme.ok, Theme.bad][max(0, min(3, level))]
    }
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text.uppercased()).font(.caption).bold().tracking(0.6)
        }
        .foregroundColor(color)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 99).stroke(Theme.line))
        .clipShape(Capsule())
    }
}

struct Tile: View {
    let label: String
    let value: String
    let unit: String?
    var variant: Variant = .normal
    enum Variant { case normal, warn, bad }
    private var color: Color {
        switch variant { case .warn: return Theme.warn; case .bad: return Theme.bad; default: return Theme.fg }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2).tracking(0.6).foregroundColor(Theme.muted).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 26, weight: .semibold, design: .default))
                    .monospacedDigit().foregroundColor(color)
                if let u = unit { Text(u).font(.caption).foregroundColor(Theme.muted) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 22, weight: .bold)).tracking(0.9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MainButton: View {
    let title: String
    var role: Role = .primary
    var disabled: Bool = false
    let action: () -> Void
    enum Role { case primary, secondary, danger, dangerArmed }
    var body: some View {
        Button(action: action) {
            Text(title).bold().frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .disabled(disabled)
        .foregroundColor(fg)
        .background(bg)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(disabled ? 0.4 : 1)
    }
    private var fg: Color {
        switch role {
        case .primary: return Color(red: 0.102, green: 0.051, blue: 0.020)
        case .danger: return Theme.bad
        case .dangerArmed: return .white
        default: return Theme.fg
        }
    }
    private var bg: Color {
        switch role {
        case .primary: return Theme.lcd
        case .dangerArmed: return Theme.bad
        default: return Theme.panel
        }
    }
    private var border: Color {
        switch role {
        case .primary: return Theme.lcd
        case .danger, .dangerArmed: return Theme.bad
        default: return Theme.line
        }
    }
}
