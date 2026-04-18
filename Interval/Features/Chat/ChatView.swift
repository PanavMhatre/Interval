import SwiftUI
import SwiftData
import FoundationModels

struct ChatMessage: Identifiable, Hashable {
    enum Sender { case user, ai }
    let id = UUID()
    let sender: Sender
    var text: String
    var chips: [String] = []
    var isStreaming: Bool = false
}

struct ChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var profiles: [UserProfile]

    @State private var ai = IntervalAI()
    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var responding = false
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
            consumePendingPrompt()
        }
        .onChange(of: router.pendingChatPrompt) { _, _ in
            consumePendingPrompt()
        }
    }

    private func consumePendingPrompt() {
        guard let prompt = router.pendingChatPrompt,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        router.pendingChatPrompt = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            send(prompt)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat with Interval")
                    .font(Theme.Font.display(22, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                    Text(statusLine)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }
            Spacer()
            AvatarCircle(initials: "i", size: 36)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.Palette.paper)
    }

    private var statusLine: String {
        switch ai.status {
        case .available: "Apple Intelligence · on-device · your context loaded"
        case .unavailable: "On-device model unavailable"
        }
    }

    private var contextPreamble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Loaded about you".uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.inkMuted)
            HStack(spacing: 6) {
                PillTag(text: "\(profile?.conditions.count ?? 0) conditions")
                PillTag(text: "\(profile?.allergies.count ?? 0) allergies")
                PillTag(text: "active meds")
                PillTag(text: "recent labs")
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
            HStack(alignment: .top, spacing: 8) {
                AvatarCircle(initials: "i", size: 28)
                VStack(alignment: .leading, spacing: 8) {
                    if msg.text.isEmpty && msg.isStreaming {
                        thinkingDots
                    } else {
                        Text(msg.text)
                            .font(Theme.Font.bodyText)
                            .foregroundStyle(Theme.Palette.ink)
                            .padding(Theme.Space.sm)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.card))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                            .animation(.smooth(duration: 0.18), value: msg.text)
                    }
                    if !msg.chips.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(msg.chips, id: \.self) { chip in
                                Button {
                                    Haptics.select()
                                    send(chip)
                                } label: {
                                    Text(chip)
                                        .font(Theme.Font.body(12, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.ink)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .overlay(Capsule().strokeBorder(Theme.Palette.ink.opacity(0.7), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Spacer(minLength: 40)
            }
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(msg.text)
                    .font(Theme.Font.bodyText)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.Palette.coral)
                    )
                    .warmGlow(intensity: 0.18)
            }
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
        .padding(Theme.Space.sm)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Palette.hairline, lineWidth: 1))
    }

    // MARK: Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.Palette.hairline)
            HStack(spacing: 10) {
                TextField("Ask about your health…", text: $draft, axis: .vertical)
                    .font(Theme.Font.bodyText)
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
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(draft.isEmpty && !responding ? Theme.Palette.inkMuted.opacity(0.4) : Theme.Palette.coral))
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
                text: "Hi \(firstName). I've got your full context loaded — conditions, meds, recent labs. Ask me anything.",
                chips: ["What does my A1C mean?", "Any risky meds?", "Am I low on iron?"]
            )
        ]
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
                    for try await partial in stream {
                        if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                            messages[idx].text = partial
                        }
                    }
                    if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                        messages[idx].isStreaming = false
                    }
                    Haptics.select()
                case .unavailable:
                    try await Task.sleep(nanoseconds: 800_000_000)
                    if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                        messages[idx].text = mockedReply(for: trimmed)
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

    // Fallback used only when Apple Intelligence isn't available.
    private func mockedReply(for prompt: String) -> String {
        let lower = prompt.lowercased()
        if lower.contains("a1c") {
            return "Your latest A1C is 6.2% — up from 5.9% in February. Still in prediabetes range. With Metformin just started, expect this to trend down over the next 3 months."
        }
        if lower.contains("iron") {
            return "Iron is 52 µg/dL — below the 60 reference but up 18% from February (46). The supplement's working. Keep morning timing, away from calcium."
        }
        if lower.contains("ibuprofen") || lower.contains("interact") || lower.contains("risky") {
            return "Daily ibuprofen with your Lisinopril can stress your kidneys and raise BP. Short-term is fine. Safer: take ibuprofen 2+ hours after lisinopril and drink water."
        }
        return "Here's what I see: 3 active meds, A1C 6.2%, iron 52 µg/dL, BP 128/82. What would you like me to focus on?"
    }
}

#Preview {
    ChatView()
        .modelContainer(previewContainer())
        .environment(AppRouter())
}
