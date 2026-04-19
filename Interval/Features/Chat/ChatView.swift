import SwiftUI
import SwiftData
import Foundation

// MARK: - Source citation model (Feature 2)

struct ChatSource: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let icon: String
    let accent: Color
    let deepLink: DeepLink

    enum DeepLink: Hashable {
        case labResult(metric: String)
        case medication(name: String)
        case openFDA
        case aiInference
    }

    static func == (lhs: ChatSource, rhs: ChatSource) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Message model

struct ChatMessage: Identifiable, Hashable {
    enum Sender { case user, ai }
    let id = UUID()
    let sender: Sender
    var text: String
    var chips: [String] = []
    var isStreaming: Bool = false
    var isEmergency: Bool = false       // Feature 1
    var sources: [ChatSource] = []      // Feature 2
}

// MARK: - Supporting private types

private enum ChatCalloutTone: String, Hashable {
    case positive
    case caution

    var fill: Color {
        switch self {
        case .positive: Theme.Palette.secondaryFixed
        case .caution:  Theme.Palette.errorContainer
        }
    }

    var border: Color {
        switch self {
        case .positive: Theme.Palette.secondaryContainer.opacity(0.45)
        case .caution:  Theme.Palette.error.opacity(0.22)
        }
    }

    var foreground: Color {
        switch self {
        case .positive: Theme.Palette.secondary
        case .caution:  Theme.Palette.error
        }
    }

    var icon: String {
        switch self {
        case .positive: "lightbulb.fill"
        case .caution:  "exclamationmark.triangle.fill"
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
        case .paragraph(let t):               "paragraph-\(t)"
        case .labGraphic(let m):              "graphic-\(m)"
        case .trendGraphic(let m):            "trend-\(m)"
        case .medicationGraphic(let m):       "med-\(m)"
        case .simulationGraphic(let m):       "simulation-\(m)"
        case .interactionGraphic(let a, let b):"interaction-\(a)-\(b)"
        case .callout(let t, let tone):       "callout-\(tone.rawValue)-\(t)"
        }
    }
}

// MARK: - Emergency keyword list

private let emergencyKeywords: [String] = [
    "chest pain", "can't breathe", "cannot breathe", "can not breathe",
    "stroke", "suicidal", "suicide", "overdose", "severe bleeding",
    "heart attack", "unconscious", "not breathing", "stop breathing",
    "dying", "kill myself", "end my life"
]

