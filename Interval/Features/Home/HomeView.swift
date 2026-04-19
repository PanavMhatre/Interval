import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appleHealth: AppleHealthStore
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query(sort: [SortDescriptor(\DoseLog.scheduledFor)]) private var doseLogs: [DoseLog]
    @Query(sort: [SortDescriptor(\LabResult.capturedAt, order: .reverse)]) private var labs: [LabResult]
    @Query(filter: #Predicate<HealthInsight> { !$0.dismissed }, sort: [SortDescriptor(\HealthInsight.createdAt, order: .reverse)])
    private var insights: [HealthInsight]
    @Query(sort: [SortDescriptor(\LabResult.capturedAt, order: .reverse)]) private var labResults: [LabResult]

    @State private var tappedInsightSource: ChatSource?
    @State private var selectedTrendTarget: TrendSheetTarget?

    let onProfileTap: (() -> Void)?

    init(onProfileTap: (() -> Void)? = nil) {
        self.onProfileTap = onProfileTap
    }

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                header
                todaysMedsCard
                statsRow
                featuredInsight
                timelineCard
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.Palette.paper)
        .task(id: appleHealth.isConnected) {
            await appleHealth.refreshIfNeeded()
        }
        .sheet(item: $selectedTrendTarget) { target in
            MetricTrendSheet(metric: target.metric, labs: labs)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
                onProfileTap?()
            } label: {
                AvatarCircle(
                    initials: profile?.initials ?? "?",
                    photoData: profile?.profilePhotoData,
                    size: 44
                )
            }
            .buttonStyle(.plain)
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

        return HStack(spacing: Theme.Space.md) {
            ZStack {
                ProgressRing(progress: progress, size: 70, lineWidth: 7)
                VStack(spacing: 0) {
                    Text("\(taken)/\(total)")
                        .font(Theme.Font.body(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's meds")
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.ink)
                FlowLayout(spacing: 6) {
                    ForEach(medications.prefix(3), id: \.persistentModelID) { med in
                        medChip(for: med)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLowest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.5), radius: 16, y: 8)
        .shadow(color: Theme.Shadow.warm.opacity(0.2), radius: 5, y: 2)
    }

    private func medChip(for med: Medication) -> some View {
        let taken = doseLogs.contains { $0.medication?.persistentModelID == med.persistentModelID && isToday($0.scheduledFor) && $0.isTaken }
        let upcoming = doseLogs.contains { $0.medication?.persistentModelID == med.persistentModelID && isToday($0.scheduledFor) && !$0.isTaken }

        let fill = taken ? Theme.Palette.mint : (upcoming ? Theme.Palette.peachTint : Theme.Palette.paperSoft)
        let border = taken ? Theme.Palette.sageDeep.opacity(0.3) : Theme.Palette.coral.opacity(0.3)
        let foreground = taken ? Theme.Palette.sageDeep : Theme.Palette.coralDeep

        let label = chipLabel(for: med, taken: taken, upcoming: upcoming)
        return Text(label)
            .font(Theme.Font.body(11, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .fixedSize(horizontal: true, vertical: false)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }

    private func chipLabel(for med: Medication, taken: Bool, upcoming: Bool) -> String {
        let baseName = med.name.split(separator: " ").first.map(String.init) ?? med.name
        let shortName = String(baseName.prefix(6))

        if taken {
            return "✓ \(shortName)"
        }

        if upcoming {
            let time = timeShort(for: med)
            return time.isEmpty ? shortName : "\(time) \(shortName)"
        }

        return shortName
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
            HealthStatTile(label: "Steps", value: stepsValue, progress: stepsProgress, icon: "figure.walk", tint: Theme.Palette.coral)
            HealthStatTile(label: "Sleep", value: sleepValue, progress: sleepProgress, icon: "moon.fill", tint: Theme.Palette.lilac)
            HealthStatTile(label: "Water", value: waterValue, progress: waterProgress, icon: "drop.fill", tint: Theme.Palette.coral)
        }
    }

    // MARK: Featured insight

    private var featuredInsight: some View {
        Group {
            if let first = insights.first {
                let linkedMetric = linkedMetric(for: first)
                InsightCard(
                    eyebrow: first.kind.eyebrow,
                    title: first.title,
                    detail: first.detail,
                    badge: "New",
                    onPrimary: linkedMetric == nil ? nil : {
                        if let linkedMetric {
                            Haptics.tap()
                            selectedTrendTarget = TrendSheetTarget(metric: linkedMetric)
                        }
                    },
                    primaryLabel: "See trend"
                )
            }
        }
    }

    // MARK: Insight source chips

    @ViewBuilder
    private func insightSourceChips(for insight: HealthInsight) -> some View {
        let sources = insightSources(for: insight)
        if !sources.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(sources) { source in
                    Button {
                        Haptics.tap()
                        tappedInsightSource = source
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: source.icon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(source.label)
                                .font(Theme.Font.body(11, weight: .medium))
                        }
                        .foregroundStyle(source.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(source.accent.opacity(0.10))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(source.accent.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func insightSources(for insight: HealthInsight) -> [ChatSource] {
        switch insight.kind {
        case .trend:
            // Point to the most recent lab on file
            let recentLab = labResults.first
            let labLabel = recentLab.map { "Your labs · \($0.capturedAt.formatted(.dateTime.month(.abbreviated).day()))" }
                ?? "Your labs · recent"
            return [
                ChatSource(
                    label: labLabel,
                    icon: "chart.line.uptrend.xyaxis",
                    accent: Theme.Palette.coral,
                    deepLink: .labResult(metric: recentLab?.metric ?? "")
                )
            ]
        case .reminder:
            // Point to the first active medication
            let med = medications.first
            return [
                ChatSource(
                    label: med.map { "Your meds · \($0.name)" } ?? "Your meds",
                    icon: "pills.fill",
                    accent: Theme.Palette.sageDeep,
                    deepLink: .medication(name: med?.name ?? "")
                )
            ]
        case .flag:
            // Flagged insight: lab source + AI inference note
            let flaggedLab = labResults.first(where: { $0.status != .normal }) ?? labResults.first
            let labLabel = flaggedLab.map { "Your labs · \($0.metric)" } ?? "Your labs · flagged"
            return [
                ChatSource(
                    label: labLabel,
                    icon: "flag.fill",
                    accent: Theme.Palette.error,
                    deepLink: .labResult(metric: flaggedLab?.metric ?? "")
                ),
                ChatSource(
                    label: "AI inference · verify with your doctor",
                    icon: "sparkles",
                    accent: Theme.Palette.inkMuted,
                    deepLink: .aiInference
                )
            ]
        }
    }

    @ViewBuilder
    private func insightSourceSheet(_ source: ChatSource) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                switch source.deepLink {
                case .labResult(let metric) where !metric.isEmpty:
                    if let lab = labResults.first(where: { $0.metric.localizedCaseInsensitiveContains(metric) }) ?? labResults.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lab.metric)
                                .font(Theme.Font.display(22, weight: .bold))
                                .foregroundStyle(Theme.Palette.ink)
                            Text("\(lab.valueText)  ·  \(lab.status.displayName.capitalized)")
                                .font(Theme.Font.body(16, weight: .medium))
                                .foregroundStyle(lab.status == .normal ? Theme.Palette.sageDeep : Theme.Palette.error)
                            Text("Recorded \(lab.capturedAt.formatted(.dateTime.month(.wide).day().year()))")
                                .font(Theme.Font.body(13))
                                .foregroundStyle(Theme.Palette.inkMuted)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Theme.Palette.surfaceContainerLowest)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1))
                    } else {
                        Text("No lab data on file yet.")
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                case .medication(let name) where !name.isEmpty:
                    if let med = medications.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) ?? medications.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(med.name)
                                .font(Theme.Font.display(22, weight: .bold))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(med.doseText)
                                .font(Theme.Font.body(16, weight: .medium))
                                .foregroundStyle(Theme.Palette.inkSoft)
                            Text(med.scheduleText)
                                .font(Theme.Font.body(13))
                                .foregroundStyle(Theme.Palette.inkMuted)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Theme.Palette.surfaceContainerLowest)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1))
                    } else {
                        Text("No medication data on file yet.")
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                default:
                    // AI inference or fallback
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.Palette.inkMuted)
                        Text("AI-generated insight")
                            .font(Theme.Font.display(20, weight: .bold))
                            .foregroundStyle(Theme.Palette.ink)
                        Text("This insight was generated by on-device AI based on your health profile. It's meant to surface patterns, not to diagnose or replace medical advice. Always verify with your doctor.")
                            .font(Theme.Font.body(15))
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
            .padding(Theme.Space.lg)
            .background(Theme.Palette.paper.ignoresSafeArea())
            .navigationTitle(source.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { tappedInsightSource = nil }
                        .foregroundStyle(Theme.Palette.primary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
                            .lineLimit(1)
                        Spacer()
                        chip(for: entry.status)
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.Palette.surfaceContainerLowest)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
                    )
                    .shadow(color: Theme.Shadow.ambient.opacity(0.28), radius: 8, y: 4)
                }
            }
        }
    }

    private var stepsValue: String {
        appleHealth.isConnected ? appleHealth.snapshot.stepsText : "6,420"
    }

    private var sleepValue: String {
        switch appleHealth.syncState {
        case .connected, .waitingForData:
            return appleHealth.snapshot.sleepText
        case .syncing:
            return appleHealth.snapshot.sleepHours == nil ? "Syncing" : appleHealth.snapshot.sleepText
        case .disconnected:
            return "Connect"
        case .unavailable:
            return "No data"
        }
    }

    private var waterValue: String {
        appleHealth.isConnected ? appleHealth.snapshot.waterGoalText : "3/8"
    }

    private var stepsProgress: Double {
        appleHealth.isConnected ? appleHealth.snapshot.stepsProgress : 0.64
    }

    private var sleepProgress: Double {
        appleHealth.snapshot.sleepProgress
    }

    private var waterProgress: Double {
        appleHealth.isConnected ? appleHealth.snapshot.waterProgress : 0.375
    }

    private var healthSummaryText: String {
        switch appleHealth.syncState {
        case .unavailable:
            return "Apple Health isn't available on this device."
        case .disconnected:
            return "Connect Apple Health for live steps, sleep, and hydration."
        case .syncing:
            return "Pulling in your latest Apple Health summary now."
        case .waitingForData:
            return "Apple Health is connected. Your latest samples will appear here as they sync."
        case .connected:
            return "Steps \(appleHealth.snapshot.stepsText) · Sleep \(appleHealth.snapshot.sleepText) · Water \(appleHealth.snapshot.waterGoalText)"
        }
    }

    private var healthStatusText: String {
        switch appleHealth.syncState {
        case .unavailable: "Unavailable"
        case .disconnected: "Connect"
        case .syncing: "Syncing"
        case .waitingForData: "Linked"
        case .connected: "Live"
        }
    }

    private var healthStatusKind: StatusChip.Kind {
        switch appleHealth.syncState {
        case .connected: .done
        case .waitingForData: .ask
        case .disconnected: .ask
        case .syncing: .ask
        case .unavailable: .later
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
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func linkedMetric(for insight: HealthInsight) -> String? {
        let searchable = metricToken(insight.title + " " + insight.detail)
        if let matched = labs.first(where: { searchable.contains(metricToken($0.metric)) }) {
            return matched.metric
        }

        return labs.first?.metric
    }
}

#Preview {
    HomeView()
        .modelContainer(previewContainer())
        .environmentObject(AppleHealthStore.previewConnected)
}

@MainActor
func previewContainer() -> ModelContainer {
    let schema = Schema([UserProfile.self, Medication.self, DoseLog.self, MedicalDocument.self, LabResult.self, HealthInsight.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    SampleData.seedIfNeeded(container.mainContext)
    return container
}
