import SwiftUI
import SwiftData
import Foundation
import FoundationModels

struct ChatMessage: Identifiable, Hashable {
    enum Sender { case user, ai }
    let id = UUID()
    let sender: Sender
    var text: String
    var chips: [String] = []
    var isStreaming: Bool = false
}

private enum ChatCalloutTone: String, Hashable {
    case positive
    case caution

    var fill: Color {
        switch self {
        case .positive: Theme.Palette.secondaryFixed
        case .caution: Theme.Palette.errorContainer
        }
    }

    var border: Color {
        switch self {
        case .positive: Theme.Palette.secondaryContainer.opacity(0.45)
        case .caution: Theme.Palette.error.opacity(0.22)
        }
    }

    var foreground: Color {
        switch self {
        case .positive: Theme.Palette.secondary
        case .caution: Theme.Palette.error
        }
    }

    var icon: String {
        switch self {
        case .positive: "lightbulb.fill"
        case .caution: "exclamationmark.triangle.fill"
        }
    }
}

private enum ChatRenderBlock: Hashable, Identifiable {
    case paragraph(String)
    case labGraphic(String)
    case trendGraphic(String)
    case medicationGraphic(String)
    case simulationGraphic(String)
    case interactionGraphic(String, String)
    case callout(text: String, tone: ChatCalloutTone)

    var id: String {
        switch self {
        case .paragraph(let text):
            return "paragraph-\(text)"
        case .labGraphic(let metric):
            return "graphic-\(metric)"
        case .trendGraphic(let metric):
            return "trend-\(metric)"
        case .medicationGraphic(let medication):
            return "med-\(medication)"
        case .simulationGraphic(let medication):
            return "simulation-\(medication)"
        case .interactionGraphic(let primary, let secondary):
            return "interaction-\(primary)-\(secondary)"
        case .callout(let text, let tone):
            return "callout-\(tone.rawValue)-\(text)"
        }
    }
}

