import SwiftUI

struct SideEffectsCard: View {
    let tips: [SideEffectTip]
    @State private var expanded = false

    var body: some View {
        Group {
            if tips.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    header
                    VStack(spacing: 8) {
                        ForEach(visibleTips) { tip in
                            tipRow(tip)
                        }
                    }
                    if tips.count > 3 {
                        Button {
                            Haptics.tap()
                            withAnimation(.smooth) { expanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(expanded ? "Show less" : "Show all \(tips.count)")
                                    .font(Theme.Font.body(13, weight: .semibold))
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(Theme.Palette.coralDeep)
                            .padding(.top, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Palette.peachSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.coral.opacity(0.35), lineWidth: 1)
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "flag.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.coralDeep)
            Text("Heads up today".uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.coralDeep)
            Spacer()
            Text("\(tips.count)")
                .font(Theme.Font.body(10, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.Palette.card))
                .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
        }
    }

    private var visibleTips: [SideEffectTip] {
        expanded ? tips : Array(tips.prefix(3))
    }

    private func tipRow(_ tip: SideEffectTip) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.card)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(tip.tint.opacity(0.35), lineWidth: 1))
                Image(systemName: tip.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tip.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tip.effect)
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    severityDot(tip.severity)
                    Text(tip.source)
                        .font(Theme.Font.body(11, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .lineLimit(1)
                }
                Text(tip.mitigation)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

    @ViewBuilder
    private func severityDot(_ severity: SideEffectTip.Severity) -> some View {
        Circle()
            .fill(severityColor(severity))
            .frame(width: 5, height: 5)
    }

    private func severityColor(_ severity: SideEffectTip.Severity) -> Color {
        switch severity {
        case .important: Theme.Palette.coralDeep
        case .caution:   Theme.Palette.coral
        case .info:      Theme.Palette.inkMuted
        }
    }
}
