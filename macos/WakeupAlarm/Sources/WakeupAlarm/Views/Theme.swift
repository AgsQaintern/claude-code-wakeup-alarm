import SwiftUI

enum WATheme {
    static let bg = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let sidebar = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let border = Color.white.opacity(0.08)
    static let text = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.55)
    static let accent = Color(red: 0.24, green: 0.86, blue: 0.59)
    static let warn = Color(red: 1.0, green: 0.42, blue: 0.48)
    static let blue = Color(red: 0.35, green: 0.65, blue: 1.0)
}

struct Pill: View {
    let title: String
    let ok: Bool
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ok ? WATheme.accent.opacity(0.18) : WATheme.warn.opacity(0.18))
            .foregroundStyle(ok ? WATheme.accent : WATheme.warn)
            .clipShape(Capsule())
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WATheme.muted)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WATheme.panel)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WATheme.border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PrimaryButton: View {
    let title: String
    var destructive: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(destructive ? WATheme.warn.opacity(0.2) : WATheme.accent.opacity(0.2))
                .foregroundStyle(destructive ? WATheme.warn : WATheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
