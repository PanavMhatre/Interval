import SwiftUI
import Charts

enum TrendMetric: String, Identifiable, CaseIterable {
    case steps, sleep, water, meds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .water: "Water"
        case .meds:  "Today's meds"
        }
    }

    var eyebrow: String {
        switch self {
        case .steps: "Movement"
        case .sleep: "Rest"
        case .water: "Hydration"
        case .meds:  "Adherence"
        }
    }

    var unitLabel: String {
        switch self {
        case .steps: "steps / day"
        case .sleep: "hours / night"
        case .water: "cups / day"
        case .meds:  "% on schedule"
        }
    }

    var icon: String {
        switch self {
        case .steps: "figure.walk"
        case .sleep: "moon.fill"
        case .water: "drop.fill"
        case .meds:  "pills.fill"
        }
    }

    var tint: Color {
        switch self {
        case .steps: Theme.Palette.coral
        case .sleep: Theme.Palette.lilac
        case .water: Theme.Palette.coral
        case .meds:  Theme.Palette.coralDeep
        }
    }
}

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct TrendDetailView: View {
    let metric: TrendMetric
    @Environment(\.dismiss) private var dismiss
    @State private var range: Range = .week

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    header
                    rangePicker
                    chartCard
                    summaryRow
                    insightCard
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.Palette.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(Theme.Font.body(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.coralDeep)
                    }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: metric.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(metric.tint)
                Text(metric.eyebrow.uppercased()).eyebrowStyle()
            }
            Text(metric.title)
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Palette.ink)
            Text(metric.unitLabel)
                .font(Theme.Font.bodyText)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    // MARK: Range tabs

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(Range.allCases) { r in
                Button {
                    Haptics.select()
                    withAnimation(.snappy) { range = r }
                } label: {
                    Text(r.rawValue)
                        .font(Theme.Font.body(13, weight: .semibold))
                        .foregroundStyle(range == r ? .white : Theme.Palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(range == r ? Theme.Palette.ink : Color.clear))
                        .overlay(Capsule().strokeBorder(Theme.Palette.ink.opacity(range == r ? 0 : 0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Last \(range == .week ? "7 days" : "30 days")")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkMuted)
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trend".uppercased()).eyebrowStyle()
                Spacer()
                Text(trendLabel)
                    .font(Theme.Font.body(12, weight: .semibold))
                    .foregroundStyle(metric.tint)
            }

            Chart(points) { p in
                AreaMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [metric.tint.opacity(0.32), metric.tint.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.value)
                )
                .foregroundStyle(metric.tint)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                if range == .week {
                    PointMark(
                        x: .value("Date", p.date),
                        y: .value("Value", p.value)
                    )
                    .foregroundStyle(metric.tint)
                    .symbolSize(36)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    AxisGridLine().foregroundStyle(Theme.Palette.hairline.opacity(0.6))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                    AxisGridLine().foregroundStyle(Theme.Palette.hairline.opacity(0.6))
                }
            }
            .frame(height: 220)
        }
        .padding(Theme.Space.md)
        .softCard()
    }

    // MARK: Summary

    private var summaryRow: some View {
        HStack(spacing: Theme.Space.sm) {
            summaryTile(label: "Avg", value: formatted(average))
            summaryTile(label: "High", value: formatted(maxVal))
            summaryTile(label: "Low", value: formatted(minVal))
        }
    }

    private func summaryTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Font.body(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Palette.inkMuted)
            Text(value)
                .font(Theme.Font.display(18, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
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

    private var insightCard: some View {
        InsightCard(
            eyebrow: "Pattern",
            title: insight.title,
            detail: insight.detail,
            accent: metric.tint,
            background: Theme.Palette.peachSoft,
            primaryLabel: "See details"
        )
    }

    // MARK: Data

    private var points: [TrendPoint] {
        TrendData.series(for: metric, days: range == .week ? 7 : 30)
    }

    private var average: Double { points.map(\.value).reduce(0, +) / Double(max(points.count, 1)) }
    private var maxVal: Double { points.map(\.value).max() ?? 0 }
    private var minVal: Double { points.map(\.value).min() ?? 0 }

    private var trendLabel: String {
        let n = max(points.count / 3, 1)
        let first = points.prefix(n).map(\.value).reduce(0, +) / Double(n)
        let last  = points.suffix(n).map(\.value).reduce(0, +) / Double(n)
        let diff  = last - first
        let pct   = abs(diff) / max(abs(first), 0.0001)
        if pct < 0.04 { return "→ steady" }
        return diff > 0 ? "↑ trending up" : "↓ trending down"
    }

    private func formatted(_ v: Double) -> String {
        switch metric {
        case .steps: return Int(v.rounded()).formatted(.number)
        case .sleep:
            let h = Int(v)
            let m = Int((v - Double(h)) * 60)
            return "\(h)h \(m)m"
        case .water: return "\(Int(v.rounded())) / 8"
        case .meds:  return "\(Int(v.rounded()))%"
        }
    }

    private var insight: (title: String, detail: String) {
        switch (metric, range) {
        case (.steps, .week):  ("Weekend dips",        "You walk ~20% less on weekends. A short Saturday walk would steady the average.")
        case (.steps, .month): ("Gradual climb",       "You're up roughly 800 steps/day vs. last month. The trend is holding.")
        case (.sleep, .week):  ("Midweek crunch",      "Wednesday nights drop below 6h. Tightening the Tuesday wind-down may help.")
        case (.sleep, .month): ("Average trending up", "You're sleeping 22 minutes longer per night compared to early last month.")
        case (.water, .week):  ("Afternoon drop-off",  "You hit 3/8 most days but stall after 2pm. An afternoon reminder could close the gap.")
        case (.water, .month): ("Hydration plateau",   "Consistent at ~4 cups/day. Pushing to 6 would align with your activity level.")
        case (.meds, .week):   ("Strong adherence",    "94% taken on schedule. Two evening doses slipped past the window — both on weekends.")
        case (.meds, .month):  ("Consistent overall",  "91% monthly adherence. The most common skip is the 10pm dose.")
        }
    }
}

enum TrendData {
    static func series(for metric: TrendMetric, days: Int) -> [TrendPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<days).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            return TrendPoint(date: date, value: value(for: metric, dayOffset: offset, days: days))
        }
    }

    private static func value(for metric: TrendMetric, dayOffset: Int, days: Int) -> Double {
        let t = Double(days - dayOffset) / Double(days)
        let wobble = sin(Double(dayOffset) * 1.37)
        let weekend = (dayOffset % 7) >= 5
        switch metric {
        case .steps:
            let base = 5200 + t * 1800
            return max(2200, base + wobble * 1200 + (weekend ? -1400 : 0))
        case .sleep:
            let base = 6.8 + t * 0.5
            return max(4.8, min(9, base + wobble * 0.55 + (weekend ? 0.6 : 0)))
        case .water:
            let base = 3.5 + t * 1.3
            return max(1, min(8, base + wobble * 1.1))
        case .meds:
            let base = 84 + t * 10
            return max(70, min(100, base + wobble * 6))
        }
    }
}

#Preview("Steps") { TrendDetailView(metric: .steps) }
#Preview("Sleep") { TrendDetailView(metric: .sleep) }
#Preview("Water") { TrendDetailView(metric: .water) }
#Preview("Meds")  { TrendDetailView(metric: .meds) }
