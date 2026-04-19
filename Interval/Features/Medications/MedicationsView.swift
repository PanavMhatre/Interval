import SwiftUI
import SwiftData

// MARK: - Dose Status

private enum DoseStatus {
    case taken
    case dueNow
    case upcoming
}

// MARK: - Meds Tab

private enum MedsTab: String, CaseIterable {
    case schedule     = "Schedule"
    case allMeds      = "All meds"
    case interactions = "Interactions"
    case streak       = "Streak"
}

// MARK: - Scheduled Dose

private struct ScheduledDose: Identifiable {
    let medication: Medication
    let log: DoseLog?
    let scheduledTime: Date

    var id: String { "\(medication.persistentModelID)-\(scheduledTime.timeIntervalSince1970)" }

    var status: DoseStatus {
        if log?.isTaken == true { return .taken }
        return scheduledTime <= .now ? .dueNow : .upcoming
    }

    var detailText: String {
        var parts = [medication.doseText]
        if let notes = medication.notes, !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " • ")
    }

    var intakeTags: [DoseIntakeTag] {
        var tags: [DoseIntakeTag] = []
        if medication.withFood  { tags.append(DoseIntakeTag(id: "food",  title: "With food",  icon: "fork.knife")) }
        if medication.withWater { tags.append(DoseIntakeTag(id: "water", title: "With water", icon: "drop.fill"))  }
        return tags
    }
}

private struct DoseIntakeTag: Identifiable {
    let id: String
    let title: String
    let icon: String
}

// MARK: - Main View

