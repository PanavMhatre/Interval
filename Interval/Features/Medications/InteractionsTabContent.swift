import SwiftUI

struct InteractionsTabContent: View {
    let medications: [Medication]
    let allergies: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            summaryBanner
            if !interactionTips.isEmpty {
                interactionSection
            }
            if !avoidances.isEmpty {
                avoidanceSection
            }
            if !allergies.isEmpty {
                allergySection
            }
        }
    }

    // MARK: - Data

    private var allTips: [SideEffectTip] {
        MedicationAdvisor.tips(medications: medications, allergies: [])
    }

    private var interactionTips: [SideEffectTip] {
        MedicationAdvisor.interactionPairs(from: allTips)
    }

    private var avoidances: [MedicationAdvisor.Avoidance] {
        MedicationAdvisor.avoidances(for: medications)
    }

    // MARK: - Summary

    private var summaryBanner: some View {
        let issueCount = interactionTips.count
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(issueCount == 0 ? Theme.Palette.mint : Theme.Palette.peachTint)
                    .frame(width: 40, height: 40)
                Image(systemName: issueCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(issueCount == 0 ? Theme.Palette.sageDeep : Theme.Palette.coralDeep)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(issueCount == 0 ? "All clear" : "\(issueCount) interaction\(issueCount == 1 ? "" : "s") to watch")
                    .font(Theme.Font.body(16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(issueCount == 0
                     ? "Your current meds don't flag any known interactions."
                     : "Tap any card to review the safer-spacing guidance.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer()
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(interactionTips.isEmpty ? Theme.Palette.mint.opacity(0.4) : Theme.Palette.peachSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(
                    (interactionTips.isEmpty ? Theme.Palette.sageDeep : Theme.Palette.coralDeep).opacity(0.3),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Interactions section

    private var interactionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Drug interactions".uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.inkMuted)
            VStack(spacing: 8) {
                ForEach(interactionTips) { tip in
                    interactionCard(tip)
                }
            }
        }
    }

    private func interactionCard(_ tip: SideEffectTip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tip.tint)
                Text(tip.source)
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                StatusChip(text: severityText(tip.severity), kind: severityKind(tip.severity))
            }
            Text(tip.effect)
                .font(Theme.Font.body(13, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
            DashedHairline()
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(tip.tint)
                    .padding(.top, 3)
                Text(tip.mitigation)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    // MARK: - Avoidance section

    private var avoidanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Things to avoid".uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.inkMuted)
            VStack(spacing: 8) {
                ForEach(avoidances) { avoidance in
                    avoidanceCard(avoidance)
                }
            }
        }
    }

    private func avoidanceCard(_ a: MedicationAdvisor.Avoidance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.Palette.peachTint).frame(width: 30, height: 30)
                    Image(systemName: "pills.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                }
                Text(a.medication)
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(a.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.coralDeep)
                        Text(item)
                            .font(Theme.Font.bodyText)
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    // MARK: - Allergies

    private var allergySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Image(systemName: "flag.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.coralDeep)
                Text("Allergy reminders".uppercased())
                    .font(Theme.Font.eyebrow)
                    .tracking(1)
                    .foregroundStyle(Theme.Palette.coralDeep)
            }
            VStack(spacing: 8) {
                ForEach(allergies, id: \.self) { allergy in
                    HStack(spacing: 10) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.coralDeep)
                        Text(allergy)
                            .font(Theme.Font.body(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Text("Flag before new Rx")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                    .padding(Theme.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .fill(Theme.Palette.peachTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(Theme.Palette.coral.opacity(0.4), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func severityText(_ s: SideEffectTip.Severity) -> String {
        switch s {
        case .important: "Watch"
        case .caution:   "Careful"
        case .info:      "FYI"
        }
    }

    private func severityKind(_ s: SideEffectTip.Severity) -> StatusChip.Kind {
        switch s {
        case .important: .warn
        case .caution:   .flag
        case .info:      .later
        }
    }
}
