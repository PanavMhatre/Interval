import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appleHealth: AppleHealthStore
    @Query private var profiles: [UserProfile]

    @State private var step: Int = 0
    @State private var healthKit: PermissionState = .on
    @State private var camera: PermissionState = .on
    @State private var notifications: PermissionState = .ask
    @State private var cloudAI: PermissionState = .skip
    @State private var userName: String = ""
    @State private var isFinishing = false

    enum PermissionState: String { case on, ask, skip }

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            content
                .animation(.smooth(duration: 0.35), value: step)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: permissionsStep
        default: conversationalStep
        }
    }

    // MARK: Step 0 — Warm welcome

    private var welcomeStep: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()

            ZStack {
                Circle().fill(Theme.Palette.peachTint).frame(width: 64, height: 64)
                Text("hi")
                    .font(Theme.Font.display(20, weight: .semibold))
                    .foregroundStyle(Theme.Palette.coralDeep)
            }

            VStack(spacing: 6) {
                Text("Hey there.")
                    .font(Theme.Font.display(34, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Let's get to know you —")
                    .font(Theme.Font.body(17))
                    .foregroundStyle(Theme.Palette.inkSoft)
                Text("just a little.")
                    .font(Theme.Font.body(17))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What we'll ask for").eyebrowStyle()
                askRow(icon: "heart.fill", text: "Health data (steps, sleep)", tint: Theme.Palette.coral)
                askRow(icon: "doc.text.fill", text: "Scan medical documents", tint: Theme.Palette.coral)
                askRow(icon: "alarm.fill", text: "Remind you of meds", tint: Theme.Palette.coral)
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(fill: Theme.Palette.paperSoft)

            VStack(alignment: .leading, spacing: 6) {
                Text("Privacy").eyebrowStyle().foregroundStyle(Theme.Palette.coralDeep)
                Text("Everything stays on your phone by default.")
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Palette.peachTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.Palette.coral.opacity(0.3), lineWidth: 1)
            )

            Spacer()

            PrimaryButton(title: "Let's begin") {
                step = 1
            }

            Text("takes about 2 minutes")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.xl)
    }

    private func askRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.Palette.card).frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            }
            Text(text).font(Theme.Font.body(15, weight: .medium)).foregroundStyle(Theme.Palette.ink)
            Spacer()
        }
    }

    // MARK: Step 1 — Plain permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack {
                Text("Step 2 of 4")
                    .font(Theme.Font.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkMuted)
                Spacer()
                stepDots(current: 1, total: 4)
            }
            DashedHairline()

            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions")
                    .font(Theme.Font.display(30, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("All optional · you're in charge".uppercased())
                    .font(Theme.Font.body(11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }

            VStack(spacing: 10) {
                permissionRow(
                    title: "HealthKit",
                    detail: "Steps, sleep, hydration, heart rate",
                    icon: "heart.fill",
                    binding: $healthKit
                )
                permissionRow(
                    title: "Camera",
                    detail: "For scanning lab results",
                    icon: "camera.fill",
                    binding: $camera
                )
                permissionRow(
                    title: "Notifications",
                    detail: "Medication reminders",
                    icon: "bell.fill",
                    binding: $notifications
                )
                permissionRow(
                    title: "Cloud AI",
                    detail: "Off by default (private)",
                    icon: "cloud.fill",
                    binding: $cloudAI
                )
            }

            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkMuted)
                Text("You can change any of these later in Settings.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            .padding(Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(
                        Theme.Palette.hairline,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )

            Spacer()

            HStack(spacing: 10) {
                GhostButton(title: "Back", dashed: true) { step = 0 }
                PrimaryButton(title: "Continue") { step = 2 }
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.xl)
    }

    private func stepDots(current: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == current ? Theme.Palette.ink : Theme.Palette.inkMuted.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func permissionRow(title: String, detail: String, icon: String, binding: Binding<PermissionState>) -> some View {
        LabeledRow(title: title, subtitle: detail, icon: icon) {
            permissionChip(binding: binding)
        }
    }

    private func permissionChip(binding: Binding<PermissionState>) -> some View {
        Button {
            Haptics.select()
            switch binding.wrappedValue {
            case .on:   binding.wrappedValue = .ask
            case .ask:  binding.wrappedValue = .skip
            case .skip: binding.wrappedValue = .on
            }
        } label: {
            switch binding.wrappedValue {
            case .on:   StatusChip(text: "✓ On",  kind: .done)
            case .ask:  StatusChip(text: "Ask",   kind: .ask)
            case .skip: StatusChip(text: "Skip",  kind: .skip)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2 — Conversational setup

    private var conversationalStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Text("Meet Interval")
                    .font(Theme.Font.display(22, weight: .semibold))
                Spacer()
                PillTag(text: "on-device", fill: Theme.Palette.peachTint, border: Theme.Palette.coral.opacity(0.3), foreground: Theme.Palette.coralDeep, icon: "lock.fill")
            }
            DashedHairline()

            // Intro bubble
            chatBubble(isUser: false) {
                HStack(alignment: .top, spacing: 10) {
                    AvatarCircle(initials: "i", size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interval").font(Theme.Font.cardTitle).foregroundStyle(Theme.Palette.ink)
                        Text("your health, together".uppercased())
                            .font(Theme.Font.body(10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                }
            }

            chatBubble(isUser: false) {
                Text("Hi! I'm here to help you keep track of your health in one place. Mind if I ask 3 quick things?")
                    .font(Theme.Font.bodyText)
                    .foregroundStyle(Theme.Palette.ink)
            }

            chatBubble(isUser: false) {
                Text("First — what should I call you?")
                    .font(Theme.Font.bodyText)
                    .foregroundStyle(Theme.Palette.ink)
            }

            if userName.isEmpty {
                HStack {
                    Spacer()
                    TextField("Your name", text: $userName)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.bodyText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.Palette.ink))
                        .foregroundStyle(.white)
                        .tint(.white)
                        .frame(maxWidth: 200)
                        .submitLabel(.done)
                        .onSubmit {
                            Haptics.tap()
                            Task {
                                await finishOnboarding(requestHealthAccess: healthKit == .on)
                            }
                        }
                }
            } else {
                HStack {
                    Spacer()
                    Text(userName)
                        .font(Theme.Font.bodyText)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.Palette.ink))
                }

                chatBubble(isUser: false) {
                    Text("Nice to meet you, \(userName). Want me to connect Apple Health for live steps, sleep, hydration, and heart rate?")
                        .font(Theme.Font.bodyText)
                        .foregroundStyle(Theme.Palette.ink)
                }

                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        choiceBubble("Sure") {
                            Task {
                                await finishOnboarding(requestHealthAccess: healthKit != .skip)
                            }
                        }
                        choiceBubble("Not yet") {
                            Task {
                                await finishOnboarding(requestHealthAccess: false)
                            }
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.Palette.inkMuted)
                Text("I won't send anything off your device unless you say so.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            .padding(Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.xl)
    }

    private func chatBubble<Content: View>(isUser: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            if isUser { Spacer() }
            content()
                .padding(Theme.Space.sm)
                .frame(maxWidth: 280, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
            if !isUser { Spacer() }
        }
    }

    private func choiceBubble(_ text: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(text)
                .font(Theme.Font.body(13, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(
                    Capsule().strokeBorder(Theme.Palette.ink.opacity(0.7), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Finish

    private func finishOnboarding(requestHealthAccess: Bool) async {
        guard !isFinishing else { return }
        isFinishing = true

        if requestHealthAccess {
            await appleHealth.requestAccess()
        }

        Haptics.success()
        if let profile = profiles.first {
            if !userName.isEmpty {
                profile.name = userName
                profile.initials = String(userName.prefix(1)).uppercased()
            }
            profile.hasCompletedOnboarding = true
        } else {
            let p = UserProfile(
                name: userName.isEmpty ? "Friend" : userName,
                initials: userName.isEmpty ? "F" : String(userName.prefix(1)).uppercased(),
                hasCompletedOnboarding: true
            )
            context.insert(p)
        }
        try? context.save()
        isFinishing = false
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: [UserProfile.self], inMemory: true)
        .environmentObject(AppleHealthStore.previewDisconnected)
}