struct ChatView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query(sort: [SortDescriptor(\LabResult.capturedAt, order: .reverse)]) private var labs: [LabResult]

    @State private var ai = IntervalAI()
    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var responding = false
    @State private var showingLoadedSummary = false
    @FocusState private var inputFocused: Bool

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Palette.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        contextPreamble
                        if case .unavailable(let msg) = ai.status {
                            unavailableBanner(msg)
                        }
                        ForEach($messages) { $msg in
                            messageBubble(msg).id(msg.id)
                        }
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)
                }
                .onChange(of: messages.count) {
                    withAnimation(.smooth) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: messages.last?.text) {
                    withAnimation(.smooth) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
            }

            inputBar
        }
        .background(Theme.Palette.paper)
        .onAppear {
            ai.prepare(with: context)
            if messages.isEmpty { seed() }
        }
    }

    // MARK: Header

    private var header: some View {
        SectionHeader(
            eyebrow: "Health chat",
            title: "Chat with Interval",
            subtitle: "Ask about your meds, labs, and health history."
        )
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.Palette.paper)
    }

    private var contextPreamble: some View {
        VStack(alignment: .leading, spacing: showingLoadedSummary ? 14 : 0) {
            Button {
                Haptics.select()
                withAnimation(.smooth(duration: 0.22)) {
                    showingLoadedSummary.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loaded about you".uppercased())
                            .font(Theme.Font.eyebrow)
                            .tracking(1)
                            .foregroundStyle(Theme.Palette.inkMuted)

                        Text(showingLoadedSummary ? "Hide the chart summary" : "Tap to review what chat is using")
                            .font(Theme.Font.body(13, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }

                    Spacer()

                    Image(systemName: showingLoadedSummary ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.Palette.surfaceContainerLowest)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
                        )
                }
            }
            .buttonStyle(.plain)

            if showingLoadedSummary {
                VStack(alignment: .leading, spacing: 12) {
                    Hairline(color: Theme.Palette.outlineVariant.opacity(0.8))

                    Text(contextSummaryText)
                        .font(Theme.Font.body(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        contextSummaryRow("Conditions", value: conditionsSummary)
                        contextSummaryRow("Allergies", value: allergiesSummary)
                        contextSummaryRow("Medications", value: medicationsSummary)
                        contextSummaryRow("Latest lab", value: latestLabSummary)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(fill: Theme.Palette.paperSoft)
    }

    private func unavailableBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.coralDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Intelligence off").font(Theme.Font.body(13, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
                Text(msg).font(Theme.Font.caption).foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.Palette.peachTint))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.Palette.coral.opacity(0.4), lineWidth: 1))
    }

    // MARK: Message bubble

    @ViewBuilder
    private func messageBubble(_ msg: ChatMessage) -> some View {
        switch msg.sender {
        case .ai:
            VStack(alignment: .leading, spacing: 10) {
                if msg.text.isEmpty && msg.isStreaming {
                    thinkingDots
                } else {
                    assistantMessageCard(msg.text)
                        .animation(.smooth(duration: 0.18), value: msg.text)
                }

                if !msg.chips.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(msg.chips, id: \.self) { chip in
                            Button {
                                Haptics.select()
                                send(chip)
                            } label: {
                                Text(chip)
                                    .font(Theme.Font.body(12, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: 150, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Theme.Palette.surfaceContainerLowest)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .user:
            HStack {
                Spacer(minLength: 40)
                paragraphText(msg.text)
                    .foregroundStyle(Theme.Palette.onPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.Palette.primary)
                    )
                    .shadow(color: Theme.Shadow.warm.opacity(0.5), radius: 10, y: 5)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var thinkingDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.Palette.coralDeep)
                    .frame(width: 6, height: 6)
                    .opacity(0.4)
                    .scaleEffect(responding ? 1 : 0.7)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15), value: responding)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 104, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.Palette.hairline, lineWidth: 1))
    }

    // MARK: Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.Palette.hairline)
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text("Ask about your health…")
                        .foregroundStyle(Theme.Palette.inkMuted),
                    axis: .vertical
                )
                    .font(Theme.Font.bodyText)
                    .foregroundStyle(Theme.Palette.ink)
                    .tint(Theme.Palette.coralDeep)
                    .focused($inputFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Palette.paperSoft))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                    .disabled(responding)

                Button {
                    send(draft)
                } label: {
                    Image(systemName: responding ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(draft.isEmpty && !responding ? Theme.Palette.inkMuted.opacity(0.4) : Theme.Palette.primary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.isEmpty || responding)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.Palette.paper)
        }
    }

    // MARK: Conversation

    private func seed() {
        let firstName = profile?.name.components(separatedBy: " ").first ?? "there"
        messages = [
            ChatMessage(
                sender: .ai,
                text: "Hi \(firstName). I have your latest conditions, meds, and labs loaded.\n\nAsk me anything.",
                chips: ["What does my A1C mean?", "Any risky meds?", "Am I low on iron?"]
            )
        ]
    }

    private func contextTag(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.body(12, weight: .medium))
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Palette.surfaceContainerLowest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
            )
            .shadow(color: Theme.Shadow.ambient.opacity(0.25), radius: 6, y: 3)
    }

    private var contextSummaryText: String {
        "Chat is grounding replies in your profile, medication list, allergies, and recent lab results so answers stay specific to your record."
    }

    private var conditionsSummary: String {
        summarizedList(profile?.conditions, empty: "No conditions loaded")
    }

    private var allergiesSummary: String {
        summarizedList(profile?.allergies, empty: "No allergies loaded")
    }

    private var medicationsSummary: String {
        let names = medications.map(\.name)
        return summarizedList(names, empty: "No active medications loaded")
    }

    private var latestLabSummary: String {
        guard let latest = labs.first else { return "No recent labs loaded" }
        return "\(latest.metric) \(latest.valueText) · \(latest.status.displayName)"
    }

    private func summarizedList(_ items: [String]?, empty: String) -> String {
        guard let items, !items.isEmpty else { return empty }
        return items.joined(separator: ", ")
    }

    private func contextSummaryRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Theme.Font.body(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.inkMuted)

            Text(value)
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func assistantMessageCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(messageBlocks(from: text)) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLowest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.28), radius: 10, y: 5)
    }

    @ViewBuilder
    private func blockView(_ block: ChatRenderBlock) -> some View {
        switch block {
        case .paragraph(let text):
            paragraphText(text)
                .foregroundStyle(Theme.Palette.ink)
        case .labGraphic(let metric):
            labGraphicCard(metric)
        case .trendGraphic(let metric):
            trendGraphicCard(metric)
        case .medicationGraphic(let medication):
            medicationGraphicCard(medication)
        case .simulationGraphic(let medication):
            simulationGraphicCard(medication)
        case .interactionGraphic(let primary, let secondary):
            interactionGraphicCard(primary, secondary)
        case .callout(let text, let tone):
            calloutCard(text: text, tone: tone)
        }
    }

    private func paragraphText(_ text: String) -> Text {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let attributed = try? AttributedString(markdown: trimmed) {
            return Text(attributed)
        }
        return Text(trimmed)
    }

    private func messageBlocks(from text: String) -> [ChatRenderBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [ChatRenderBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.isEmpty else {
                paragraphLines.removeAll()
                return
            }
            blocks.append(.paragraph(paragraph))
            paragraphLines.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let block = parseGraphicToken(line) {
                flushParagraph()
                blocks.append(block)
                continue
            }

            if let callout = parseCalloutToken(line) {
                flushParagraph()
                blocks.append(callout)
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        return blocks.isEmpty && !text.isEmpty ? [.paragraph(text)] : blocks
    }

    private func parseGraphicToken(_ line: String) -> ChatRenderBlock? {
        guard line.hasPrefix("[[graphic:"), line.hasSuffix("]]") else { return nil }

        let payload = String(line.dropFirst(10).dropLast(2))
        let parts = payload.split(separator: ":").map(String.init)
        guard let kind = parts.first else { return nil }

        switch kind {
        case "lab":
            guard parts.count >= 2 else { return nil }
            return .labGraphic(parts[1])
        case "trend":
            guard parts.count >= 2 else { return nil }
            return .trendGraphic(parts[1])
        case "med":
            guard parts.count >= 2 else { return nil }
            return .medicationGraphic(parts[1])
        case "simulation":
            guard parts.count >= 2 else { return nil }
            return .simulationGraphic(parts[1])
        case "interaction":
            guard parts.count >= 3 else { return nil }
            return .interactionGraphic(parts[1], parts[2])
        default:
            return nil
        }
    }

    private func parseCalloutToken(_ line: String) -> ChatRenderBlock? {
        guard line.hasPrefix("[[callout:"), line.hasSuffix("]]") else { return nil }
        let payload = String(line.dropFirst(10).dropLast(2))
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let tone = ChatCalloutTone(rawValue: parts[0]) else { return nil }
        return .callout(text: parts[1], tone: tone)
    }

    @ViewBuilder
    private func labGraphicCard(_ metric: String) -> some View {
        if let lab = matchingLab(for: metric) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(lab.metric) Range")
                        .font(Theme.Font.body(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)

                    Spacer()

                    Text(lab.status.displayName.uppercased())
                        .font(Theme.Font.body(10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(statusForeground(for: lab.status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(statusFill(for: lab.status)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            HStack(spacing: 0) {
                                Rectangle().fill(Theme.Palette.primaryFixed)
                                Rectangle().fill(Theme.Palette.secondaryFixed)
                                Rectangle().fill(Theme.Palette.errorContainer)
                            }

                            Circle()
                                .fill(Theme.Palette.inverseSurface)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Theme.Palette.surfaceContainerLowest, lineWidth: 2)
                                )
                                .offset(x: max(0, min(geo.size.width - 14, geo.size.width * rangePosition(for: lab) - 7)))
                        }
                    }
                    .frame(height: 12)
                    .clipShape(Capsule())

                    HStack {
                        Text(referenceLabel(for: lab.referenceLow))
                        Spacer()
                        Text("\(compactValueText(for: lab)) (You)")
                        Spacer()
                        Text(referenceLabel(for: lab.referenceHigh))
                    }
                    .font(Theme.Font.body(11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Palette.paperSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func trendGraphicCard(_ metric: String) -> some View {
        if let current = matchingLab(for: metric), let previous = previousLab(for: metric) {
            let delta = current.value - previous.value
            let improved = delta < 0

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(current.metric) Trend")
                        .font(Theme.Font.body(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)

                    Spacer()

                    Text(trendDeltaText(delta, unit: current.unit))
                        .font(Theme.Font.body(10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(improved ? Theme.Palette.primary : Theme.Palette.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(improved ? Theme.Palette.primaryFixed : Theme.Palette.secondaryFixed)
                        )
                }

                HStack(spacing: 10) {
                    trendMetricTile(label: "Previous", value: compactValueText(for: previous), caption: shortDate(previous.capturedAt))

                    Image(systemName: improved ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(improved ? Theme.Palette.primary : Theme.Palette.secondary)

                    trendMetricTile(label: "Latest", value: compactValueText(for: current), caption: shortDate(current.capturedAt))
                }

                Capsule()
                    .fill(Theme.Palette.surfaceContainer)
                    .frame(height: 8)
                    .overlay(
                        GeometryReader { proxy in
                            let start = min(trendPosition(for: previous), trendPosition(for: current))
                            let end = max(trendPosition(for: previous), trendPosition(for: current))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Theme.Palette.primaryFixedDim, improved ? Theme.Palette.primary : Theme.Palette.secondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(16, proxy.size.width * max(0.08, end - start)), height: 8)
                                .offset(x: proxy.size.width * start)
                        }
                    )

                Text(improved ? "Your latest result moved down versus the previous lab." : "Your latest result moved up versus the previous lab.")
                    .font(Theme.Font.body(12, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Palette.surfaceContainerLow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
            )
        }
    }

    private func trendMetricTile(label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Font.body(10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.Palette.inkMuted)

            Text(value)
                .font(Theme.Font.body(16, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)

            Text(caption)
                .font(Theme.Font.body(11, weight: .medium))
                .foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLowest)
        )
    }

    @ViewBuilder
    private func medicationGraphicCard(_ medicationName: String) -> some View {
        if let medication = matchingMedication(for: medicationName) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.Palette.secondaryFixed)
                            .frame(width: 42, height: 42)

                        Image(systemName: medicationSymbol(for: medication.form))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(medication.name)
                            .font(Theme.Font.body(17, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)

                        Text("\(medication.doseText) · \(medication.scheduleText)")
                            .font(Theme.Font.body(13, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }

                    Spacer()
                }

                FlowLayout(spacing: 8) {
                    if medication.withFood {
                        infoChip("With food", icon: "fork.knife", fill: Theme.Palette.secondaryFixed, foreground: Theme.Palette.secondary)
                    }
                    if medication.withWater {
                        infoChip("With water", icon: "drop.fill", fill: Theme.Palette.primaryFixed, foreground: Theme.Palette.primary)
                    }
                    infoChip(medication.form.displayName, icon: "circle.grid.2x2.fill", fill: Theme.Palette.surfaceContainerHigh, foreground: Theme.Palette.inkSoft)
                }

                if let notes = medication.notes, !notes.isEmpty {
                    Text(notes)
                        .font(Theme.Font.body(12, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Palette.surfaceContainerLow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func simulationGraphicCard(_ medicationName: String) -> some View {
        if let medication = matchingMedication(for: medicationName) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(medication.name) Scenario Planner")
                        .font(Theme.Font.body(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)

                    Spacer()

                    Text("WHAT IF")
                        .font(Theme.Font.body(10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Palette.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Palette.secondaryFixed))
                }

                VStack(spacing: 8) {
                    scenarioRow(
                        title: "Usual plan",
                        detail: medication.scheduleText,
                        caption: intakeSummary(for: medication)
                    )
                    scenarioRow(
                        title: "If timing shifts",
                        detail: "Stay close to your normal routine",
                        caption: "Log it clearly instead of guessing later."
                    )
                    scenarioRow(
                        title: "If you're unsure",
                        detail: "Check the label or your clinician's instructions",
                        caption: "Especially before taking an extra dose."
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Palette.primaryFixed)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.primaryFixedDim.opacity(0.9), lineWidth: 1)
            )
        }
    }

    private func scenarioRow(title: String, detail: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(Theme.Font.body(10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.Palette.primary)

            Text(detail)
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)

            Text(caption)
                .font(Theme.Font.body(11, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLowest)
        )
    }

    private func interactionGraphicCard(_ primary: String, _ secondary: String) -> some View {
        let summary = interactionSummary(primary: primary, secondary: secondary)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Interaction Check")
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)

                Spacer()

                Text(summary.risk.uppercased())
                    .font(Theme.Font.body(10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(summary.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(summary.fill))
            }

            HStack(spacing: 10) {
                interactionMedicationPill(name: primary, accent: summary.accent)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(summary.accent)
                interactionMedicationPill(name: secondary, accent: Theme.Palette.ink)
            }

            Text(summary.body)
                .font(Theme.Font.body(13, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)

            Text(summary.nextStep)
                .font(Theme.Font.body(12, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(summary.fill.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(summary.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private func interactionMedicationPill(name: String, accent: Color) -> some View {
        Text(name)
            .font(Theme.Font.body(12, weight: .semibold))
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Palette.surfaceContainerLowest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(0.22), lineWidth: 1)
            )
    }

    private func calloutCard(text: String, tone: ChatCalloutTone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone.foreground)
                .padding(.top, 2)

            paragraphText(text)
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tone.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tone.border, lineWidth: 1)
        )
    }

    private func matchingLab(for metric: String) -> LabResult? {
        let target = normalizedToken(metric)
        return labs.first {
            let current = normalizedToken($0.metric)
            return current == target || current.contains(target) || target.contains(current)
        }
    }

    private func previousLab(for metric: String) -> LabResult? {
        let target = normalizedToken(metric)
        let matches = labs.filter {
            let current = normalizedToken($0.metric)
            return current == target || current.contains(target) || target.contains(current)
        }
        guard matches.count > 1 else { return nil }
        return matches[1]
    }

    private func matchingMedication(for text: String) -> Medication? {
        let target = normalizedToken(text)
        return medications.first {
            let name = normalizedToken($0.name)
            if name == target || name.contains(target) || target.contains(name) {
                return true
            }

            if let brand = $0.brand {
                let brandName = normalizedToken(brand)
                return brandName == target || brandName.contains(target) || target.contains(brandName)
            }

            return false
        }
    }

    private func normalizedToken(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private func referenceLabel(for value: Double?) -> String {
        guard let value else { return "Range" }
        return compactNumber(value)
    }

    private func compactValueText(for lab: LabResult) -> String {
        "\(compactNumber(lab.value)) \(lab.unit)"
    }

    private func compactNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }

    private func rangePosition(for lab: LabResult) -> CGFloat {
        guard let low = lab.referenceLow, let high = lab.referenceHigh, high > low else { return 0.5 }
        let spread = high - low
        let minBound = low - spread * 0.35
        let maxBound = high + spread * 0.35
        guard maxBound > minBound else { return 0.5 }
        return max(0.05, min(0.95, (lab.value - minBound) / (maxBound - minBound)))
    }

    private func trendPosition(for lab: LabResult) -> CGFloat {
        guard let current = matchingLab(for: lab.metric),
              let previous = previousLab(for: lab.metric)
        else { return 0.5 }

        let minValue = min(current.value, previous.value)
        let maxValue = max(current.value, previous.value)
        guard maxValue > minValue else { return 0.5 }
        return max(0.05, min(0.95, (lab.value - minValue) / (maxValue - minValue)))
    }

    private func trendDeltaText(_ delta: Double, unit: String) -> String {
        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(compactNumber(delta)) \(unit)"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func medicationSymbol(for form: DoseForm) -> String {
        switch form {
        case .tablet, .capsule:
            return "pills.fill"
        case .liquid, .drops:
            return "drop.fill"
        case .injection:
            return "syringe.fill"
        case .patch:
            return "cross.case.fill"
        case .inhaler:
            return "cross.vial.fill"
        }
    }

    private func infoChip(_ text: String, icon: String, fill: Color, foreground: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(Theme.Font.body(11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .fixedSize(horizontal: true, vertical: false)
        .background(Capsule().fill(fill))
    }

    private func intakeSummary(for medication: Medication) -> String {
        var parts: [String] = []
        if medication.withFood { parts.append("with food") }
        if medication.withWater { parts.append("with water") }
        return parts.isEmpty ? "No special intake note on file." : "Usually taken " + parts.joined(separator: " and ") + "."
    }

    private func interactionSummary(primary: String, secondary: String) -> (risk: String, body: String, nextStep: String, fill: Color, accent: Color) {
        let pair = [normalizedToken(primary), normalizedToken(secondary)]

        if pair.contains("ibuprofen"), pair.contains("lisinopril") {
            return (
                risk: "Careful",
                body: "This pair can push blood pressure up and add kidney stress if it becomes a repeated pattern.",
                nextStep: "Short-term use is the safer case. Spacing it out, staying hydrated, and checking with a clinician is the best next move.",
                fill: Theme.Palette.secondaryFixed,
                accent: Theme.Palette.secondary
            )
        }

        return (
            risk: "Review",
            body: "This combination is worth double-checking before you make it part of your routine.",
            nextStep: "Use the chart as a prompt to confirm the pair with your pharmacist or clinician.",
            fill: Theme.Palette.surfaceContainerHigh,
            accent: Theme.Palette.ink
        )
    }

    private func statusFill(for status: LabStatus) -> Color {
        switch status {
        case .normal: Theme.Palette.primaryFixed
        case .low: Theme.Palette.secondaryFixed
        case .high: Theme.Palette.errorContainer
        }
    }

    private func statusForeground(for status: LabStatus) -> Color {
        switch status {
        case .normal: Theme.Palette.primary
        case .low: Theme.Palette.secondary
        case .high: Theme.Palette.error
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !responding else { return }
        Haptics.tap()
        messages.append(ChatMessage(sender: .user, text: trimmed))
        draft = ""

        // Placeholder AI bubble we stream into
        let pending = ChatMessage(sender: .ai, text: "", isStreaming: true)
        messages.append(pending)
        let pendingID = pending.id
        responding = true

        Task {
            defer { responding = false }
            do {
                switch ai.status {
                case .available:
                    let stream = ai.stream(userPrompt: trimmed)
                    var finalText = ""
                    for try await partial in stream {
                        finalText = partial
                        if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                            messages[idx].text = displayResponseText(from: partial)
                        }
                    }
                    if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                        let rendered = decorateResponse(finalText, for: trimmed)
                        messages[idx].text = rendered
                        messages[idx].isStreaming = false
                    }
                    Haptics.select()
                case .unavailable:
                    try await Task.sleep(nanoseconds: 800_000_000)
                    if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                        messages[idx].text = decorateResponse(mockedReply(for: trimmed), for: trimmed)
                        messages[idx].isStreaming = false
                    }
                }
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                    messages[idx].text = "I couldn't finish that one — \(error.localizedDescription). Try rephrasing?"
                    messages[idx].isStreaming = false
                }
                Haptics.error()
            }
        }
    }

    private func displayResponseText(from raw: String) -> String {
        normalizeResponseText(stripRenderTokens(from: raw))
    }

    private func decorateResponse(_ raw: String, for prompt: String) -> String {
        var text = normalizeResponseText(raw)

        guard !containsRenderTokens(in: text) else {
            return text
        }

        var tokens: [String] = []

        if let metric = suggestedGraphicMetric(for: prompt, response: text) {
            tokens.append("[[graphic:lab:\(metric)]]")

            if previousLab(for: metric) != nil {
                tokens.append("[[graphic:trend:\(metric)]]")
            }

            if let callout = suggestedCallout(for: metric) {
                tokens.append("[[callout:\(callout.tone.rawValue):\(callout.text)]]")
            }
        }

        if let pair = suggestedInteractionPair(for: prompt, response: text) {
            tokens.append("[[graphic:interaction:\(pair.primary):\(pair.secondary)]]")
        } else if let medication = suggestedMedication(for: prompt, response: text) {
            tokens.append("[[graphic:med:\(medication.name)]]")

            if shouldShowSimulation(for: prompt, response: text) {
                tokens.append("[[graphic:simulation:\(medication.name)]]")
            }
        }

        if !tokens.isEmpty {
            text = conciseResponseText(text)
            text += "\n\n" + tokens.joined(separator: "\n")
        }

        return text
    }

    private func containsRenderTokens(in text: String) -> Bool {
        text.contains("[[graphic:") || text.contains("[[callout:")
    }

    private func stripRenderTokens(from text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("[[graphic:") && !trimmed.hasPrefix("[[callout:")
            }
            .joined(separator: "\n")
    }

    private func normalizeResponseText(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        while normalized.contains("\n\n\n") {
            normalized = normalized.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func suggestedGraphicMetric(for prompt: String, response: String) -> String? {
        let haystack = normalizedToken(prompt + " " + response)

        if let directMatch = labs.first(where: { haystack.contains(normalizedToken($0.metric)) }) {
            return directMatch.metric
        }

        if haystack.contains("lab") || haystack.contains("result") || haystack.contains("range") {
            return labs.first?.metric
        }

        return nil
    }

    private func suggestedMedication(for prompt: String, response: String) -> Medication? {
        let haystack = normalizedToken(prompt + " " + response)

        return medications.first {
            let medName = normalizedToken($0.name)
            if haystack.contains(medName) {
                return true
            }

            if let brand = $0.brand {
                return haystack.contains(normalizedToken(brand))
            }

            return false
        }
    }

    private func suggestedInteractionPair(for prompt: String, response: String) -> (primary: String, secondary: String)? {
        let haystack = normalizedToken(prompt + " " + response)

        if haystack.contains("ibuprofen"), medications.contains(where: { normalizedToken($0.name).contains("lisinopril") }) {
            return ("Ibuprofen", "Lisinopril")
        }

        return nil
    }

    private func shouldShowSimulation(for prompt: String, response: String) -> Bool {
        let haystack = normalizedToken(prompt + " " + response)
        return haystack.contains("whatif") ||
            haystack.contains("simulate") ||
            haystack.contains("scenario") ||
            haystack.contains("late") ||
            haystack.contains("miss") ||
            haystack.contains("skip")
    }

    private func conciseResponseText(_ text: String) -> String {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return text }

        let shortened = Array(paragraphs.prefix(2)).joined(separator: "\n\n")
        guard shortened.count > 320 else { return shortened }

        let prefix = String(shortened.prefix(317))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "..."
        }
        return prefix + "..."
    }

    private func suggestedCallout(for metric: String) -> (tone: ChatCalloutTone, text: String)? {
        guard let lab = matchingLab(for: metric) else { return nil }

        if normalizedToken(lab.metric).contains("a1c") && lab.status == .high {
            return (.positive, "Prediabetes often improves with steady food, movement, and medication habits over time.")
        }

        switch lab.status {
        case .normal:
            return (.positive, "\(lab.metric) is sitting inside the lab's reference range right now.")
        case .low:
            return (.caution, "\(lab.metric) is below range, so it is worth reviewing the trend with your clinician.")
        case .high:
            return (.caution, "\(lab.metric) is above range, so keep an eye on the trend and follow up if it keeps climbing.")
        }
    }

    // Fallback used only when Apple Intelligence isn't available.
    private func mockedReply(for prompt: String) -> String {
        let lower = prompt.lowercased()
        if lower.contains("a1c") {
            return """
            Your latest A1C is 6.2%, up from 5.9% in February.

            That is still in the prediabetes range, but it is a level many people improve with steady food, movement, and medication habits.
            """
        }
        if lower.contains("iron") {
            return """
            Your iron is 52 ug/dL, which is still below the reference range but better than February's 46.

            The trend is moving the right way. Keep taking the supplement in the morning and away from calcium when you can.
            """
        }
        if lower.contains("ibuprofen") || lower.contains("interact") || lower.contains("risky") {
            return """
            Ibuprofen with Lisinopril can put extra stress on your kidneys and may push blood pressure up.

            Short-term use is usually the safer case, but spacing it out, using the lowest dose, and staying hydrated is a better pattern to discuss with your clinician.
            """
        }
        return """
        Here is the quick picture from your chart: 3 active meds, A1C 6.2%, iron 52 ug/dL, and BP 128/82.

        Tell me what you want to focus on and I will break it down clearly.
        """
    }
}

#Preview {
    ChatView()
        .modelContainer(previewContainer())
}
