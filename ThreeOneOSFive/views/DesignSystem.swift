import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.58, green: 0.00, blue: 1.00)
    static let accentDeep = Color(red: 0.22, green: 0.00, blue: 0.40)
    static let neonMagenta = Color(red: 0.94, green: 0.00, blue: 1.00)
    static let highlight = Color(red: 0.97, green: 0.90, blue: 1.00)
    static let pageBackground = Color(red: 0.035, green: 0.012, blue: 0.07)
    static let consoleBackground = Color(red: 0.086, green: 0.035, blue: 0.14)
    static let elevatedBackground = Color(red: 0.141, green: 0.051, blue: 0.22)
    static let secondaryText = Color(red: 0.78, green: 0.70, blue: 0.86)
    static let neonGradient = LinearGradient(
        colors: [accent, neonMagenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
    static let contentCardCornerRadius: CGFloat = 20
    static let contentCardInset: CGFloat = 16
    static let contentCardPadding: CGFloat = 16
}

struct VINIButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : AppTheme.highlight)
            .background(
                Group {
                    if prominent {
                        AppTheme.neonGradient
                    } else {
                        AppTheme.consoleBackground
                    }
                }
                .opacity(configuration.isPressed ? 0.72 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        prominent ? Color.white.opacity(0.18) : AppTheme.accent.opacity(0.65),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: prominent ? AppTheme.neonMagenta.opacity(0.28) : .clear, radius: 12)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct VINICardBackground: ViewModifier {
    var elevated = false

    func body(content: Content) -> some View {
        content
            .background(elevated ? AppTheme.elevatedBackground : AppTheme.consoleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.30), lineWidth: 1)
            )
    }
}

extension View {
    func viniCard(elevated: Bool = false) -> some View {
        modifier(VINICardBackground(elevated: elevated))
    }
}

struct AppCardBorder: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: AppTheme.contentCardCornerRadius,
            style: .continuous
        )
        .strokeBorder(
            Color(uiColor: .separator).opacity(0.22),
            lineWidth: 0.5
        )
        .accessibilityHidden(true)
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(AppTheme.pageBackground)
            Text("V")
                .font(.system(size: size * 0.72, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.neonGradient)
                .shadow(color: AppTheme.neonMagenta.opacity(0.72), radius: size * 0.16)
            Ellipse()
                .stroke(AppTheme.highlight.opacity(0.9), lineWidth: max(1, size * 0.035))
                .frame(width: size * 1.12, height: size * 0.34)
                .rotationEffect(.degrees(-16))
                .shadow(color: AppTheme.neonMagenta.opacity(0.65), radius: size * 0.08)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.55), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}
