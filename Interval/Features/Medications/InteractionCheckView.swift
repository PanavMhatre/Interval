import SwiftUI
import SwiftData

struct InteractionCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query private var profiles: [UserProfile]

    let newMedName: String
    let newBrand: String?
    let newDose: String
    let withFood: Bool
    let withWater: Bool
    var onAdd: () -> Void

    @State private var ai = IntervalAI()
    @State private var aiReview: InteractionReviewContent?

    private var profile: UserProfile? { profiles.first }

    private var report: MedicationAdditionReport {
        MedicationSafetyEngine.analyzeAddition(
            candidateName: newMedName,
            candidateBrand: newBrand,
            candidateDoseText: newDose,
            currentMedications: medications,
            profile: profile
        )
    }

    private var headlineText: String {
        if let severity = report.highestSeverity {
            switch severity {
            case .high: return "Something needs a closer look"
            case .moderate: return "There is one thing to review"
            case .low: return "A quick detail to review"
            }
        }

        return "All clear so far"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    Button { Haptics.tap(); dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    .buttonStyle(.plain)
                    Text("Interaction check")
                        .font(Theme.Font.display(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    StatusChip(
                        text: report.isClear ? "Clear" : "\(report.issueCount) alert\(report.issueCount == 1 ? "" : "s")",
                        kind: report.isClear ? .done : statusKind(for: report.highestSeverity)
                    )
                }

                DashedHairline()

                heroCard

                if let aiReview {
                    aiSummaryCard(aiReview)
                }

                if report.isClear {
                    clearCard
                } else {
                    ForEach(report.issues) { issue in
                        issueCard(issue)
                    }
                }

                checkedAgainstCard

                HStack(spacing: 10) {
                    GhostButton(title: report.isClear ? "Back" : "Ask doctor first", dashed: true) {
                        Haptics.select()
                        dismiss()
                    }
                    PrimaryButton(title: report.isClear ? "Add medication" : "Add anyway", icon: nil) {
                        onAdd()
                        dismiss()
                    }
                }

                Text("Not a substitute for medical advice.".uppercased())
                    .font(Theme.Font.body(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Palette.inkMuted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
        }
        .background(Theme.Palette.paper)
        .task {
            ai.prepare(with: context)
            aiReview = await ai.generateInteractionReview(
                candidateName: newMedName,
                checkedMedications: report.checkedMedications.map(\.displayName),
                allergies: profile?.allergies ?? [],
                issues: report.issues
            )
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: report.isClear ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(report.isClear ? Theme.Palette.sageDeep : heroAccent)
                Text((report.isClear ? "Checked" : "Review").uppercased())
                    .font(Theme.Font.body(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(report.isClear ? Theme.Palette.sageDeep : heroAccent)
                Spacer()
                Text(report.highestSeverity?.label.uppercased() ?? "CLEAR")
                    .font(Theme.Font.body(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }

            Text(headlineText)
                .font(Theme.Font.display(22, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)

            Text(newMedName + (newBrand.map { " · \($0)" } ?? ""))
                .font(Theme.Font.body(15, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSoft)

            Text("I checked this against \(report.checkedMedications.count) medication\(report.checkedMedications.count == 1 ? "" : "s") and \(profile?.allergies.count ?? 0) allergy item\(profile?.allergies.count == 1 ? "" : "s") from the loaded profile.")
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(report.isClear ? Theme.Palette.primaryFixed.opacity(0.42) : heroFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(heroAccent.opacity(0.28), lineWidth: 1)
        )
    }

    private func aiSummaryCard(_ review: InteractionReviewContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primary)
                Text("Apple Intelligence summary".uppercased())
                    .font(Theme.Font.body(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Palette.primary)
            }

            Text(review.headline)
                .font(Theme.Font.body(16, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)

            Text(review.summary)
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Text(review.nextStep)
                .font(Theme.Font.body(13, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
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

    private var clearCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.sageDeep)
                Text("No direct issue found")
                    .font(Theme.Font.body(16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
            }

            Text("I did not find a direct medication-pair conflict, class overlap, or allergy match for this addition in the loaded record.")
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private func issueCard(_ issue: MedicationInteractionIssue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusChip(text: issue.severity.label, kind: statusKind(for: issue.severity))
                Text(issue.title)
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
            }

            HStack(spacing: 10) {
                medPairCard(name: issue.primary.displayName, label: "New", dose: newDose, accent: issueAccent(for: issue))
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(issueAccent(for: issue))
                medPairCard(
                    name: issue.secondary.displayName,
                    label: issue.kind == .allergy ? "Allergy" : "Current",
                    dose: issue.kind == .allergy ? "Profile match" : doseLabel(for: issue.secondary),
                    accent: Theme.Palette.ink
                )
            }

            Text(issue.summary)
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Text(issue.recommendation)
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let adjustment = issue.scheduleAdjustment {
                HStack(spacing: 8) {
                    PillTag(text: adjustment.anchorMedicationName, fill: Theme.Palette.paperSoft, foreground: Theme.Palette.ink, icon: "clock.fill")
                    Text("then")
                        .font(Theme.Font.body(12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                    PillTag(text: adjustment.suggestedTime, fill: Theme.Palette.primaryFixed, foreground: Theme.Palette.primary, icon: "arrow.right")
                }
            }

            PillTag(
                text: issue.source,
                fill: Theme.Palette.surfaceContainerLowest,
                border: Theme.Palette.outlineVariant,
                foreground: Theme.Palette.inkMuted,
                icon: "checklist"
            )
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(issueFill(for: issue))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(issueAccent(for: issue).opacity(0.25), lineWidth: 1)
        )
    }

    private var checkedAgainstCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Checked against".uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.inkMuted)

            FlowLayout(spacing: 8) {
                ForEach(report.checkedMedications, id: \.id) { med in
                    PillTag(text: med.displayName)
                }

                ForEach(profile?.allergies ?? [], id: \.self) { allergy in
                    PillTag(
                        text: allergy,
                        fill: Theme.Palette.surfaceContainerLowest,
                        border: Theme.Palette.outlineVariant,
                        foreground: Theme.Palette.inkSoft,
                        icon: "exclamationmark.circle"
                    )
                }
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(fill: Theme.Palette.paperSoft)
    }

    private func medPairCard(name: String, label: String, dose: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(Theme.Font.display(16, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("\(label.uppercased()) · \(dose)")
                .font(Theme.Font.body(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func statusKind(for severity: MedicationInteractionSeverity?) -> StatusChip.Kind {
        switch severity {
        case .some(.high): .flag
        case .some(.moderate): .warn
        case .some(.low): .ask
        case .none: .done
        }
    }

    private var heroAccent: Color {
        switch report.highestSeverity {
        case .some(.high): Theme.Palette.error
        case .some(.moderate): Theme.Palette.coralDeep
        case .some(.low): Theme.Palette.primary
        case .none: Theme.Palette.sageDeep
        }
    }

    private var heroFill: Color {
        switch report.highestSeverity {
        case .some(.high): Theme.Palette.errorContainer
        case .some(.moderate): Theme.Palette.peachTint
        case .some(.low): Theme.Palette.primaryFixed
        case .none: Theme.Palette.primaryFixed
        }
    }

    private func issueAccent(for issue: MedicationInteractionIssue) -> Color {
        switch issue.severity {
        case .low: Theme.Palette.primary
        case .moderate: Theme.Palette.coralDeep
        case .high: Theme.Palette.error
        }
    }

    private func issueFill(for issue: MedicationInteractionIssue) -> Color {
        switch issue.severity {
        case .low: Theme.Palette.primaryFixed.opacity(0.4)
        case .moderate: Theme.Palette.peachTint.opacity(0.45)
        case .high: Theme.Palette.errorContainer.opacity(0.78)
        }
    }

    private func doseLabel(for descriptor: MedicationSafetyDescriptor) -> String {
        let trimmed = descriptor.doseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "On file" : trimmed
    }
}

#Preview {
    NavigationStack {
        InteractionCheckView(
            newMedName: "Ibuprofen",
            newBrand: "Advil",
            newDose: "200 mg",
            withFood: true,
            withWater: true
        ) {}
    }
    .modelContainer(previewContainer())
}
