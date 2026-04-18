import SwiftUI
import SwiftData

struct InteractionCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var medications: [Medication]

    let newMedName: String
    let newDose: String
    var onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    Button { Haptics.tap(); dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }.buttonStyle(.plain)
                    Text("Interaction check")
                        .font(Theme.Font.display(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    StatusChip(text: "1 issue", kind: .warn)
                }
                DashedHairline()

                // Careful banner
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.coralDeep)
                        Text("Careful".uppercased())
                            .font(Theme.Font.body(11, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.Palette.coralDeep)
                        Spacer()
                        Text("Moderate risk".uppercased())
                            .font(Theme.Font.body(10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                    Text("\(newMedName) + Lisinopril")
                        .font(Theme.Font.display(22, weight: .bold))
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
                        .strokeBorder(Theme.Palette.coral.opacity(0.5), lineWidth: 1)
                )

                // Pair detail
                HStack(spacing: 10) {
                    medPairCard(name: newMedName, label: "New", dose: newDose, accent: Theme.Palette.coralDeep)
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                    medPairCard(name: "Lisinopril", label: "Current", dose: "10mg", accent: Theme.Palette.ink)
                }

                // Plain words
                VStack(alignment: .leading, spacing: 8) {
                    Text("In plain words".uppercased())
                        .font(Theme.Font.eyebrow)
                        .tracking(1)
                        .foregroundStyle(Theme.Palette.inkMuted)
                    Text("Taking NSAIDs with ACE inhibitors may reduce blood-pressure control and stress the kidneys. Short-term is usually fine — avoid daily use.")
                        .font(Theme.Font.body(15))
                        .foregroundStyle(Theme.Palette.ink)
                    HStack {
                        PillTag(text: "openFDA", icon: "link")
                        PillTag(text: "RxNorm", icon: "link")
                        Spacer()
                        Text("Source")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                }
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard()

                // Safer spacing
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Safer spacing".uppercased())
                            .font(Theme.Font.eyebrow)
                            .tracking(1)
                            .foregroundStyle(Theme.Palette.coralDeep)
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.coralDeep)
                        Spacer()
                    }
                    Text("Take \(newMedName.lowercased()) 2+ hours after lisinopril and drink water.")
                        .font(Theme.Font.body(15, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                }
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Palette.peachSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.coral.opacity(0.35), lineWidth: 1)
                )

                HStack(spacing: 10) {
                    GhostButton(title: "Ask doctor first", dashed: true) {
                        Haptics.select()
                        dismiss()
                    }
                    PrimaryButton(title: "Add anyway", icon: nil) {
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
}

#Preview {
    NavigationStack {
        InteractionCheckView(newMedName: "Ibuprofen", newDose: "200mg") {}
    }
    .modelContainer(previewContainer())
}
