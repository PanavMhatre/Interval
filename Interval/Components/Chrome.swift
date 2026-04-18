import SwiftUI

// MARK: - Hairline

struct Hairline: View {
    var color: Color = Theme.Palette.hairline
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

// MARK: - Dashed hairline (paper sketch feel)

struct DashedHairline: View {
    var color: Color = Theme.Palette.hairline
    var body: some View {
        Line()
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

// MARK: - Pill tag

struct PillTag: View {
    var text: String
    var fill: Color = Theme.Palette.paperSoft
    var border: Color = Theme.Palette.hairline
    var foreground: Color = Theme.Palette.ink
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(Theme.Font.caption)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(fill)
        )
        .overlay(
            Capsule().strokeBorder(border, lineWidth: 1)
        )
    }
}

// MARK: - Avatar circle

struct AvatarCircle: View {
    var initials: String
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Theme.Palette.peachTint)
            .overlay(
                Circle().strokeBorder(Theme.Palette.coral.opacity(0.4), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(Theme.Font.body(size * 0.42, weight: .semibold))
                    .foregroundStyle(Theme.Palette.coralDeep)
            )
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    var title: String
    var icon: String? = "arrow.right"
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.Font.body(16, weight: .semibold))
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule().fill(enabled ? Theme.Palette.coral : Theme.Palette.inkMuted.opacity(0.4))
            )
            .shadow(color: Theme.Palette.coral.opacity(enabled ? 0.28 : 0), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Ghost (outlined) button

struct GhostButton: View {
    var title: String
    var icon: String? = nil
    var dashed: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                }
                Text(title).font(Theme.Font.body(15, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(
                    Theme.Palette.ink,
                    style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [5, 4] : [])
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sketch-style tab chip row

struct ScreenChipRow: View {
    @Binding var selected: Int
    let chips: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips.indices, id: \.self) { idx in
                    Button {
                        Haptics.select()
                        withAnimation(.snappy) { selected = idx }
                    } label: {
                        HStack(spacing: 6) {
                            Text(String(format: "%02d", idx + 1))
                                .font(Theme.Font.mono(11, weight: .semibold))
                                .foregroundStyle(selected == idx ? .white.opacity(0.8) : Theme.Palette.inkMuted)
                            Text(chips[idx])
                                .font(Theme.Font.display(14, weight: .semibold))
                                .foregroundStyle(selected == idx ? .white : Theme.Palette.ink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(selected == idx ? Theme.Palette.ink : Color.clear)
                        )
                        .overlay(
                            Capsule().strokeBorder(Theme.Palette.ink.opacity(selected == idx ? 0 : 0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Status chip (DONE / NOW / LATER / NEW / etc.)

struct StatusChip: View {
    enum Kind {
        case done, now, later, newItem, warn, flag, skip, ask
        var fill: Color {
            switch self {
            case .done: Theme.Palette.mint
            case .now: Theme.Palette.peachTint
            case .later: Theme.Palette.paperSoft
            case .newItem: Theme.Palette.peachTint
            case .warn: Theme.Palette.peachTint
            case .flag: Theme.Palette.peachTint
            case .skip: Theme.Palette.paperSoft
            case .ask: Theme.Palette.peachTint
            }
        }
        var foreground: Color {
            switch self {
            case .done: Theme.Palette.sageDeep
            case .now, .newItem, .warn, .flag, .ask: Theme.Palette.coralDeep
            case .later, .skip: Theme.Palette.inkMuted
            }
        }
        var border: Color {
            switch self {
            case .done: Theme.Palette.sageDeep.opacity(0.3)
            default: foreground.opacity(0.35)
            }
        }
    }

    var text: String
    var kind: Kind

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.body(10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(kind.foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(kind.fill))
            .overlay(Capsule().strokeBorder(kind.border, lineWidth: 1))
    }
}

// MARK: - Ring indicator (for meds taken)

struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 62
    var lineWidth: CGFloat = 6
    var tint: Color = Theme.Palette.coral
    var track: Color = Theme.Palette.peachTint

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.7), value: progress)
        }
        .frame(width: size, height: size)
    }
}