struct MedicationsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query private var doseLogs: [DoseLog]

    @State private var selectedTab: MedsTab = .schedule
    @State private var showAdd = false
    @State private var isAddingReminders = false
    @State private var reminderFeedback: ReminderFeedback?
    @State private var reminderAlert: ReminderAlert?
    @State private var interactionActionMessage: String?

    // MARK: Computed

    private var todaysDoses: [ScheduledDose] {
        let calendar = Calendar.current
        var doses: [ScheduledDose] = []

        for medication in medications {
            let logs = doseLogs
                .filter {
                    $0.medication?.persistentModelID == medication.persistentModelID &&
                    calendar.isDateInToday($0.scheduledFor)
                }
                .sorted { $0.scheduledFor < $1.scheduledFor }

            if !logs.isEmpty {
                logs.forEach { doses.append(ScheduledDose(medication: medication, log: $0, scheduledTime: $0.scheduledFor)) }
                continue
            }

            let times = medication.preferredTimes.compactMap(Self.parseTime)
            if times.isEmpty {
                doses.append(ScheduledDose(medication: medication, log: nil, scheduledTime: .now))
            } else {
                times.forEach { doses.append(ScheduledDose(medication: medication, log: nil, scheduledTime: $0)) }
            }
        }

        return doses.sorted { $0.scheduledTime < $1.scheduledTime }
    }

    private var takenCount: Int  { todaysDoses.filter { $0.status == .taken  }.count }
    private var dueNowCount: Int { todaysDoses.filter { $0.status == .dueNow }.count }
    private var totalCount: Int  { todaysDoses.count }
    private var remainingDoseCount: Int { todaysDoses.filter { $0.status != .taken }.count }

    private var reminderDrafts: [MedicationReminderDraft] {
        todaysDoses
            .filter { $0.status != .taken }
            .map { dose in
                let noteLines = [
                    dose.detailText,
                    dose.intakeTags.map(\.title).joined(separator: " • "),
                    "Scheduled for \(formattedReminderTime(for: dose.scheduledTime))",
                    "Added from Interval"
                ]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                return MedicationReminderDraft(
                    title: "Take \(dose.medication.name)",
                    notes: noteLines.joined(separator: "\n"),
                    scheduledTime: dose.scheduledTime,
                    isUrgent: dose.status == .dueNow
                )
            }
    }

    private var interactionReport: MedicationSafetyReport {
        MedicationSafetyEngine.analyzeCurrentMedications(medications)
    }

    private var showcaseInteractionIssue: MedicationInteractionIssue? {
        guard interactionReport.issues.isEmpty else { return nil }

        if let ironMedication = medications.first(where: { $0.name.localizedCaseInsensitiveContains("iron") }) {
            let ironDescriptor = MedicationSafetyDescriptor(ironMedication)
            let anchorTime = ironMedication.preferredTimes.first ?? "8:00 AM"
            let suggestedTime = shiftedTimeString(from: anchorTime, byAddingHours: 2) ?? "10:00 AM"

            return MedicationInteractionIssue(
                id: "showcase-iron-calcium-\(ironDescriptor.id)",
                primary: MedicationSafetyDescriptor.candidate(name: "Calcium", brand: "Supplement", doseText: "500 mg"),
                secondary: ironDescriptor,
                severity: .moderate,
                kind: .timing,
                title: "Minerals can crowd out iron",
                summary: "Calcium and multivitamins can reduce how much iron absorbs when they land too close to your iron dose.",
                recommendation: "Keep your iron at least 2 hours away from calcium or multivitamins so it has a cleaner absorption window.",
                source: "Daily supplement timing",
                scheduleAdjustment: MedicationScheduleAdjustment(
                    targetMedicationID: ironDescriptor.id,
                    targetMedicationName: ironDescriptor.displayName,
                    anchorMedicationName: "Calcium or multivitamin",
                    anchorTime: anchorTime,
                    suggestedTime: suggestedTime,
                    minimumGapHours: 2
                )
            )
        }

        if medications.contains(where: { $0.name.localizedCaseInsensitiveContains("lisinopril") }) {
            return MedicationInteractionIssue(
                id: "showcase-lisinopril-ibuprofen",
                primary: MedicationSafetyDescriptor.candidate(name: "Ibuprofen", doseText: "200 mg"),
                secondary: MedicationSafetyDescriptor.candidate(name: "Lisinopril", doseText: "10 mg"),
                severity: .moderate,
                kind: .monitoring,
                title: "Kidney and blood-pressure caution",
                summary: "Ibuprofen can blunt the blood-pressure effect of lisinopril and add kidney stress if it becomes a repeated pattern.",
                recommendation: "Keep this in mind before adding routine ibuprofen, and check with a clinician if it starts becoming frequent.",
                source: "Curated medication-safety rules",
                scheduleAdjustment: nil
            )
        }

        return nil
    }

    private var interactionIssuesToShow: [MedicationInteractionIssue] {
        if !interactionReport.issues.isEmpty {
            return interactionReport.issues
        }

        return showcaseInteractionIssue.map { [$0] } ?? []
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerSection
                dailyGoalCard
                tabRow

                Group {
                    switch selectedTab {
                    case .schedule:     scheduleContent
                    case .allMeds:      allMedsContent
                    case .interactions: interactionsContent
                    case .streak:       streakContent
                    }
                }

                addMedicationButton
                    .padding(.top, 6)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(pageBackground)
        .sheet(isPresented: $showAdd) {
            NavigationStack { AddMedicationView() }
                .presentationDetents([.large])
        }
        .alert(item: $reminderAlert) { reminderAlert in
            Alert(
                title: Text(reminderAlert.title),
                message: Text(reminderAlert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Background

    private var pageBackground: some View {
        LinearGradient(
            colors: [Theme.Palette.paper, Theme.Palette.paperSoft.opacity(0.96)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayDateLabel)
                        .font(Theme.Font.body(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.Palette.sageDeep)
                        .textCase(.uppercase)

                    Text("Medications")
                        .font(Theme.Font.display(34, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)

                    HStack(spacing: 4) {
                        Text("\(takenCount) taken")
                            .foregroundStyle(Theme.Palette.sageDeep)
                        Text("·")
                            .foregroundStyle(Theme.Palette.inkMuted)
                        Text("\(max(0, totalCount - takenCount)) remaining today")
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    .font(Theme.Font.body(14, weight: .semibold))
                }

                Spacer(minLength: Theme.Space.sm)

                quickReminderButton
            }

            if let reminderFeedback {
                HStack(spacing: 8) {
                    Image(systemName: reminderFeedback.icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(reminderFeedback.message)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .font(Theme.Font.body(12, weight: .semibold))
                .foregroundStyle(reminderFeedback.foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(reminderFeedback.background)
                )
            }
        }
    }

    private var quickReminderButton: some View {
        Button {
            Haptics.tap()
            addTodaysRemainingMedsToReminders()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Palette.card)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline.opacity(0.85), lineWidth: 1)

                if isAddingReminders {
                    ProgressView()
                        .tint(Theme.Palette.primary)
                } else {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.primary)
                }
            }
            .frame(width: 52, height: 52)
            .shadow(color: Theme.Shadow.ambient.opacity(0.4), radius: 12, y: 6)
            .overlay(alignment: .bottomTrailing) {
                if remainingDoseCount > 0 && !isAddingReminders {
                    Text("\(remainingDoseCount)")
                        .font(Theme.Font.body(10, weight: .bold))
                        .foregroundStyle(Theme.Palette.onPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Palette.primary))
                        .offset(x: 4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add today's remaining medications to Reminders")
    }

    private var dayDateLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE · MMM d"
        return fmt.string(from: .now)
    }

    // MARK: - Daily Goal Card

    private var dailyGoalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DAILY GOAL")
                    .font(Theme.Font.body(12, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Palette.inkMuted)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(takenCount)")
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("/ \(totalCount)")
                        .font(Theme.Font.body(16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }

            if totalCount > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<totalCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(index < takenCount ? Theme.Palette.sageDeep : Theme.Palette.hairline)
                            .frame(height: 8)
                    }
                }
            }

            let remaining = max(0, totalCount - takenCount)
            Text(remaining == 0
                 ? "All done for today! Great job."
                 : "\(remaining) dose\(remaining == 1 ? "" : "s") left to hit today's goal.")
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient, radius: 18, y: 10)
        .shadow(color: Theme.Shadow.warm.opacity(0.35), radius: 6, y: 2)
    }

    // MARK: - Tab Row

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(MedsTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.select()
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(Theme.Font.body(13, weight: selectedTab == tab ? .bold : .semibold))
                        .foregroundStyle(selectedTab == tab ? Theme.Palette.onPrimary : Theme.Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? Theme.Palette.sageDeep : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Palette.paperSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Schedule Tab

    @ViewBuilder
    private var scheduleContent: some View {
        if todaysDoses.isEmpty {
            emptyState
        } else {
            VStack(spacing: 12) {
                ForEach(todaysDoses) { dose in
                    scheduleRow(dose)
                }
            }
        }
    }

    private func scheduleRow(_ dose: ScheduledDose) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left time + status column
            VStack(alignment: .trailing, spacing: 3) {
                Text(dose.scheduledTime, style: .time)
                    .font(Theme.Font.body(13, weight: .bold))
                    .foregroundStyle(
                        dose.status == .taken ? Theme.Palette.inkMuted :
                        dose.status == .dueNow ? Theme.Palette.coralDeep :
                        Theme.Palette.ink
                    )
                Text(dose.status == .taken ? "TAKEN" :
                     dose.status == .dueNow ? "NOW" : "UPCOMING")
                    .font(Theme.Font.body(9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(
                        dose.status == .taken ? Theme.Palette.inkMuted :
                        dose.status == .dueNow ? Theme.Palette.coralDeep :
                        Theme.Palette.sageDeep
                    )
            }
            .frame(width: 64, alignment: .trailing)
            .padding(.top, 16)

            // Card
            doseCard(dose)
        }
    }

    // MARK: - All Meds Tab

    @ViewBuilder
    private var allMedsContent: some View {
        if medications.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(Array(medications.enumerated()), id: \.element.persistentModelID) { index, med in
                    allMedRow(med)
                    if index < medications.count - 1 {
                        Divider()
                            .padding(.leading, 70)
                            .foregroundStyle(Theme.Palette.hairline)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Theme.Shadow.ambient, radius: 18, y: 10)
            .shadow(color: Theme.Shadow.warm.opacity(0.35), radius: 6, y: 2)
        }
    }

    private func allMedRow(_ med: Medication) -> some View {
        HStack(spacing: 14) {
            medIcon(for: med, tone: .upcoming)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(med.name)
                        .font(Theme.Font.body(16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("·")
                        .foregroundStyle(Theme.Palette.inkMuted)
                    Text(med.doseText)
                        .font(Theme.Font.body(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }

                HStack(spacing: 4) {
                    Text(med.scheduleText)
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)

                    if let qty = med.quantityRemaining, qty > 0 {
                        Text("·")
                            .foregroundStyle(Theme.Palette.hairline)
                        Text("\(qty) left")
                            .font(Theme.Font.body(13, weight: .semibold))
                            .foregroundStyle(qty <= 7 ? Theme.Palette.coralDeep : Theme.Palette.inkMuted)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.hairline)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 14)
    }

    // MARK: - Interactions Tab

    @ViewBuilder
    private var interactionsContent: some View {
        if medications.count < 2 {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nothing to check yet")
                        .font(Theme.Font.display(22, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Interaction checking kicks in once you have at least 2 medications added.")
                        .font(Theme.Font.body(15, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )

                if let showcaseInteractionIssue {
                    interactionIssueCard(showcaseInteractionIssue, showsAcceptButton: true)
                }
            }
        } else {
            let report = interactionReport
            let shownIssues = interactionIssuesToShow

            VStack(spacing: 16) {
                interactionOverviewCard(pairCount: report.pairAssessments.count, issueCount: shownIssues.count)

                if let interactionActionMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(interactionActionMessage)
                            .lineLimit(2)
                    }
                    .font(Theme.Font.body(12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.sageDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(Theme.Palette.mint))
                }

                if shownIssues.isEmpty {
                    noIssueCard(report)
                } else {
                    ForEach(shownIssues) { issue in
                        interactionIssueCard(issue, showsAcceptButton: report.issues.isEmpty)
                    }
                }

                if !report.clearPairs.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("CHECKED · NO CONFLICTS")
                                .font(Theme.Font.body(11, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(Theme.Palette.inkMuted)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                        Divider()
                            .padding(.horizontal, Theme.Space.md)

                        ForEach(Array(report.clearPairs.enumerated()), id: \.element.id) { index, assessment in
                            noConflictRow(assessment)
                            if index < report.clearPairs.count - 1 {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.Palette.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Theme.Palette.hairline.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: Theme.Shadow.ambient, radius: 18, y: 10)
                }
            }
        }
    }

    private func interactionOverviewCard(pairCount: Int, issueCount: Int) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(issueCount == 0 ? "Interaction check looks clean" : "Review these interaction alerts")
                    .font(Theme.Font.body(18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(pairCount) pair\(pairCount == 1 ? "" : "s") checked across your current medication list.")
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }

            Spacer()

            StatusChip(
                text: issueCount == 0 ? "Clear" : "\(issueCount) alert\(issueCount == 1 ? "" : "s")",
                kind: issueCount == 0 ? .done : .warn
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.35), radius: 16, y: 8)
    }

    private func noIssueCard(_ report: MedicationSafetyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.sageDeep)
                Text("No actionable issues found")
                    .font(Theme.Font.body(16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
            }

            Text("I did not find a medication pair that needs spacing changes, a major class warning, or a matched allergy flag in the current list.")
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)

            Text("This screen is a quick safety check, not a full medication review. New prescriptions and short-term meds can still change the picture.")
                .font(Theme.Font.body(13, weight: .medium))
                .foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Palette.primaryFixed.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.Palette.primary.opacity(0.14), lineWidth: 1)
        )
    }

    private func interactionIssueCard(_ issue: MedicationInteractionIssue, showsAcceptButton: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: interactionIcon(for: issue))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(interactionAccent(for: issue))
                Text(interactionEyebrow(for: issue))
                    .font(Theme.Font.body(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(interactionAccent(for: issue))
                Spacer()
                StatusChip(text: issue.severity.label, kind: interactionStatusKind(for: issue))
            }

            HStack(spacing: 10) {
                medPairIcon()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.inkMuted)
                medPairIcon()

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.primary.displayName)
                        .font(Theme.Font.body(16, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("+ \(issue.secondary.displayName)")
                        .font(Theme.Font.body(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }

            Text(issue.summary)
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT TO DO")
                    .font(Theme.Font.body(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Palette.inkMuted)
                Text(issue.recommendation)
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let adjustment = issue.scheduleAdjustment {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SUGGESTED SCHEDULE")
                        .font(Theme.Font.body(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.Palette.inkMuted)

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(adjustment.anchorTime)
                                .font(Theme.Font.body(16, weight: .bold))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(adjustment.anchorMedicationName)
                                .font(Theme.Font.body(12, weight: .medium))
                                .foregroundStyle(Theme.Palette.inkSoft)
                                .lineLimit(1)
                        }

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(adjustment.minimumGapHours)h gap")
                                .font(Theme.Font.body(12, weight: .bold))
                        }
                        .foregroundStyle(Theme.Palette.sageDeep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Palette.sage.opacity(0.35)))

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(adjustment.suggestedTime)
                                .font(Theme.Font.body(16, weight: .bold))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(adjustment.targetMedicationName)
                                .font(Theme.Font.body(12, weight: .medium))
                                .foregroundStyle(Theme.Palette.inkSoft)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.Palette.paperSoft)
                )

            }

            if showsAcceptButton {
                Button {
                    acceptShowcaseInteraction(issue)
                } label: {
                    Text(issue.scheduleAdjustment == nil ? "Accept alert" : "Accept plan")
                        .font(Theme.Font.body(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.Palette.ink))
                }
                .buttonStyle(.plain)
            } else if let adjustment = issue.scheduleAdjustment {
                Button {
                    applySuggestedSchedule(adjustment)
                } label: {
                    Text("Apply \(adjustment.suggestedTime) for \(adjustment.targetMedicationName)")
                        .font(Theme.Font.body(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.Palette.ink))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                PillTag(
                    text: issue.source,
                    fill: Theme.Palette.surfaceContainerLowest,
                    border: Theme.Palette.outlineVariant,
                    foreground: Theme.Palette.inkMuted,
                    icon: "checklist"
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(interactionCardFill(for: issue))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(interactionAccent(for: issue).opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: interactionAccent(for: issue).opacity(0.08), radius: 18, y: 10)
    }

    private func noConflictRow(_ assessment: MedicationPairAssessment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.sage.opacity(0.5))
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.sageDeep)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(assessment.primary.displayName) + \(assessment.secondary.displayName)")
                    .font(Theme.Font.body(14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("No known interaction")
                    .font(Theme.Font.body(13, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkMuted)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 12)
    }

    private func interactionEyebrow(for issue: MedicationInteractionIssue) -> String {
        switch issue.kind {
        case .timing: "TIMING ISSUE"
        case .allergy: "ALLERGY ALERT"
        case .duplicateTherapy: "CLASS OVERLAP"
        case .monitoring: "MEDICATION REVIEW"
        }
    }

    private func interactionIcon(for issue: MedicationInteractionIssue) -> String {
        switch issue.kind {
        case .timing: "clock.badge.exclamationmark.fill"
        case .allergy: "exclamationmark.triangle.fill"
        case .duplicateTherapy: "pills.circle.fill"
        case .monitoring: "stethoscope"
        }
    }

    private func interactionStatusKind(for issue: MedicationInteractionIssue) -> StatusChip.Kind {
        switch issue.severity {
        case .low: .ask
        case .moderate: .warn
        case .high: .flag
        }
    }

    private func interactionAccent(for issue: MedicationInteractionIssue) -> Color {
        switch issue.severity {
        case .low: Theme.Palette.primary
        case .moderate: Theme.Palette.coralDeep
        case .high: Theme.Palette.error
        }
    }

    private func interactionCardFill(for issue: MedicationInteractionIssue) -> Color {
        switch issue.severity {
        case .low: Theme.Palette.primaryFixed.opacity(0.35)
        case .moderate: Theme.Palette.peachTint.opacity(0.35)
        case .high: Theme.Palette.errorContainer.opacity(0.65)
        }
    }

    // MARK: - Streak Tab

    @ViewBuilder
    private var streakContent: some View {
        let streak    = currentStreak
        let adherence = weeklyAdherence

        VStack(spacing: 16) {
            // Stats card
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(streak)")
                        .font(Theme.Font.display(48, weight: .bold))
                        .foregroundStyle(Theme.Palette.sageDeep)
                    Text("day streak")
                        .font(Theme.Font.body(16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(adherence * 100))%")
                        .font(Theme.Font.display(36, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("this week")
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Palette.sage.opacity(0.55), Theme.Palette.paperSoft],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.Palette.sageDeep.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Theme.Palette.sageDeep.opacity(0.10), radius: 16, y: 10)

            // 7-day dots
            weeklyDotView
        }
    }

    private var weeklyDotView: some View {
        let calendar = Calendar.current
        let today    = Date()
        let weekdays = (0..<7).compactMap { calendar.date(byAdding: .day, value: -6 + $0, to: today) }

        return VStack(alignment: .leading, spacing: 14) {
            Text("LAST 7 DAYS")
                .font(Theme.Font.body(11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.inkMuted)

            HStack(spacing: 6) {
                ForEach(weekdays, id: \.self) { day in
                    let isToday  = calendar.isDateInToday(day)
                    let isFuture = day > today
                    let dayLogs  = doseLogs.filter { calendar.isDate($0.scheduledFor, inSameDayAs: day) }
                    let taken    = dayLogs.filter { $0.isTaken }.count
                    let total    = dayLogs.count
                    let allGood  = total > 0 && taken == total

                    VStack(spacing: 6) {
                        Text(shortDayLabel(day))
                            .font(Theme.Font.body(11, weight: isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? Theme.Palette.sageDeep : Theme.Palette.inkMuted)

                        ZStack {
                            Circle()
                                .fill(
                                    isFuture || total == 0 ? Theme.Palette.hairline.opacity(0.35) :
                                    allGood               ? Theme.Palette.sageDeep :
                                    Theme.Palette.coralDeep
                                )
                                .frame(width: 30, height: 30)

                            if isToday {
                                Circle()
                                    .strokeBorder(Theme.Palette.sageDeep, lineWidth: 2)
                                    .frame(width: 30, height: 30)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient, radius: 18, y: 10)
    }

    private func shortDayLabel(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "E"
        return String(fmt.string(from: date).prefix(1))
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var day = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        for _ in 0..<60 {
            let dayLogs = doseLogs.filter { calendar.isDate($0.scheduledFor, inSameDayAs: day) }
            guard !dayLogs.isEmpty, dayLogs.allSatisfy({ $0.isTaken }) else { break }
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    private var weeklyAdherence: Double {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = doseLogs.filter { $0.scheduledFor >= start && $0.scheduledFor < Date() }
        guard !recent.isEmpty else { return 0 }
        return Double(recent.filter { $0.isTaken }.count) / Double(recent.count)
    }

    // MARK: - Dose Cards (unchanged visual style)

    @ViewBuilder
    private func doseCard(_ dose: ScheduledDose) -> some View {
        switch dose.status {
        case .taken:    takenCard(dose)
        case .dueNow:   dueNowCard(dose)
        case .upcoming: upcomingCard(dose)
        }
    }

    private func takenCard(_ dose: ScheduledDose) -> some View {
        HStack(alignment: .top, spacing: 14) {
            medIcon(for: dose.medication, tone: .taken)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dose.medication.name)
                        .font(Theme.Font.body(18, weight: .semibold))
                        .strikethrough(color: Theme.Palette.inkMuted)
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Text(dose.scheduledTime, style: .time)
                        .font(Theme.Font.body(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if let notes = dose.medication.notes, !notes.isEmpty {
                    Text(notes)
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .lineLimit(2)
                } else {
                    Text(dose.detailText)
                        .font(Theme.Font.body(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .lineLimit(2)
                }

                footerRow(for: dose, tone: .taken) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                        Text("Taken")
                            .font(Theme.Font.body(12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Palette.sageDeep))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.Palette.sage.opacity(0.8), lineWidth: 1.6)
        )
        .shadow(color: Theme.Palette.ink.opacity(0.03), radius: 10, y: 6)
    }

    private func dueNowCard(_ dose: ScheduledDose) -> some View {
        HStack(alignment: .top, spacing: 14) {
            medIcon(for: dose.medication, tone: .urgent)

            VStack(alignment: .leading, spacing: 12) {
                dueNowHeader(dose)

                if let notes = dose.medication.notes, !notes.isEmpty {
                    Text(notes)
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(2)
                } else {
                    Text(dose.detailText)
                        .font(Theme.Font.body(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(2)
                }

                footerRow(for: dose, tone: .urgent) {
                    Button {
                        Haptics.tap()
                        markTaken(dose)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Take")
                            Image(systemName: "drop.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.Palette.sageDeep))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Theme.Palette.ink.opacity(0.05), radius: 14, y: 8)
    }

    private func upcomingCard(_ dose: ScheduledDose) -> some View {
        HStack(alignment: .top, spacing: 14) {
            medIcon(for: dose.medication, tone: .upcoming)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dose.medication.name)
                        .font(Theme.Font.body(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Text(dose.scheduledTime, style: .time)
                        .font(Theme.Font.body(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if let notes = dose.medication.notes, !notes.isEmpty {
                    Text(notes)
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(2)
                } else {
                    Text(dose.detailText)
                        .font(Theme.Font.body(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(2)
                }

                footerRow(for: dose, tone: .upcoming) {
                    Button {
                        Haptics.tap()
                        markTaken(dose)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Take")
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.Palette.sageDeep))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: Theme.Palette.ink.opacity(0.035), radius: 12, y: 7)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing scheduled yet")
                .font(Theme.Font.display(24, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Add a medication and Interval will track it in your daily timeline.")
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
    }

    // MARK: - Atoms

    private enum IconTone { case taken, urgent, upcoming }

    private func medIcon(for medication: Medication, tone: IconTone) -> some View {
        let fill: Color = {
            switch tone {
            case .taken:    return Theme.Palette.paperSoft
            case .urgent:   return Theme.Palette.peachTint
            case .upcoming: return Theme.Palette.paperSoft
            }
        }()
        let foreground: Color = {
            switch tone {
            case .taken:    return Theme.Palette.sageDeep
            case .urgent:   return Theme.Palette.coralDeep
            case .upcoming: return Theme.Palette.inkMuted
            }
        }()
        return ZStack {
            Circle()
                .fill(fill)
                .frame(width: 46, height: 46)
            Image(systemName: symbol(for: medication.form))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
        }
    }

    private func medPairIcon() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Palette.paperSoft)
                .frame(width: 38, height: 38)
            Image(systemName: "pills.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkMuted)
        }
    }

    @ViewBuilder
    private func footerRow<Accessory: View>(
        for dose: ScheduledDose,
        tone: IconTone,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                intakeTagRow(dose.intakeTags, tone: tone)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 8)
                accessory().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 12) {
                intakeTagRow(dose.intakeTags, tone: tone)
                HStack {
                    Spacer()
                    accessory().fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    @ViewBuilder
    private func dueNowHeader(_ dose: ScheduledDose) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 8) { doseName(dose); dueNowBadge }
                Spacer(minLength: 8)
                dueNowTime(dose)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { doseName(dose); dueNowBadge }
                dueNowTime(dose)
            }
        }
    }

    private func doseName(_ dose: ScheduledDose) -> some View {
        Text(dose.medication.name)
            .font(Theme.Font.body(18, weight: .bold))
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .layoutPriority(1)
    }

    private var dueNowBadge: some View {
        Text("DUE NOW")
            .font(Theme.Font.body(10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.Palette.coralDeep))
    }

    private func dueNowTime(_ dose: ScheduledDose) -> some View {
        Text(dose.scheduledTime, style: .time)
            .font(Theme.Font.body(16, weight: .bold))
            .foregroundStyle(Theme.Palette.coralDeep)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func intakeTagRow(_ tags: [DoseIntakeTag], tone: IconTone) -> some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(tags) { tag in
                    intakeTag(tag, tone: tone)
                }
            }
        }
    }

    private func intakeTag(_ tag: DoseIntakeTag, tone: IconTone) -> some View {
        let fill: Color = {
            switch tone {
            case .taken:    return Theme.Palette.paperSoft
            case .urgent:   return Theme.Palette.peachTint
            case .upcoming: return Theme.Palette.paperSoft
            }
        }()
        let foreground: Color = {
            switch tone {
            case .taken:    return Theme.Palette.inkMuted
            case .urgent:   return Theme.Palette.coralDeep
            case .upcoming: return Theme.Palette.inkSoft
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: tag.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(tag.title)
                .font(Theme.Font.body(12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .fixedSize(horizontal: true, vertical: false)
        .background(Capsule().fill(fill))
    }

    private func symbol(for form: DoseForm) -> String {
        switch form {
        case .tablet, .capsule: return "pills.fill"
        case .liquid, .drops:   return "drop.fill"
        case .injection:        return "syringe.fill"
        case .patch:            return "cross.case.fill"
        case .inhaler:          return "cross.vial.fill"
        }
    }

    // MARK: - Add Button

    private var addMedicationButton: some View {
        Button {
            Haptics.tap()
            showAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Add Medication")
                    .font(Theme.Font.body(17, weight: .bold))
            }
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Capsule().fill(Theme.Palette.sunny))
            .shadow(color: Theme.Palette.sunny.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 36)
    }

    // MARK: - Actions

    private func markTaken(_ dose: ScheduledDose) {
        if let log = dose.log {
            if log.isTaken { log.takenAt = nil; Haptics.select() }
            else            { log.takenAt = .now; Haptics.success() }
        } else {
            let log = DoseLog(medication: dose.medication, scheduledFor: dose.scheduledTime, takenAt: .now)
            context.insert(log)
            Haptics.success()
        }
        try? context.save()
    }

    private func applySuggestedSchedule(_ adjustment: MedicationScheduleAdjustment) {
        guard let medication = medications.first(where: { String(describing: $0.persistentModelID) == adjustment.targetMedicationID }) else {
            interactionActionMessage = "I couldn't find that medication to update its schedule."
            Haptics.error()
            return
        }

        var updatedTimes = medication.preferredTimes
        if updatedTimes.isEmpty {
            updatedTimes = [adjustment.suggestedTime]
        } else {
            updatedTimes[0] = adjustment.suggestedTime
        }
        medication.updatePreferredTimes(updatedTimes)

        if let newTime = Self.parseTime(adjustment.suggestedTime) {
            let calendar = Calendar.current
            for log in doseLogs where log.medication?.persistentModelID == medication.persistentModelID {
                guard calendar.isDateInToday(log.scheduledFor), !log.isTaken else { continue }
                log.scheduledFor = newTime
            }
        }

        try? context.save()
        interactionActionMessage = "Moved \(medication.name) to \(adjustment.suggestedTime)."
        Haptics.success()
    }

    private func acceptShowcaseInteraction(_ issue: MedicationInteractionIssue) {
        if let adjustment = issue.scheduleAdjustment {
            applySuggestedSchedule(adjustment)
            return
        }

        interactionActionMessage = "Okay — I'll keep this interaction on your radar."
        Haptics.success()
    }

    private func addTodaysRemainingMedsToReminders() {
        guard !isAddingReminders else { return }

        let drafts = reminderDrafts
        guard !drafts.isEmpty else {
            reminderFeedback = ReminderFeedback(
                icon: "checkmark.circle.fill",
                message: "Everything for today is already taken.",
                foreground: Theme.Palette.sageDeep,
                background: Theme.Palette.mint
            )
            Haptics.select()
            return
        }

        isAddingReminders = true
        reminderFeedback = nil

        Task { @MainActor in
            do {
                let result = try await AppleRemindersStore.shared.addMedicationReminders(for: drafts)
                isAddingReminders = false
                reminderFeedback = feedback(for: result)
                if result.addedCount > 0 { Haptics.success() } else { Haptics.select() }
            } catch {
                isAddingReminders = false
                reminderAlert = ReminderAlert(
                    title: "Couldn't Add Reminders",
                    message: (error as? LocalizedError)?.errorDescription ?? "Something went wrong while adding today's medications to Apple Reminders."
                )
                Haptics.error()
            }
        }
    }

    private func feedback(for result: ReminderImportResult) -> ReminderFeedback {
        if result.addedCount > 0 && result.skippedCount > 0 {
            return ReminderFeedback(
                icon: "checkmark.circle.fill",
                message: "Added \(result.addedCount) reminder\(result.addedCount == 1 ? "" : "s") · \(result.skippedCount) already there",
                foreground: Theme.Palette.sageDeep,
                background: Theme.Palette.mint
            )
        }

        if result.addedCount > 0 {
            return ReminderFeedback(
                icon: "checkmark.circle.fill",
                message: "Added \(result.addedCount) reminder\(result.addedCount == 1 ? "" : "s") to Apple Reminders",
                foreground: Theme.Palette.sageDeep,
                background: Theme.Palette.mint
            )
        }

        return ReminderFeedback(
            icon: "list.bullet.clipboard",
            message: "Today's remaining meds are already in Reminders.",
            foreground: Theme.Palette.primary,
            background: Theme.Palette.primaryFixed
        )
    }

    private func formattedReminderTime(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func shiftedTimeString(from rawTime: String, byAddingHours hours: Int) -> String? {
        guard let base = Self.parseTime(rawTime) else { return nil }
        return formattedReminderTime(for: base.addingTimeInterval(Double(hours) * 3600))
    }

    // MARK: - Helpers

    nonisolated private static func parseTime(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: string) else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: .now)
    }
}

private struct ReminderFeedback {
    let icon: String
    let message: String
    let foreground: Color
    let background: Color
}

private struct ReminderAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    NavigationStack { MedicationsView() }
        .modelContainer(previewContainer())
}
