import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query(sort: [SortDescriptor(\LabResult.capturedAt, order: .reverse)]) private var labs: [LabResult]
    @Query(sort: [SortDescriptor(\MedicalDocument.capturedAt, order: .reverse)]) private var documents: [MedicalDocument]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                identityHeader
                snapshotGrid
                conditionsCard
                allergiesCard
                currentMedsCard
                recentLabsCard
                whatIKnowCard
                shareCard
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.Palette.paper)
    }

    // MARK: Identity

    private var identityHeader: some View {
        HStack(spacing: Theme.Space.md) {
            AvatarCircle(initials: profile?.initials ?? "?", size: 66)
            VStack(alignment: .leading, spacing: 6) {
                Text(profile?.name ?? "—")
                    .font(Theme.Font.display(28, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(profile?.age ?? 0) · \(profile?.sex ?? "") · \(profile?.bloodType ?? "") · \(heightString)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
                HStack(spacing: 6) {
                    PillTag(text: profile?.location ?? "—")
                    PillTag(text: "on-device", fill: Theme.Palette.peachTint, border: Theme.Palette.coral.opacity(0.3), foreground: Theme.Palette.coralDeep, icon: "lock.fill")
                }
            }
            Spacer()
        }
    }

    private var heightString: String {
        guard let inches = profile?.heightInches else { return "—" }
        return "\(inches / 12)'\(inches % 12)\""
    }

    // MARK: Snapshot grid

    private var snapshotGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Your snapshot".uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.inkMuted)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                snapshotTile(label: "BP · Latest", value: "128/82", detail: "Apr 17", accent: Theme.Palette.ink, tint: Theme.Palette.paperSoft)
                snapshotTile(label: "A1C", value: "6.2%", detail: "↑ from 5.9", accent: Theme.Palette.coralDeep, tint: Theme.Palette.peachTint)
                snapshotTile(label: "Iron", value: "52 µg/dL", detail: "↓ Low", accent: Theme.Palette.coralDeep, tint: Theme.Palette.peachTint)
                snapshotTile(label: "HR Rest", value: "68 bpm", detail: "7-day avg", accent: Theme.Palette.ink, tint: Theme.Palette.paperSoft)
                snapshotTile(label: "Sleep", value: "7h 4m", detail: "7-day avg", accent: Theme.Palette.ink, tint: Theme.Palette.paperSoft)
                snapshotTile(label: "Weight", value: "141 lb", detail: "↓ 2 lb / mo", accent: Theme.Palette.sageDeep, tint: Theme.Palette.mint)
            }
        }
    }

    private func snapshotTile(label: String, value: String, detail: String, accent: Color, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Font.body(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Palette.inkMuted)
            Text(value)
                .font(Theme.Font.display(20, weight: .bold))
                .foregroundStyle(accent)
            Text(detail)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkMuted)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Conditions

    private var conditionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conditions".uppercased()).eyebrowStyle()
            FlowLayout(spacing: 6) {
                ForEach(profile?.conditions ?? [], id: \.self) { tag in
                    PillTag(text: tag)
                }
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    // MARK: Allergies (highlighted)

    private var allergiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flag.fill").font(.system(size: 11)).foregroundStyle(Theme.Palette.coralDeep)
                Text("Allergies").eyebrowStyle().foregroundStyle(Theme.Palette.coralDeep)
            }
            FlowLayout(spacing: 6) {
                ForEach(profile?.allergies ?? [], id: \.self) { tag in
                    PillTag(text: tag, fill: Theme.Palette.card, border: Theme.Palette.coral.opacity(0.5), foreground: Theme.Palette.coralDeep)
                }
            }
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

    // MARK: Current meds

    private var currentMedsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current meds".uppercased()).eyebrowStyle()
                Spacer()
                Text("\(medications.count)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            VStack(spacing: 0) {
                ForEach(Array(medications.enumerated()), id: \.element.persistentModelID) { idx, med in
                    HStack {
                        Text(med.name)
                            .font(Theme.Font.body(15, weight: .medium))
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Text(med.doseText + " · " + med.schedule.shortLabel)
                            .font(Theme.Font.body(13))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    .padding(.vertical, 10)
                    if idx < medications.count - 1 {
                        DashedHairline()
                    }
                }
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    // MARK: Recent labs

    private var recentLabsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent labs".uppercased()).eyebrowStyle()
                Spacer()
                Text("See all")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
            }
            VStack(spacing: 0) {
                ForEach(Array(labs.prefix(4).enumerated()), id: \.element.persistentModelID) { idx, lab in
                    HStack {
                        Text(lab.metric)
                            .font(Theme.Font.body(15, weight: .medium))
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Text("\(lab.valueText) · \(lab.capturedAt.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(Theme.Font.body(13))
                            .foregroundStyle(labColor(lab.status))
                    }
                    .padding(.vertical, 10)
                    if idx < min(labs.count, 4) - 1 {
                        DashedHairline()
                    }
                }
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private func labColor(_ status: LabStatus) -> Color {
        switch status {
        case .normal: Theme.Palette.inkSoft
        case .low, .high: Theme.Palette.coralDeep
        }
    }

    // MARK: What I know about you

    private var whatIKnowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What I know about you".uppercased()).eyebrowStyle()
            VStack(alignment: .leading, spacing: 6) {
                bullet("\(profile?.conditions.count ?? 0) conditions, \(profile?.allergies.count ?? 0) allergies")
                bullet("\(medications.count) active meds")
                bullet("\(documents.count) documents (\(labs.count) labs parsed)")
                bullet("18 months of HealthKit data")
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("·").foregroundStyle(Theme.Palette.coralDeep).font(.system(size: 22, weight: .bold))
            Text(text).font(Theme.Font.bodyText).foregroundStyle(Theme.Palette.ink)
        }
    }

    // MARK: Share with doctor

    private var shareCard: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Share with doctor")
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("One-time PDF · 5 min expiry".uppercased())
                    .font(Theme.Font.body(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            Spacer()
            Button {
                Haptics.tap()
            } label: {
                HStack(spacing: 6) {
                    Text("Draft")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.Palette.coral))
            }
            .buttonStyle(.plain)
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

extension ScheduleKind {
    var shortLabel: String {
        switch self {
        case .daily: "daily"
        case .everyXHours: "interval"
        case .asNeeded: "PRN"
        }
    }
}

// MARK: - Flow layout for tag rows

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                totalHeight += rowHeight + spacing
                maxWidth = max(maxWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        maxWidth = max(maxWidth, rowWidth - spacing)
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .modelContainer(previewContainer())
}