// MARK: - Main view

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
    @State private var loadedSummaryHeight: CGFloat = 0
    @FocusState private var inputFocused: Bool

    // Feature 1 & 2 sheet state
    @State private var tappedSource: ChatSource? = nil
    @State private var showMedicalDisclaimer = false

    private var profile: UserProfile? { profiles.first }
    private var firstName: String {
        profile?.name
            .split(separator: " ")
            .first
            .map(String.init) ?? "there"
    }

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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        inputFocused = false
                    }
                )
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
        // Source chip deep-link sheet
        .sheet(item: $tappedSource) { source in
            sourceDetailSheet(source)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.Palette.paper)
        }
        // Medical disclaimer sheet
        .sheet(isPresented: $showMedicalDisclaimer) {
            medicalDisclaimerSheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.Palette.paper)
        }
    }

    // MARK: - Header

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

    // MARK: - Context preamble

    private var contextPreamble: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.select()
                withAnimation(.smooth(duration: 0.34, extraBounce: 0)) {
                    showingLoadedSummary.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loaded about you".uppercased())
                            .font(Theme.Font.eyebrow)
                            .tracking(1)
                            .foregroundStyle(Theme.Palette.inkMuted)

                        Text(showingLoadedSummary ? "Hide summary" : "Tap to review what chat is using")
                            .font(Theme.Font.body(13, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(showingLoadedSummary ? 180 : 0))
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

            loadedSummaryContent
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ChatMeasuredHeightKey.self, value: proxy.size.height)
                    }
                )
                .frame(height: showingLoadedSummary ? max(loadedSummaryHeight, 1) : 0, alignment: .top)
                .clipped()
                .opacity(showingLoadedSummary ? 1 : 0)
                .offset(y: showingLoadedSummary ? 0 : -8)
                .allowsHitTesting(showingLoadedSummary)
        }
        .onPreferenceChange(ChatMeasuredHeightKey.self) { height in
            guard height > 0 else { return }
            loadedSummaryHeight = height
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(fill: Theme.Palette.paperSoft)
    }

    private var loadedSummaryContent: some View {
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
        .padding(.top, 14)
    }

    private func unavailableBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.coralDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Intelligence off")
                    .font(Theme.Font.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(msg)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.Palette.peachTint))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.Palette.coral.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Message bubble

    @ViewBuilder
    private func messageBubble(_ msg: ChatMessage) -> some View {
        switch msg.sender {
        case .ai:
            VStack(alignment: .leading, spacing: 8) {

                // ── Feature 1: Emergency callout ──────────────────────────
                if msg.isEmergency {
                    emergencyCalloutView
                }

                // ── Regular AI content ────────────────────────────────────
                if msg.text.isEmpty && msg.isStreaming {
                    thinkingDots
                } else if !msg.text.isEmpty {
                    assistantMessageCard(
                        msg.text,
                        showsDisclaimerIcon: shouldShowIntroDisclaimer(for: msg)
                    )
                        .animation(.smooth(duration: 0.18), value: msg.text)
                }

                // ── Follow-up suggestion chips ────────────────────────────
                if !msg.chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(msg.chips, id: \.self) { chip in
                                Button {
                                    Haptics.select()
                                    send(chip)
                                } label: {
                                    Text(chip)
                                        .font(Theme.Font.body(12, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.ink)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
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

    // MARK: - Feature 1: Emergency callout

    private var emergencyCalloutView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text("Get help now")
                    .font(Theme.Font.body(18, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("This sounds serious. If you or someone else is in immediate danger, please contact emergency services — don't wait.")
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Link(destination: URL(string: "tel://911")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Call 911")
                            .font(Theme.Font.body(15, weight: .bold))
                    }
                    .foregroundStyle(Theme.Palette.error)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(.white))
                }

                Link(destination: URL(string: "tel://988")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Crisis line · 988")
                            .font(Theme.Font.body(15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(.white.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.Palette.error, Theme.Palette.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: Theme.Palette.error.opacity(0.3), radius: 16, y: 8)
    }

    // MARK: - Feature 2: Source chip row

    private func sourceChipsRow(_ sources: [ChatSource]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(sources) { source in
                Button {
                    Haptics.tap()
                    tappedSource = source
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: source.icon)
                            .font(.system(size: 9, weight: .bold))
                        Text(source.label)
                            .font(Theme.Font.body(11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(source.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(source.accent.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(source.accent.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Feature 1: Disclaimer chip

    private var disclaimerChip: some View {
        Button {
            Haptics.select()
            showMedicalDisclaimer = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.Palette.surfaceContainerLowest)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
                )
                .shadow(color: Theme.Shadow.ambient.opacity(0.18), radius: 6, y: 3)
                .accessibilityLabel("Medical disclaimer")
                .accessibilityHint("Opens the medical disclaimer")
        }
        .buttonStyle(.plain)
    }

    private func shouldShowIntroDisclaimer(for message: ChatMessage) -> Bool {
        guard !message.isStreaming else { return false }
        guard let firstAIMessage = messages.first(where: { $0.sender == .ai }) else { return false }
        return firstAIMessage.id == message.id
    }

    // MARK: - Thinking dots

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

    // MARK: - Input bar

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
                .submitLabel(.send)
                .onSubmit {
                    submitDraft()
                }
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Palette.paperSoft))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                .disabled(responding)

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: responding ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(draft.isEmpty && !responding
                                      ? Theme.Palette.inkMuted.opacity(0.4)
                                      : Theme.Palette.primary)
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

    // MARK: - Conversation logic

    private func seed() {
        messages = [
            ChatMessage(
                sender: .ai,
                text: "Hi \(firstName). I have your latest conditions, meds, and labs loaded.\n\nAsk me anything.",
                chips: ["What does my A1C mean?", "Any risky meds?", "Am I low on iron?"]
            )
        ]
    }

    private func submitDraft() {
        inputFocused = false
        send(draft)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !responding else { return }
        Haptics.tap()

        // Feature 1: detect emergency before sending
        let isEmerg = isEmergencyInput(trimmed)

        messages.append(ChatMessage(sender: .user, text: trimmed))
        draft = ""

        let pending = ChatMessage(sender: .ai, text: "", isStreaming: true, isEmergency: isEmerg)
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
                        messages[idx].sources = computeSources(prompt: trimmed, response: rendered)
                    }
                    Haptics.select()

                case .unavailable:
                    try await Task.sleep(nanoseconds: 800_000_000)
                    if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                        let rendered = decorateResponse(mockedReply(for: trimmed), for: trimmed)
                        messages[idx].text = rendered
                        messages[idx].isStreaming = false
                        messages[idx].sources = computeSources(prompt: trimmed, response: rendered)
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

    // MARK: - Feature 1: Emergency detection

    private func isEmergencyInput(_ text: String) -> Bool {
        let lower = text.lowercased()
        return emergencyKeywords.contains { lower.contains($0) }
    }

    // MARK: - Feature 2: Source computation

    private func computeSources(prompt: String, response: String) -> [ChatSource] {
        var sources: [ChatSource] = []
        let combined = (prompt + " " + response).lowercased()

        // Lab mention → "Your labs · Apr 15"
        if let lab = labs.first(where: { combined.contains($0.metric.lowercased()) }) {
            let dateStr = lab.capturedAt.formatted(.dateTime.month(.abbreviated).day())
            sources.append(ChatSource(
                label: "Your labs · \(dateStr)",
                icon: "chart.bar.fill",
                accent: Theme.Palette.primary,
                deepLink: .labResult(metric: lab.metric)
            ))
        }

        // Medication mention → "Your meds"
        if let med = medications.first(where: { combined.contains($0.name.lowercased()) }) {
            sources.append(ChatSource(
                label: "Your meds",
                icon: "pills.fill",
                accent: Theme.Palette.sageDeep,
                deepLink: .medication(name: med.name)
            ))
        }

        // Drug/interaction language → openFDA
        let fdaKeywords = ["interaction", "side effect", "contraindication", "fda", "prescrib", "drug class"]
        if fdaKeywords.contains(where: { combined.contains($0) }) {
            sources.append(ChatSource(
                label: "openFDA",
                icon: "building.columns.fill",
                accent: Theme.Palette.tertiary,
                deepLink: .openFDA
            ))
        }

        // Fallback if nothing matched
        if sources.isEmpty {
            sources.append(ChatSource(
                label: "AI inference · verify with your doctor",
                icon: "sparkles",
                accent: Theme.Palette.inkMuted,
                deepLink: .aiInference
            ))
        }

        return Array(sources.prefix(3))
    }

    // MARK: - Source detail sheets (Feature 2)

    @ViewBuilder
    private func sourceDetailSheet(_ source: ChatSource) -> some View {
        switch source.deepLink {
        case .labResult(let metric):
            if let lab = labs.first(where: { normalizedToken($0.metric) == normalizedToken(metric) ||
                                             normalizedToken($0.metric).contains(normalizedToken(metric)) }) {
                labDetailSheet(lab)
            } else {
                genericSourceSheet(label: source.label, icon: source.icon, accent: source.accent,
                                   body: "No matching lab result found in your records.")
            }
        case .medication(let name):
            if let med = medications.first(where: { normalizedToken($0.name).contains(normalizedToken(name)) }) {
                medicationDetailSheet(med)
            } else {
                genericSourceSheet(label: source.label, icon: source.icon, accent: source.accent,
                                   body: "No matching medication found in your records.")
            }
        case .openFDA:
            openFDASheet
        case .aiInference:
            medicalDisclaimerSheet
        }
    }

    private func labDetailSheet(_ lab: LabResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(statusFill(for: lab.status)).frame(width: 48, height: 48)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusForeground(for: lab.status))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(lab.metric)
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(lab.capturedAt.formatted(.dateTime.month(.wide).day().year()))
                        .font(Theme.Font.body(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Result")
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                    Spacer()
                    Text(lab.valueText)
                        .font(Theme.Font.body(17, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                Divider()
                HStack {
                    Text("Status")
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                    Spacer()
                    Text(lab.status.displayName.capitalized)
                        .font(Theme.Font.body(15, weight: .bold))
                        .foregroundStyle(statusForeground(for: lab.status))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(statusFill(for: lab.status)))
                }
                if let low = lab.referenceLow, let high = lab.referenceHigh {
                    Divider()
                    HStack {
                        Text("Reference range")
                            .font(Theme.Font.body(14, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkMuted)
                        Spacer()
                        Text("\(compactNumber(low))–\(compactNumber(high)) \(lab.unit)")
                            .font(Theme.Font.body(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
            }
            .padding(Theme.Space.md)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.Palette.hairline.opacity(0.7), lineWidth: 1))

            Spacer()
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.paper)
    }

    private func medicationDetailSheet(_ med: Medication) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.Palette.sage).frame(width: 48, height: 48)
                    Image(systemName: "pills.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.sageDeep)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(med.name)
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    if let brand = med.brand {
                        Text(brand)
                            .font(Theme.Font.body(14, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                }
            }

            VStack(spacing: 12) {
                detailRow("Dose",     value: med.doseText)
                Divider()
                detailRow("Schedule", value: med.scheduleText)
                if let notes = med.notes, !notes.isEmpty {
                    Divider()
                    detailRow("Notes", value: notes)
                }
                if med.withFood || med.withWater {
                    Divider()
                    detailRow("Intake", value: [med.withFood ? "With food" : nil, med.withWater ? "With water" : nil].compactMap { $0 }.joined(separator: " · "))
                }
            }
            .padding(Theme.Space.md)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.Palette.hairline.opacity(0.7), lineWidth: 1))

            Spacer()
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.paper)
    }

    private var openFDASheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.Palette.tertiaryFixed).frame(width: 48, height: 48)
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("openFDA")
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("U.S. Food & Drug Administration")
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }

            Text("Drug interaction and pharmacology information shown in this chat is derived from openFDA — the FDA's open dataset of approved drug labels, adverse events, and recalls.")
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Text("openFDA data is publicly available and updated by the FDA. It reflects information from approved drug labels and should not replace advice from your pharmacist or prescriber.")
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Link("Open openFDA.gov ↗", destination: URL(string: "https://open.fda.gov")!)
                .font(Theme.Font.body(15, weight: .bold))
                .foregroundStyle(Theme.Palette.tertiary)

            Spacer()
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.paper)
    }

    private var medicalDisclaimerSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "cross.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Palette.coralDeep)
                Text("Medical disclaimer")
                    .font(Theme.Font.display(22, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
            }

            Text("Interval provides health information based on data you've entered — your medications, lab results, and medical history. It is not a licensed medical professional and cannot diagnose, treat, or prevent any condition.")
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Text("Always consult a qualified healthcare provider before making any changes to your medication, diet, or treatment plan.")
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.paper)
    }

    private func genericSourceSheet(label: String, icon: String, accent: Color, body: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(accent)
                Text(label).font(Theme.Font.display(20, weight: .bold)).foregroundStyle(Theme.Palette.ink)
            }
            Text(body).font(Theme.Font.body(15, weight: .medium)).foregroundStyle(Theme.Palette.inkSoft)
            Spacer()
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.paper)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkMuted)
            Spacer()
            Text(value)
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Existing graphic card builders (unchanged)

    private func assistantMessageCard(_ text: String, showsDisclaimerIcon: Bool = false) -> some View {
        let blocks = messageBlocks(from: text)
        let trailingParagraph: String? = {
            guard showsDisclaimerIcon, let last = blocks.last else { return nil }
            if case .paragraph(let value) = last { return value }
            return nil
        }()
        let leadingBlocks = trailingParagraph == nil ? blocks : Array(blocks.dropLast())

        return VStack(alignment: .leading, spacing: 14) {
            ForEach(leadingBlocks) { block in
                blockView(block)
            }

            if let trailingParagraph {
                HStack(alignment: .center, spacing: 10) {
                    paragraphText(trailingParagraph)
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    disclaimerChip
                }
            } else if showsDisclaimerIcon {
                HStack {
                    Spacer()
                    disclaimerChip
                }
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
        case .paragraph(let text):              paragraphText(text).foregroundStyle(Theme.Palette.ink)
        case .labGraphic(let metric):           labGraphicCard(metric)
        case .trendGraphic(let metric):         trendGraphicCard(metric)
        case .medicationGraphic(let med):       medicationGraphicCard(med)
        case .simulationGraphic(let med):       simulationGraphicCard(med)
        case .interactionGraphic(let a, let b): interactionGraphicCard(a, b)
        case .callout(let text, let tone):      calloutCard(text: text, tone: tone)
        }
    }

    private func paragraphText(_ text: String) -> Text {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let attributed = try? AttributedString(markdown: trimmed) { return Text(attributed) }
        return Text(trimmed)
    }

    private func messageBlocks(from text: String) -> [ChatRenderBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [ChatRenderBlock] = []
        var paragraphLines: [String] = []

        func flush() {
            let p = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { paragraphLines.removeAll(); return }
            blocks.append(.paragraph(p)); paragraphLines.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty       { flush(); continue }
            if let b = parseGraphicToken(line)  { flush(); blocks.append(b); continue }
            if let b = parseCalloutToken(line)  { flush(); blocks.append(b); continue }
            paragraphLines.append(line)
        }
        flush()
        return blocks.isEmpty && !text.isEmpty ? [.paragraph(text)] : blocks
    }

    private func parseGraphicToken(_ line: String) -> ChatRenderBlock? {
        guard line.hasPrefix("[[graphic:"), line.hasSuffix("]]") else { return nil }
        let payload = String(line.dropFirst(10).dropLast(2))
        let parts   = payload.split(separator: ":").map(String.init)
        guard let kind = parts.first else { return nil }
        switch kind {
        case "lab":         return parts.count >= 2 ? .labGraphic(parts[1])         : nil
        case "trend":       return parts.count >= 2 ? .trendGraphic(parts[1])       : nil
        case "med":         return parts.count >= 2 ? .medicationGraphic(parts[1])  : nil
        case "simulation":  return parts.count >= 2 ? .simulationGraphic(parts[1])  : nil
        case "interaction": return parts.count >= 3 ? .interactionGraphic(parts[1], parts[2]) : nil
        default: return nil
        }
    }

    private func parseCalloutToken(_ line: String) -> ChatRenderBlock? {
        guard line.hasPrefix("[[callout:"), line.hasSuffix("]]") else { return nil }
        let payload = String(line.dropFirst(10).dropLast(2))
        let parts   = payload.split(separator: ":", maxSplits: 1).map(String.init)
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
                        .padding(.horizontal, 8).padding(.vertical, 4)
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
                                .overlay(Circle().strokeBorder(Theme.Palette.surfaceContainerLowest, lineWidth: 2))
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
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Palette.paperSoft))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1))
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
                        .font(Theme.Font.body(15, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text(trendDeltaText(delta, unit: current.unit))
                        .font(Theme.Font.body(10, weight: .bold)).tracking(0.5)
                        .foregroundStyle(improved ? Theme.Palette.primary : Theme.Palette.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(improved ? Theme.Palette.primaryFixed : Theme.Palette.secondaryFixed))
                }
                HStack(spacing: 10) {
                    trendMetricTile(label: "Previous", value: compactValueText(for: previous), caption: shortDate(previous.capturedAt))
                    Image(systemName: improved ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(improved ? Theme.Palette.primary : Theme.Palette.secondary)
                    trendMetricTile(label: "Latest", value: compactValueText(for: current), caption: shortDate(current.capturedAt))
                }
                Capsule().fill(Theme.Palette.surfaceContainer).frame(height: 8)
                    .overlay(GeometryReader { proxy in
                        let start = min(trendPosition(for: previous), trendPosition(for: current))
                        let end   = max(trendPosition(for: previous), trendPosition(for: current))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.Palette.primaryFixedDim, improved ? Theme.Palette.primary : Theme.Palette.secondary], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(16, proxy.size.width * max(0.08, end - start)), height: 8)
                            .offset(x: proxy.size.width * start)
                    })
                Text(improved ? "Your latest result moved down versus the previous lab." : "Your latest result moved up versus the previous lab.")
                    .font(Theme.Font.body(12, weight: .medium)).foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Palette.surfaceContainerLow))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1))
        }
    }

    private func trendMetricTile(label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(Theme.Font.body(10, weight: .semibold)).tracking(0.7).foregroundStyle(Theme.Palette.inkMuted)
            Text(value).font(Theme.Font.body(16, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
            Text(caption).font(Theme.Font.body(11, weight: .medium)).foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.Palette.surfaceContainerLowest))
    }

    @ViewBuilder
    private func medicationGraphicCard(_ medicationName: String) -> some View {
        if let medication = matchingMedication(for: medicationName) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.Palette.secondaryFixed).frame(width: 42, height: 42)
                        Image(systemName: medicationSymbol(for: medication.form))
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Palette.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(medication.name).font(Theme.Font.body(17, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
                        Text("\(medication.doseText) · \(medication.scheduleText)").font(Theme.Font.body(13, weight: .medium)).foregroundStyle(Theme.Palette.inkSoft)
                    }
                    Spacer()
                }
                FlowLayout(spacing: 8) {
                    if medication.withFood  { infoChip("With food",  icon: "fork.knife",         fill: Theme.Palette.secondaryFixed, foreground: Theme.Palette.secondary) }
                    if medication.withWater { infoChip("With water", icon: "drop.fill",           fill: Theme.Palette.primaryFixed,   foreground: Theme.Palette.primary) }
                    infoChip(medication.form.displayName, icon: "circle.grid.2x2.fill", fill: Theme.Palette.surfaceContainerHigh, foreground: Theme.Palette.inkSoft)
                }
                if let notes = medication.notes, !notes.isEmpty {
                    Text(notes).font(Theme.Font.body(12, weight: .medium)).foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Palette.surfaceContainerLow))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func simulationGraphicCard(_ medicationName: String) -> some View {
        if let medication = matchingMedication(for: medicationName) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(medication.name) Scenario Planner").font(Theme.Font.body(15, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text("WHAT IF").font(Theme.Font.body(10, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Theme.Palette.secondary).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Palette.secondaryFixed))
                }
                VStack(spacing: 8) {
                    scenarioRow(title: "Usual plan",        detail: medication.scheduleText,              caption: intakeSummary(for: medication))
                    scenarioRow(title: "If timing shifts",  detail: "Stay close to your normal routine",  caption: "Log it clearly instead of guessing later.")
                    scenarioRow(title: "If you're unsure",  detail: "Check the label or your clinician's instructions", caption: "Especially before taking an extra dose.")
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Palette.primaryFixed))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.Palette.primaryFixedDim.opacity(0.9), lineWidth: 1))
        }
    }

    private func scenarioRow(title: String, detail: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(Theme.Font.body(10, weight: .semibold)).tracking(0.7).foregroundStyle(Theme.Palette.primary)
            Text(detail).font(Theme.Font.body(14, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
            Text(caption).font(Theme.Font.body(11, weight: .medium)).foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.surfaceContainerLowest))
    }

    private func interactionGraphicCard(_ primary: String, _ secondary: String) -> some View {
        let summary = interactionSummary(primary: primary, secondary: secondary)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Interaction Check").font(Theme.Font.body(15, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(summary.risk.uppercased()).font(Theme.Font.body(10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(summary.accent).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(summary.fill))
            }
            HStack(spacing: 10) {
                interactionMedicationPill(name: primary, accent: summary.accent)
                Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundStyle(summary.accent)
                interactionMedicationPill(name: secondary, accent: Theme.Palette.ink)
            }
            Text(summary.body).font(Theme.Font.body(13, weight: .medium)).foregroundStyle(Theme.Palette.ink)
            Text(summary.nextStep).font(Theme.Font.body(12, weight: .medium)).foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(summary.fill.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(summary.accent.opacity(0.2), lineWidth: 1))
    }

    private func interactionMedicationPill(name: String, accent: Color) -> some View {
        Text(name).font(Theme.Font.body(12, weight: .semibold)).foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.surfaceContainerLowest))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(accent.opacity(0.22), lineWidth: 1))
    }

    private func calloutCard(text: String, tone: ChatCalloutTone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tone.foreground).padding(.top, 2)
            paragraphText(text).foregroundStyle(Theme.Palette.ink)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tone.fill))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tone.border, lineWidth: 1))
    }

    // MARK: - Context summary helpers

    private func contextTag(_ text: String) -> some View {
        Text(text).font(Theme.Font.body(12, weight: .medium)).foregroundStyle(Theme.Palette.ink).lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 8).fixedSize(horizontal: true, vertical: false)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.Palette.surfaceContainerLowest))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1))
            .shadow(color: Theme.Shadow.ambient.opacity(0.25), radius: 6, y: 3)
    }

    private var contextSummaryText: String { "Chat is grounding replies in your profile, medication list, allergies, and recent lab results so answers stay specific to your record." }
    private var conditionsSummary:  String { summarizedList(profile?.conditions, empty: "No conditions loaded") }
    private var allergiesSummary:   String { summarizedList(profile?.allergies,  empty: "No allergies loaded") }
    private var medicationsSummary: String { summarizedList(medications.map(\.name), empty: "No active medications loaded") }
    private var latestLabSummary:   String { labs.first.map { "\($0.metric) \($0.valueText) · \($0.status.displayName)" } ?? "No recent labs loaded" }

    private func summarizedList(_ items: [String]?, empty: String) -> String {
        guard let items, !items.isEmpty else { return empty }
        return items.joined(separator: ", ")
    }

    private func contextSummaryRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(Theme.Font.body(10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.Palette.inkMuted)
            Text(value).font(Theme.Font.body(14, weight: .medium)).foregroundStyle(Theme.Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Data lookup helpers

    private func matchingLab(for metric: String) -> LabResult? {
        let t = normalizedToken(metric)
        return labs.first { let c = normalizedToken($0.metric); return c == t || c.contains(t) || t.contains(c) }
    }

    private func previousLab(for metric: String) -> LabResult? {
        let t = normalizedToken(metric)
        let matches = labs.filter { let c = normalizedToken($0.metric); return c == t || c.contains(t) || t.contains(c) }
        return matches.count > 1 ? matches[1] : nil
    }

    private func matchingMedication(for text: String) -> Medication? {
        let t = normalizedToken(text)
        return medications.first {
            let name = normalizedToken($0.name)
            if name == t || name.contains(t) || t.contains(name) { return true }
            if let brand = $0.brand { let b = normalizedToken(brand); return b == t || b.contains(t) || t.contains(b) }
            return false
        }
    }

    private func normalizedToken(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Number / formatting helpers

    private func referenceLabel(for value: Double?) -> String { value.map { compactNumber($0) } ?? "Range" }
    private func compactValueText(for lab: LabResult) -> String { "\(compactNumber(lab.value)) \(lab.unit)" }
    private func compactNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }
    private func shortDate(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day()) }
    private func trendDeltaText(_ delta: Double, unit: String) -> String { "\(delta > 0 ? "+" : "")\(compactNumber(delta)) \(unit)" }

    private func rangePosition(for lab: LabResult) -> CGFloat {
        guard let low = lab.referenceLow, let high = lab.referenceHigh, high > low else { return 0.5 }
        let spread = high - low; let min = low - spread * 0.35; let max = high + spread * 0.35
        guard max > min else { return 0.5 }
        return Swift.max(0.05, Swift.min(0.95, (lab.value - min) / (max - min)))
    }

    private func trendPosition(for lab: LabResult) -> CGFloat {
        guard let current = matchingLab(for: lab.metric), let previous = previousLab(for: lab.metric) else { return 0.5 }
        let minV = Swift.min(current.value, previous.value); let maxV = Swift.max(current.value, previous.value)
        guard maxV > minV else { return 0.5 }
        return Swift.max(0.05, Swift.min(0.95, (lab.value - minV) / (maxV - minV)))
    }

    private func statusFill(for status: LabStatus) -> Color {
        switch status { case .normal: Theme.Palette.primaryFixed; case .low: Theme.Palette.secondaryFixed; case .high: Theme.Palette.errorContainer }
    }
    private func statusForeground(for status: LabStatus) -> Color {
        switch status { case .normal: Theme.Palette.primary; case .low: Theme.Palette.secondary; case .high: Theme.Palette.error }
    }

    private func medicationSymbol(for form: DoseForm) -> String {
        switch form {
        case .tablet, .capsule: "pills.fill"; case .liquid, .drops: "drop.fill"
        case .injection: "syringe.fill"; case .patch: "cross.case.fill"; case .inhaler: "cross.vial.fill"
        }
    }

    private func infoChip(_ text: String, icon: String, fill: Color, foreground: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(Theme.Font.body(11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(foreground).padding(.horizontal, 10).padding(.vertical, 7)
        .fixedSize(horizontal: true, vertical: false).background(Capsule().fill(fill))
    }

    private func intakeSummary(for medication: Medication) -> String {
        var parts: [String] = []
        if medication.withFood  { parts.append("with food") }
        if medication.withWater { parts.append("with water") }
        return parts.isEmpty ? "No special intake note on file." : "Usually taken " + parts.joined(separator: " and ") + "."
    }

    private func interactionSummary(primary: String, secondary: String) -> (risk: String, body: String, nextStep: String, fill: Color, accent: Color) {
        if let issue = MedicationSafetyEngine.interactionIssue(primary: primary, secondary: secondary, profile: profile) {
            switch issue.severity {
            case .low:
                return (
                    issue.severity.label,
                    issue.summary,
                    issue.recommendation,
                    Theme.Palette.primaryFixed,
                    Theme.Palette.primary
                )
            case .moderate:
                return (
                    issue.severity.label,
                    issue.summary,
                    issue.recommendation,
                    Theme.Palette.secondaryFixed,
                    Theme.Palette.secondary
                )
            case .high:
                return (
                    issue.severity.label,
                    issue.summary,
                    issue.recommendation,
                    Theme.Palette.errorContainer,
                    Theme.Palette.error
                )
            }
        }

        return (
            "Clear",
            "I did not find a direct medication-pair or allergy warning for this pair in the current quick-check rules.",
            "If either medication is new or temporary, it is still smart to confirm it with a pharmacist.",
            Theme.Palette.primaryFixed,
            Theme.Palette.primary
        )
    }

    // MARK: - Response decoration (unchanged)

    private func displayResponseText(from raw: String) -> String { normalizeResponseText(stripRenderTokens(from: raw)) }

    private func decorateResponse(_ raw: String, for prompt: String) -> String {
        var text = normalizeResponseText(raw)
        guard !containsRenderTokens(in: text) else { return text }
        var tokens: [String] = []
        if let metric = suggestedGraphicMetric(for: prompt, response: text) {
            tokens.append("[[graphic:lab:\(metric)]]")
            if previousLab(for: metric) != nil { tokens.append("[[graphic:trend:\(metric)]]") }
            if let callout = suggestedCallout(for: metric) { tokens.append("[[callout:\(callout.tone.rawValue):\(callout.text)]]") }
        }
        if let pair = suggestedInteractionPair(for: prompt, response: text) {
            tokens.append("[[graphic:interaction:\(pair.primary):\(pair.secondary)]]")
        } else if let medication = suggestedMedication(for: prompt, response: text) {
            tokens.append("[[graphic:med:\(medication.name)]]")
            if shouldShowSimulation(for: prompt, response: text) { tokens.append("[[graphic:simulation:\(medication.name)]]") }
        }
        if !tokens.isEmpty { text = conciseResponseText(text); text += "\n\n" + tokens.joined(separator: "\n") }
        return text
    }

    private func containsRenderTokens(in text: String) -> Bool { text.contains("[[graphic:") || text.contains("[[callout:") }
    private func stripRenderTokens(from text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[[") }
            .joined(separator: "\n")
    }
    private func normalizeResponseText(_ text: String) -> String {
        var n = text.replacingOccurrences(of: "\r\n", with: "\n")
        while n.contains("\n\n\n") { n = n.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return n.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func suggestedGraphicMetric(for prompt: String, response: String) -> String? {
        let h = normalizedToken(prompt + " " + response)
        if let m = labs.first(where: { h.contains(normalizedToken($0.metric)) }) { return m.metric }
        if h.contains("lab") || h.contains("result") || h.contains("range") { return labs.first?.metric }
        return nil
    }
    private func suggestedMedication(for prompt: String, response: String) -> Medication? {
        let h = normalizedToken(prompt + " " + response)
        return medications.first { let n = normalizedToken($0.name); if h.contains(n) { return true }; if let b = $0.brand { return h.contains(normalizedToken(b)) }; return false }
    }
    private func suggestedInteractionPair(for prompt: String, response: String) -> (primary: String, secondary: String)? {
        let mentioned = Array(NSOrderedSet(array: MedicationSafetyEngine.medicationNamesMentioned(
            in: prompt + " " + response,
            currentMedications: medications
        ))) as? [String] ?? []

        var best: (primary: String, secondary: String, severity: MedicationInteractionSeverity)?

        for index in mentioned.indices {
            for nextIndex in mentioned.indices where nextIndex > index {
                let primary = mentioned[index]
                let secondary = mentioned[nextIndex]
                guard let issue = MedicationSafetyEngine.interactionIssue(
                    primary: primary,
                    secondary: secondary,
                    profile: profile
                ) else { continue }

                if best == nil || issue.severity > best!.severity {
                    best = (primary, secondary, issue.severity)
                }
            }
        }

        return best.map { ($0.primary, $0.secondary) }
    }
    private func shouldShowSimulation(for prompt: String, response: String) -> Bool {
        let h = normalizedToken(prompt + " " + response)
        return h.contains("whatif") || h.contains("simulate") || h.contains("scenario") || h.contains("late") || h.contains("miss") || h.contains("skip")
    }
    private func conciseResponseText(_ text: String) -> String {
        let ps = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !ps.isEmpty else { return text }
        let s = Array(ps.prefix(2)).joined(separator: "\n\n")
        guard s.count > 320 else { return s }
        let p = String(s.prefix(317))
        return (p.lastIndex(of: " ").map { String(p[..<$0]) } ?? p) + "..."
    }
    private func suggestedCallout(for metric: String) -> (tone: ChatCalloutTone, text: String)? {
        guard let lab = matchingLab(for: metric) else { return nil }
        if normalizedToken(lab.metric).contains("a1c") && lab.status == .high {
            return (.positive, "Prediabetes often improves with steady food, movement, and medication habits over time.")
        }
        switch lab.status {
        case .normal: return (.positive, "\(lab.metric) is sitting inside the lab's reference range right now.")
        case .low:    return (.caution,  "\(lab.metric) is below range, so it is worth reviewing the trend with your clinician.")
        case .high:   return (.caution,  "\(lab.metric) is above range, so keep an eye on the trend and follow up if it keeps climbing.")
        }
    }
    private func mockedReply(for prompt: String) -> String {
        let lower = prompt.lowercased()
        if lower.contains("a1c") { return "Your latest A1C is 6.2%, up from 5.9% in February.\n\nThat is still in the prediabetes range, but it is a level many people improve with steady food, movement, and medication habits." }
        if lower.contains("iron") { return "Your iron is 52 ug/dL, which is still below the reference range but better than February's 46.\n\nThe trend is moving the right way. Keep taking the supplement in the morning and away from calcium when you can." }
        if lower.contains("ibuprofen") || lower.contains("interact") || lower.contains("risky") {
            return "Ibuprofen with Lisinopril can put extra stress on your kidneys and may push blood pressure up.\n\nShort-term use is usually the safer case, but spacing it out, using the lowest dose, and staying hydrated is a better pattern to discuss with your clinician."
        }
        return "Here is the quick picture: 3 active meds, A1C 6.2%, iron 52 ug/dL, and BP 128/82.\n\nTell me what you want to focus on and I will break it down clearly."
    }
}

private struct ChatMeasuredHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    ChatView()
        .modelContainer(previewContainer())
}
