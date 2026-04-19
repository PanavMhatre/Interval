import SwiftUI
import Charts
import SwiftData

struct TrendSheetTarget: Identifiable, Equatable {
    let metric: String

    var id: String { metricToken(metric) }
}

struct MetricTrendSheet: View {
    let metric: String
    let labs: [LabResult]

    @Environment(\.dismiss) private var dismiss

    private var metricLabs: [LabResult] {
        labs
            .filter { metricToken($0.metric) == metricToken(metric) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private var current: LabResult? { metricLabs.last }
    private var previous: LabResult? { metricLabs.dropLast().last }
    private var earliest: LabResult? { metricLabs.first }

    private var accent: Color {
        switch current?.status {
        case .normal:
            Theme.Palette.sageDeep
        case .low, .high:
            Theme.Palette.coralDeep
        case nil:
            Theme.Palette.primary
        }
    }

    private var accentFill: Color {
        switch current?.status {
        case .normal:
            Theme.Palette.mint
        case .low, .high:
            Theme.Palette.peachTint
        case nil:
            Theme.Palette.surfaceContainerLow
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = metricLabs.map(\.value)
        let lows = metricLabs.compactMap(\.referenceLow)
        let highs = metricLabs.compactMap(\.referenceHigh)
        let allValues = values + lows + highs

        guard let minValue = allValues.min(), let maxValue = allValues.max() else {
            return 0...1
        }

        let span = max(maxValue - minValue, 0.4)
        let padding = span * 0.18
        return (minValue - padding)...(maxValue + padding)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    if let current {
                        summaryHeader(current)
                        aiExplanationCard
                        chartCard
                        statRow
                        resultTimeline
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.Palette.paper)
            .navigationTitle("\(metric) Trend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Theme.Font.body(14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primary)
                }
            }
        }
    }

    private func summaryHeader(_ current: LabResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(current.metric)
                .font(Theme.Font.display(28, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(valueText(for: current))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.ink)

                Text(current.unit)
                    .font(Theme.Font.body(17, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkMuted)
            }

            HStack(spacing: 10) {
                statusPill(for: current.status)

                Text(deltaText)
                    .font(Theme.Font.body(13, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    private var aiExplanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primary)
                Text("Apple Intelligence explanation".uppercased())
                    .font(Theme.Font.body(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Palette.primary)
            }

            Text(aiExplanationTitle)
                .font(Theme.Font.body(16, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)

            Text(aiExplanationBody)
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.paperSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trend line")
                .font(Theme.Font.body(16, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)

            Chart {
                if let firstDate = earliest?.capturedAt,
                   let lastDate = current?.capturedAt,
                   let low = current?.referenceLow,
                   let high = current?.referenceHigh {
                    RectangleMark(
                        xStart: .value("Start", firstDate),
                        xEnd: .value("End", lastDate),
                        yStart: .value("Low Band", low),
                        yEnd: .value("High Band", high)
                    )
                    .foregroundStyle(accentFill.opacity(0.22))
                }

                if let low = current?.referenceLow {
                    RuleMark(y: .value("Low", low))
                        .foregroundStyle(Theme.Palette.primary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }

                if let high = current?.referenceHigh {
                    RuleMark(y: .value("High", high))
                        .foregroundStyle(Theme.Palette.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }

                ForEach(metricLabs, id: \.persistentModelID) { result in
                    AreaMark(
                        x: .value("Date", result.capturedAt),
                        y: .value("Value", result.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", result.capturedAt),
                        y: .value("Value", result.value)
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", result.capturedAt),
                        y: .value("Value", result.value)
                    )
                    .foregroundStyle(accent)
                    .symbolSize(result.persistentModelID == current?.persistentModelID ? 90 : 55)
                }
            }
            .frame(height: 220)
            .chartLegend(.hidden)
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: metricLabs.map(\.capturedAt)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(Theme.Palette.surfaceContainerLow.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text(referenceCopy)
                .font(Theme.Font.body(12, weight: .medium))
                .foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLowest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.3), radius: 12, y: 6)
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            trendStatCard(
                label: "Latest",
                value: current.map(valueText(for:)) ?? "—",
                caption: current.map { shortDate($0.capturedAt) } ?? "No date"
            )

            trendStatCard(
                label: "Previous",
                value: previous.map(valueText(for:)) ?? "—",
                caption: previous.map { shortDate($0.capturedAt) } ?? "Waiting for more data"
            )

            trendStatCard(
                label: "Range",
                value: referenceRangeText,
                caption: current?.status.displayName ?? "Unknown"
            )
        }
    }

    private func trendStatCard(label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Font.body(10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.Palette.inkMuted)

            Text(value)
                .font(Theme.Font.body(18, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(caption)
                .font(Theme.Font.body(11, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineLimit(2)
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
    }

    private var resultTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Result history")
                .font(Theme.Font.body(16, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)

            ForEach(Array(metricLabs.reversed()), id: \.persistentModelID) { result in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shortDate(result.capturedAt))
                            .font(Theme.Font.body(13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(result.document?.title ?? result.document?.provider ?? "Imported result")
                            .font(Theme.Font.body(12, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(valueText(for: result)) \(result.unit)")
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)

                    statusPill(for: result.status)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.Palette.surfaceContainerLowest)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No linked results yet")
                .font(Theme.Font.display(24, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)

            Text("Once Interval has lab data for this metric, the trend view will appear here.")
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLow)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
        )
    }

    private func statusPill(for status: LabStatus) -> some View {
        Text(status.displayName)
            .font(Theme.Font.body(13, weight: .semibold))
            .foregroundStyle(status == .normal ? Theme.Palette.sageDeep : Theme.Palette.coralDeep)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(status == .normal ? Theme.Palette.mint : Theme.Palette.peachTint))
    }

    private func valueText(for lab: LabResult) -> String {
        if lab.value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(lab.value))"
        }
        return String(format: "%.1f", lab.value)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var referenceRangeText: String {
        guard let current, let low = current.referenceLow, let high = current.referenceHigh else {
            return "—"
        }

        return "\(formattedRangeValue(low))–\(formattedRangeValue(high))"
    }

    private var referenceCopy: String {
        guard let current else { return "No reference range loaded yet." }
        guard current.referenceLow != nil, current.referenceHigh != nil else {
            return "This result does not include a reference range in the record."
        }

        if metricLabs.count < 2 {
            return "You have one result so far. The next result will make the trend more meaningful."
        }

        return "\(deltaText) Based on \(metricLabs.count) recorded results."
    }

    private var deltaText: String {
        guard let current else { return "No change data yet." }
        guard let previous else { return "This is your first recorded result for this metric." }

        let delta = current.value - previous.value
        if abs(delta) < 0.01 {
            return "Your latest result is steady compared with the previous lab."
        }

        let direction = delta < 0 ? "down" : "up"
        return "Your latest result is \(formattedRangeValue(abs(delta))) \(current.unit) \(direction) versus the previous lab."
    }

    private func formattedRangeValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private var aiExplanationTitle: String {
        switch metricInfo.kind {
        case .a1c:
            return "What A1C measures"
        case .vitaminD:
            return "What vitamin D shows"
        case .iron:
            return "What iron means"
        case .cholesterol:
            return "What this cholesterol marker tracks"
        case .thyroid:
            return "What this thyroid marker means"
        case .kidney:
            return "What this kidney marker tracks"
        case .bloodCount:
            return "What this blood count shows"
        case .glucose:
            return "What this glucose result means"
        case .vitaminB12:
            return "What vitamin B12 supports"
        case .generic:
            return "What this lab is tracking"
        }
    }

    private var aiExplanationBody: String {
        metricInfo.description
    }

    private var metricInfo: MetricInfo {
        let token = metricToken(metric)

        if token.contains("a1c") || token.contains("hba1c") || token.contains("hemoglobina1c") {
            return MetricInfo(
                kind: .a1c,
                description: "A1C estimates your average blood sugar over about the last 3 months, so it helps show longer-term glucose control instead of a single-day reading."
            )
        }

        if token.contains("vitamind") || token == "25ohvitamind" || token.contains("25hydroxyvitamind") {
            return MetricInfo(
                kind: .vitaminD,
                description: "Vitamin D helps with bone strength, muscle function, and immune support. This lab shows whether your level is low, in range, or higher than expected."
            )
        }

        if token == "iron" || token.contains("serumiron") {
            return MetricInfo(
                kind: .iron,
                description: "Iron helps your body make hemoglobin so oxygen can move through your blood. Low iron can happen even before anemia shows up clearly on other labs."
            )
        }

        if token.contains("ldl") || token.contains("hdl") || token.contains("cholesterol") || token.contains("triglyceride") {
            return MetricInfo(
                kind: .cholesterol,
                description: "This cholesterol-related marker helps show how fats are moving in your blood and can add context around heart and blood vessel risk over time."
            )
        }

        if token.contains("tsh") || token.contains("thyroid") || token.contains("t4") || token.contains("t3") {
            return MetricInfo(
                kind: .thyroid,
                description: "This thyroid marker helps show how your body is regulating energy, temperature, and metabolism. Trends can matter as much as a single value."
            )
        }

        if token.contains("creatinine") || token.contains("egfr") || token.contains("bun") {
            return MetricInfo(
                kind: .kidney,
                description: "This kidney marker helps show how well your kidneys are filtering and balancing waste, fluids, or electrolytes in your blood."
            )
        }

        if token.contains("hemoglobin") || token.contains("hematocrit") || token.contains("rbc") || token.contains("wbc") || token.contains("platelet") {
            return MetricInfo(
                kind: .bloodCount,
                description: "This blood-count marker helps show how your body is carrying oxygen, fighting infection, or clotting. It is usually interpreted alongside related blood count results."
            )
        }

        if token.contains("glucose") {
            return MetricInfo(
                kind: .glucose,
                description: "Glucose is the sugar your body uses for energy. This result reflects one moment in time, while its trend can show whether your levels are becoming more stable or drifting."
            )
        }

        if token.contains("b12") || token.contains("vitaminb12") {
            return MetricInfo(
                kind: .vitaminB12,
                description: "Vitamin B12 helps with nerve health and red blood cell production. Low levels can contribute to fatigue, numbness, or anemia-related symptoms."
            )
        }

        return MetricInfo(
            kind: .generic,
            description: "\(metric) is one of your tracked lab markers. Use this trend to see how it is moving over time and compare it with the reference range shown for each result."
        )
    }
}

private struct MetricInfo {
    let kind: MetricKind
    let description: String
}

private enum MetricKind {
    case a1c
    case vitaminD
    case iron
    case cholesterol
    case thyroid
    case kidney
    case bloodCount
    case glucose
    case vitaminB12
    case generic
}

func metricToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
}
