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
    @State private var firstNameInput = ""
    @State private var lastNameInput = ""
    @State private var ageInput = ""
    @State private var submittedFirstName: String?
    @State private var submittedLastName: String?
    @State private var submittedAge: Int?
    @State private var isFinishing = false
    @FocusState private var focusedField: IntakeField?

    enum PermissionState: String { case on, ask, skip }
    enum IntakeField { case firstName, lastName, age }

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
            chatBubble(isUser: false) {
                Text("I just need 3 quick details to set up your profile.")
                    .font(Theme.Font.bodyText)
                    .foregroundStyle(Theme.Palette.ink)
            }

            chatBubble(isUser: false) {
                Text("First, what's your first name?")
                    .font(Theme.Font.bodyText)
                    .foregroundStyle(Theme.Palette.ink)
            }

            if let submittedFirstName {
                userReplyBubble(submittedFirstName)
                chatBubble(isUser: false) {
                    Text("Thanks, \(submittedFirstName). What's your last name?")
                        .font(Theme.Font.bodyText)
                        .foregroundStyle(Theme.Palette.ink)
                }
            } else {
                intakeField(
                    placeholder: "First name",
                    text: $firstNameInput,
                    field: .firstName,
                    submitLabel: .next
                )
            }

            if let submittedLastName {
                userReplyBubble(submittedLastName)
                chatBubble(isUser: false) {
                    Text("Got it. How old are you?")
                        .font(Theme.Font.bodyText)
                        .foregroundStyle(Theme.Palette.ink)
                }
            } else if submittedFirstName != nil {
                intakeField(
                    placeholder: "Last name",
                    text: $lastNameInput,
                    field: .lastName,
                    submitLabel: .next
                )
            }

            if let submittedAge {
                userReplyBubble("\(submittedAge)")

                chatBubble(isUser: false) {
                    Text("Perfect, \(resolvedFullName). Want me to connect Apple Health for live steps, sleep, hydration, and heart rate?")
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
            } else if submittedFirstName != nil && submittedLastName != nil {
                intakeField(
                    placeholder: "Age",
                    text: $ageInput,
                    field: .age,
                    submitLabel: .done,
                    isNumeric: true
                )
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
        .onAppear {
            focusedField = currentInputField
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    submitCurrentField()
                }
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.primary)
            }
        }
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

    private func intakeField(
        placeholder: String,
        text: Binding<String>,
        field: IntakeField,
        submitLabel: SubmitLabel,
        isNumeric: Bool = false
    ) -> some View {
        HStack {
            Spacer()
            TextField(
                "",
                text: text,
                prompt: Text(placeholder)
                    .foregroundStyle(Theme.Palette.inkMuted)
            )
            .textFieldStyle(.plain)
            .font(Theme.Font.bodyText)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.Palette.card))
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
            .foregroundStyle(Theme.Palette.ink)
            .tint(Theme.Palette.ink)
            .frame(maxWidth: 220)
            .textInputAutocapitalization(isNumeric ? .never : .words)
            .keyboardType(isNumeric ? .numberPad : .default)
            .focused($focusedField, equals: field)
            .submitLabel(submitLabel)
            .onSubmit {
                submitCurrentField()
            }
        }
    }

    private func userReplyBubble(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .font(Theme.Font.bodyText)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.Palette.ink))
        }
    }

    // MARK: Finish

    private var currentInputField: IntakeField? {
        if submittedFirstName == nil { return .firstName }
        if submittedLastName == nil { return .lastName }
        if submittedAge == nil { return .age }
        return nil
    }

    private var resolvedFullName: String {
        [submittedFirstName, submittedLastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var resolvedInitials: String {
        let first = submittedFirstName?.first.map(String.init) ?? ""
        let last = submittedLastName?.first.map(String.init) ?? ""
        let combined = (first + last).uppercased()
        return combined.isEmpty ? "F" : combined
    }

    private func submitCurrentField() {
        switch currentInputField {
        case .firstName:
            submitFirstName()
        case .lastName:
            submitLastName()
        case .age:
            submitAge()
        case nil:
            focusedField = nil
        }
    }

    private func submitFirstName() {
        let trimmed = firstNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        firstNameInput = trimmed
        submittedFirstName = trimmed
        Haptics.tap()
        focusedField = .lastName
    }

    private func submitLastName() {
        let trimmed = lastNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastNameInput = trimmed
        submittedLastName = trimmed
        Haptics.tap()
        focusedField = .age
    }

    private func submitAge() {
        let trimmed = ageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let age = Int(trimmed), (1...120).contains(age) else { return }
        ageInput = String(age)
        submittedAge = age
        Haptics.tap()
        focusedField = nil
    }

    private func finishOnboarding(requestHealthAccess: Bool) async {
        guard !isFinishing else { return }
        isFinishing = true

        if requestHealthAccess {
            await appleHealth.requestAccess()
        }

        Haptics.success()
        if let profile = profiles.first {
            profile.name = resolvedFullName.isEmpty ? "Friend" : resolvedFullName
            profile.initials = resolvedInitials
            if let submittedAge {
                profile.age = submittedAge
            }
            profile.hasCompletedOnboarding = true
        } else {
            let p = UserProfile(
                name: resolvedFullName.isEmpty ? "Friend" : resolvedFullName,
                initials: resolvedInitials,
                age: submittedAge ?? 34,
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
