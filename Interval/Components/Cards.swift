import SwiftUI

// MARK: - Insight card

struct InsightCard: View {
    var eyebrow: String
    var title: String
    var detail: String
    var accent: Color = Theme.Palette.primary
    var background: Color = Theme.Palette.surfaceContainerLow
    var badge: String? = nil
    var onPrimary: (() -> Void)? = nil
    var primaryLabel: String = "Tell me more"
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Text(eyebrow.uppercased())
                        .font(Theme.Font.body(10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.Palette.surfaceContainerLowest))
                        .overlay(Capsule().strokeBorder(accent.opacity(0.18), lineWidth: 1))
                }
                Spacer()
                if let badge {
                    Text(badge.uppercased())
                        .font(Theme.Font.body(10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }
            Text(title)
                .font(Theme.Font.body(18, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.leading)
            Text(detail)
                .font(Theme.Font.bodyText)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.leading)
            if onPrimary != nil || onDismiss != nil {
                HStack(spacing: 8) {
                    if let onPrimary {
                        Button(action: {
                            Haptics.tap()
                            onPrimary()
                        }) {
                            Text(primaryLabel)
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Theme.Palette.primaryFixed))
                                .overlay(Capsule().strokeBorder(Theme.Palette.primaryFixedDim.opacity(0.7), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    if let onDismiss {
                        Button(action: {
                            Haptics.select()
                            onDismiss()
                        }) {
                            Text("Dismiss")
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.inkMuted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Theme.Palette.surfaceContainerHighest))
                                .overlay(Capsule().strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.8), radius: 16, y: 10)
        .shadow(color: Theme.Shadow.warm.opacity(0.3), radius: 6, y: 2)
    }
}

// MARK: - Health stat tile

struct HealthStatTile: View {
    var label: String
    var value: String
    var progress: Double
    var icon: String
    var tint: Color = Theme.Palette.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 22, height: 22)

                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(label.uppercased())
                    .font(Theme.Font.body(10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            Text(value)
                .font(Theme.Font.body(18, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Capsule()
                .fill(Theme.Palette.surfaceContainer)
                .frame(height: 7)
                .overlay(
                    GeometryReader { geo in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Palette.tertiaryFixed, tint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * max(0, min(1, progress)))
                    }
                )
                .frame(height: 7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLowest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.45), radius: 12, y: 6)
        .shadow(color: Theme.Shadow.warm.opacity(0.18), radius: 4, y: 2)
    }
}

// MARK: - Row with optional trailing chip + arrow

struct LabeledRow<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconBackground: Color = Theme.Palette.peachTint
    var iconForeground: Color = Theme.Palette.coralDeep
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconBackground: Color = Theme.Palette.peachTint,
        iconForeground: Color = Theme.Palette.coralDeep,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconBackground = iconBackground
        self.iconForeground = iconForeground
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                ZStack {
                    Circle().fill(iconBackground)
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconForeground)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.body(15, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
                if let subtitle {
                    Text(subtitle).font(Theme.Font.body(12)).foregroundStyle(Theme.Palette.inkMuted)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.45), radius: 10, y: 5)
    }
}

// MARK: - Section header for screens

struct SectionHeader: View {
    var eyebrow: String? = nil
    var title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(Theme.Font.eyebrow)
                    .tracking(1.1)
                    .foregroundStyle(Theme.Palette.primary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                trailing
            }
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.bodyText)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }
}

// MARK: - Ask bar (AI input)

struct AskBar: View {
    var placeholder: String = "Ask Interval anything…"
    @State private var text: String = ""
    var onSubmit: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.Palette.primaryFixed)
                    .frame(width: 32, height: 32)
                Text("i")
                    .font(Theme.Font.display(16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primary)
            }
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder)
                    .foregroundStyle(Theme.Palette.inkMuted)
            )
                .font(Theme.Font.bodyText)
                .foregroundStyle(Theme.Palette.ink)
                .tint(Theme.Palette.secondary)
                .submitLabel(.send)
                .onSubmit {
                    guard !text.isEmpty else { return }
                    Haptics.tap()
                    onSubmit?(text)
                    text = ""
                }
            Image(systemName: "command")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLowest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    Theme.Palette.outlineVariant,
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.45), radius: 12, y: 7)
        .shadow(color: Theme.Shadow.warm.opacity(0.18), radius: 4, y: 2)
    }
}
