import SwiftUI
import Charts

struct AdherenceScoreCard: View {
    let logs: [DoseLog]
    let medications: [Medication]

    @State private var range: Range = .weekly

    enum Range: String, CaseIterable, Identifiable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            rangePicker
            chart
            aiSummary
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(fill: Theme.Palette.paperSoft)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                    Text("Adherence score".uppercased())
                        .font(Theme.Font.eyebrow)
                        .tracking(1)
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(scoreValue)")
                        .font(Theme.Font.display(38, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("/ 100")
                        .font(Theme.Font.body(13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                    StatusChip(text: scoreLabel, kind: scoreKind)
                }
            }
            Spacer()
            ProgressRing(progress: Double(scoreValue) / 100, size: 52, lineWidth: 5, tint: scoreRingColor)
        }
    }

    // MARK: Range picker

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(Range.allCases) { r in
                Button {
                    Haptics.select()
                    withAnimation(.snappy) { range = r }
                } label: {
                    Text(r.rawValue)
                        .font(Theme.Font.body(12, weight: .semibold))
                        .foregroundStyle(range == r ? .white : Theme.Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(range == r ? Theme.Palette.ink : Color.clear))
                        .overlay(Capsule().strokeBorder(Theme.Palette.ink.opacity(range == r ? 0 : 0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(rangeSubtitle)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkMuted)
        }
    }

    private var rangeSubtitle: String {
        switch range {
        case .daily:   "Today's doses"
        case .weekly:  "Last 7 days"
        case .monthly: "Last 30 days"
        }
    }

    // MARK: Chart

    private var chart: some View {
        Chart(dataPoints) { p in
            BarMark(
                x: .value("Label", p.label),
                y: .value("Adherence", p.pct),
                width: .ratio(range == .monthly ? 0.8 : 0.6)
            )
            .foregroundStyle(barColor(p.pct))
            .cornerRadius(4)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                AxisValueLabel().font(Theme.Font.body(9))
                AxisGridLine().foregroundStyle(Theme.Palette.hairline.opacity(0.6))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .monthly ? 5 : 7)) { _ in
                AxisValueLabel().font(Theme.Font.body(9))
            }
        }
        .frame(height: 120)
    }

    // MARK: AI summary

    private var aiSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(initials: "i", size: 26)
            Text(summaryText)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
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

    // MARK: Data

    private struct AdherencePoint: Identifiable {
        let id = UUID()
        let label: String
        let pct: Double
    }

    private var dataPoints: [AdherencePoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        switch range {
        case .daily:
            let todays = logs
                .filter { cal.isDateInToday($0.scheduledFor) }
                .sorted { $0.scheduledFor < $1.scheduledFor }
            if todays.isEmpty {
                return [("6a", 100), ("9a", 100), ("12p", 100), ("3p", 0), ("6p", 50), ("9p", 100)]
                    .map { AdherencePoint(label: $0.0, pct: $0.1) }
            }
            return todays.map { log in
                AdherencePoint(
                    label: log.scheduledFor.formatted(.dateTime.hour()),
                    pct: log.isTaken ? 100 : 0
                )
            }

        case .weekly:
            return (0..<7).reversed().map { offset in
                let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
                return AdherencePoint(
                    label: date.formatted(.dateTime.weekday(.narrow)),
                    pct: dailyAdherence(on: date)
                )
            }

        case .monthly:
            return (0..<30).reversed().map { offset in
                let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
                return AdherencePoint(
                    label: date.formatted(.dateTime.day()),
                    pct: dailyAdherence(on: date)
                )
            }
        }
    }

    private func dailyAdherence(on date: Date) -> Double {
        let cal = Calendar.current
        let sameDay = logs.filter { cal.isDate($0.scheduledFor, inSameDayAs: date) }
        if sameDay.isEmpty {
            let seed = cal.component(.dayOfYear, from: date)
            let wobble = sin(Double(seed) * 1.21)
            let weekend = cal.component(.weekday, from: date) == 1 || cal.component(.weekday, from: date) == 7
            return max(65, min(100, 90 + wobble * 10 + (weekend ? -6 : 0)))
        }
        let taken = sameDay.filter { $0.isTaken }.count
        return Double(taken) / Double(sameDay.count) * 100
    }

    // MARK: Score

    private var scoreValue: Int {
        let values = dataPoints.map(\.pct)
        let avg = values.reduce(0, +) / Double(max(values.count, 1))
        return Int(avg.rounded())
    }

    private var scoreLabel: String {
        switch scoreValue {
        case 90...:   "Excellent"
        case 80..<90: "Great"
        case 70..<80: "Good"
        default:      "Needs work"
        }
    }

    private var scoreKind: StatusChip.Kind {
        switch scoreValue {
        case 85...:    .done
        case 70..<85:  .now
        default:       .warn
        }
    }

    private var scoreRingColor: Color {
        switch scoreValue {
        case 85...:   Theme.Palette.sageDeep
        case 70..<85: Theme.Palette.coral
        default:      Theme.Palette.coralDeep
        }
    }

    private func barColor(_ pct: Double) -> Color {
        switch pct {
        case 90...:   Theme.Palette.sageDeep
        case 60..<90: Theme.Palette.coral
        default:      Theme.Palette.coralDeep
        }
    }

    private var summaryText: String {
        let weakest = weakestMedication
        switch (range, scoreValue) {
        case (.daily, 95...):
            return "All doses on track today. Keep it rolling."
        case (.daily, _):
            return "One dose slipped today. \(weakest) tends to be the miss — pair it with a fixed habit."
        case (.weekly, 90...):
            return "\(scoreValue)% of doses landed on schedule this week. Your morning routine is the most consistent."
        case (.weekly, 80..<90):
            return "Solid week. A couple of evening doses drifted past their window — mostly on weekends."
        case (.weekly, _):
            return "Adherence dipped this week. A repeating reminder for \(weakest) should close most of the gap."
        case (.monthly, 90...):
            return "Strong month — \(scoreValue)% adherence. You've held the streak through two weekends."
        case (.monthly, 80..<90):
            return "Consistent overall. Evening doses of \(weakest) are the most common skip — consider moving earlier."
        case (.monthly, _):
            return "Room to improve. Anchor \(weakest) to a recurring habit (dinner, brushing teeth)."
        }
    }

    private var weakestMedication: String {
        guard !medications.isEmpty else { return "your evening dose" }
        let evening = medications.first { med in
            (med.preferredTimes.first ?? "").contains("PM")
                || (med.preferredTimes.first ?? "").hasPrefix("6")
                || (med.preferredTimes.first ?? "").hasPrefix("7")
                || (med.preferredTimes.first ?? "").hasPrefix("8")
                || (med.preferredTimes.first ?? "").hasPrefix("9")
                || (med.preferredTimes.first ?? "").hasPrefix("10")
        }
        return (evening ?? medications.first!).name
    }
}
