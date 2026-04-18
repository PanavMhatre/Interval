import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query(sort: [SortDescriptor(\DoseLog.scheduledFor)]) private var doseLogs: [DoseLog]
    @Query(filter: #Predicate<HealthInsight> { !$0.dismissed }, sort: [SortDescriptor(\HealthInsight.createdAt, order: .reverse)])
    private var insights: [HealthInsight]

    @State private var trendFor: TrendMetric? = nil

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                header
                todaysMedsCard
                statsRow
                featuredInsight
                sideEffectsCard
                SymptomQuickLogCard()
                timelineCard
                askBarCard
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.Palette.paper)
        .sheet(item: $trendFor) { metric in
            TrendDetailView(metric: metric)
                .presentationDetents([.large])
        }
    }

    private var sideEffectsCard: some View {
        let tips = MedicationAdvisor.tips(
            medications: medications,
            allergies: profile?.allergies ?? []
        )
        return SideEffectsCard(tips: tips)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(Theme.Font.eyebrow)
                    .tracking(1.1)
                    .foregroundStyle(Theme.Palette.inkMuted)
                Text(greeting)
                    .font(Theme.Font.display(30, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            Spacer()
            Button {
                Haptics.tap()
                router.tab = .profile
            } label: {
                AvatarCircle(initials: profile?.initials ?? "?", size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile")
        }
    }

    private var greeting: String {
        let name = profile?.name.components(separatedBy: " ").first ?? "friend"
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 5..<12: return "Good morning,\n\(name)."
        case 12..<17: return "Good afternoon,\n\(name)."
        default: return "Good evening,\n\(name)."
        }
    }

    // MARK: Today's meds card

    private var todaysMedsCard: some View {
        let total = max(medications.count, 3)
        let taken = doseLogs.filter { isToday($0.scheduledFor) && $0.isTaken }.count
        let progress = Double(taken) / Double(total)

        return Button {
            Haptics.tap()
            trendFor = .meds
        } label: {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    ProgressRing(progress: progress, size: 70, lineWidth: 7)
                    VStack(spacing: 0) {
                        Text("\(taken)/\(total)")
                            .font(Theme.Font.body(18, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Today's meds")
                            .font(Theme.Font.cardTitle)
                            .foregroundStyle(Theme.Palette.ink)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                    HStack(spacing: 6) {
                        ForEach(medications.prefix(3), id: \.persistentModelID) { med in
                            medChip(for: med)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.inkMuted)
            }
            .padding(Theme.Space.md)
            .softCard()
        }
        .buttonStyle(.plain)
    }

    private func medChip(for med: Medication) -> some View {
        let taken = doseLogs.contains { $0.medication?.persistentModelID == med.persistentModelID && isToday($0.scheduledFor) && $0.isTaken }
        let upcoming = doseLogs.contains { $0.medication?.persistentModelID == med.persistentModelID && isToday($0.scheduledFor) && !$0.isTaken }

        let fill = taken ? Theme.Palette.mint : (upcoming ? Theme.Palette.peachTint : Theme.Palette.paperSoft)
        let border = taken ? Theme.Palette.sageDeep.opacity(0.3) : Theme.Palette.coral.opacity(0.3)
        let foreground = taken ? Theme.Palette.sageDeep : Theme.Palette.coralDeep

        let label = taken ? "✓ " + med.name.prefix(5) : (upcoming ? timeShort(for: med) + " " + med.name.prefix(4) : med.name.prefix(5))
        return Text(label)
            .font(Theme.Font.body(11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(border, lineWidth: 1))
    }

    private func timeShort(for med: Medication) -> String {
        doseLogs.first { $0.medication?.persistentModelID == med.persistentModelID && isToday($0.scheduledFor) && !$0.isTaken }
            .map { log in
                let h = Calendar.current.component(.hour, from: log.scheduledFor)
                return h <= 12 ? "\(h)AM" : "\(h - 12)PM"
            } ?? ""
    }

    // MARK: Stats row

    private var statsRow: some View {
        HStack(spacing: Theme.Space.sm) {
            statTileButton(metric: .steps) {
                HealthStatTile(label: "Steps", value: "6,420", progress: 0.64, icon: "figure.walk", tint: Theme.Palette.coral)
            }
            statTileButton(metric: .sleep) {
                HealthStatTile(label: "Sleep", value: "7h 12m", progress: 0.9, icon: "moon.fill", tint: Theme.Palette.lilac)
            }
            statTileButton(metric: .water) {
                HealthStatTile(label: "Water", value: "3/8", progress: 0.375, icon: "drop.fill", tint: Theme.Palette.coral)
            }
        }
    }

    private func statTileButton<Content: View>(metric: TrendMetric, @ViewBuilder content: () -> Content) -> some View {
        Button {
            Haptics.tap()
            trendFor = metric
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }

    // MARK: Featured insight

    private var featuredInsight: some View {
        Group {
            if let first = insights.first {
                InsightCard(
                    eyebrow: first.kind.eyebrow,
                    title: first.title,
                    detail: first.detail,
                    badge: "New",
                    onPrimary: {},
                    primaryLabel: "See trend"
                )
            }
        }
    }

    // MARK: Timeline of today's scheduled meds + HealthKit summary

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(eyebrow: "Today", title: "Your day")

            VStack(spacing: 8) {
                ForEach(todaysTimeline, id: \.self) { entry in
                    HStack(spacing: 12) {
                        Text(entry.time)
                            .font(Theme.Font.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkMuted)
                            .frame(width: 44, alignment: .leading)
                        Text(entry.label)
                            .font(Theme.Font.body(14, weight: .medium))
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        chip(for: entry.status)
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Theme.Palette.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    )
                }
            }

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").foregroundStyle(Theme.Palette.coral).font(.system(size: 11))
                    Text("From Health").eyebrowStyle()
                }
                Spacer()
                Text("Steps 6,420 · Sleep 7h 12m")
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Palette.inkSoft)
                StatusChip(text: "On track", kind: .done)
            }
            .padding(Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.Palette.paperSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
        }
    }

    private struct TimelineEntry: Hashable {
        let time: String
        let label: String
        let status: TimelineStatus
    }

    private enum TimelineStatus { case done, now, later }

    private var todaysTimeline: [TimelineEntry] {
        [
            .init(time: "7:00",  label: "Lisinopril · 10mg",   status: .done),
            .init(time: "7:30",  label: "Morning walk (2.1mi)", status: .done),
            .init(time: "8:00",  label: "Iron supplement",     status: .done),
            .init(time: "12:00", label: "Water goal check-in", status: .now),
            .init(time: "18:00", label: "Metformin · 500mg",   status: .later),
            .init(time: "22:30", label: "Wind-down / sleep",   status: .later)
        ]
    }

    @ViewBuilder
    private func chip(for status: TimelineStatus) -> some View {
        switch status {
        case .done:  StatusChip(text: "Done",  kind: .done)
        case .now:   StatusChip(text: "Now",   kind: .now)
        case .later: StatusChip(text: "Later", kind: .later)
        }
    }

    // MARK: Ask bar card

    private var askBarCard: some View {
        AskBar(placeholder: "Ask about your health…") { text in
            router.pendingChatPrompt = text
            withAnimation(.smooth) { router.tab = .chat }
        }
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

#Preview {
    HomeView()
        .modelContainer(previewContainer())
        .environment(AppRouter())
}

@MainActor
func previewContainer() -> ModelContainer {
    let schema = Schema([UserProfile.self, Medication.self, DoseLog.self, MedicalDocument.self, LabResult.self, HealthInsight.self, SymptomLog.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    SampleData.seedIfNeeded(container.mainContext)
    return container
}
