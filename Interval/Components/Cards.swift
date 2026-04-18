import SwiftUI

// MARK: - Insight card

struct InsightCard: View {
    var eyebrow: String
    var title: String
    var detail: String
    var accent: Color = Theme.Palette.coral
    var background: Color = Theme.Palette.peachTint
    var badge: String? = nil
    var onPrimary: (() -> Void)? = nil
    var primaryLabel: String = "Tell me more"
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Text(eyebrow.uppercased())
                        .font(Theme.Font.body(10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.7)))
                        .overlay(Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 1))
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
                .font(Theme.Font.body(16, weight: .semibold))
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
                                .foregroundStyle(Theme.Palette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.white))
                                .overlay(Capsule().strokeBorder(Theme.Palette.ink.opacity(0.7), lineWidth: 1))
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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.white.opacity(0.5)))
                                .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Health stat tile

struct HealthStatTile: View {
    var label: String
    var value: String
    var progress: Double
    var icon: String
    var tint: Color = Theme.Palette.coral

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(Theme.Font.body(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            Text(value)
                .font(Theme.Font.body(18, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Capsule().fill(Theme.Palette.peachDeep.opacity(0.5))
                .frame(height: 8)
                .overlay(
                    GeometryReader { geo in
                        Capsule().fill(
                            LinearGradient(
                                colors: [Theme.Palette.sunny, tint],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                    }
                )
                .frame(height: 8)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
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
                    .foregroundStyle(Theme.Palette.inkMuted)
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
                Circle().fill(Theme.Palette.peachTint)
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.coralDeep)
            }
            TextField(placeholder, text: $text)
                .font(Theme.Font.bodyText)
                .submitLabel(.send)
                .onSubmit {
                    guard !text.isEmpty else { return }
                    Haptics.tap()
                    onSubmit?(text)
                    text = ""
                }
            Button {
                guard !text.isEmpty else { return }
                Haptics.tap()
                onSubmit?(text)
                text = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(text.isEmpty ? Theme.Palette.inkMuted.opacity(0.4) : Theme.Palette.coral))
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Theme.Palette.card)
        )
        .shadow(color: Theme.Palette.coral.opacity(0.10), radius: 14, x: 0, y: 6)
    }
}
