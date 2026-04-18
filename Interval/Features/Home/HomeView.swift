import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appleHealth: AppleHealthStore
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query(sort: [SortDescriptor(\DoseLog.scheduledFor)]) private var doseLogs: [DoseLog]
    @Query(filter: #Predicate<HealthInsight> { !$0.dismissed }, sort: [SortDescriptor(\HealthInsight.createdAt, order: .reverse)])
    private var insights: [HealthInsight]

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
            AvatarCircle(initials: profile?.initials ?? "?", size: 44)
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

            Button {
                Haptics.tap()
                Task {
                    if appleHealth.isConnected {
                        await appleHealth.refreshIfNeeded(force: true)
                    } else {
                        await appleHealth.requestAccess()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Theme.Palette.secondaryFixed)
                                .frame(width: 24, height: 24)
                            Image(systemName: "heart.fill")
                                .foregroundStyle(Theme.Palette.coralDeep)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text("From Health")
                            .eyebrowStyle()
                    }

                    Spacer(minLength: 8)

                    Text(healthSummaryText)
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .multilineTextAlignment(.trailing)

                    if appleHealth.isLoading {
                        ProgressView()
                            .tint(Theme.Palette.primary)
                    } else {
                        StatusChip(text: healthStatusText, kind: healthStatusKind)
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.Palette.surfaceContainerLow)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Theme.Shadow.ambient.opacity(0.22), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!appleHealth.isAvailable)
        }
    }

    private var stepsValue: String {
        appleHealth.isConnected ? appleHealth.snapshot.stepsText : "6,420"
    }

    private var sleepValue: String {
        appleHealth.isConnected ? appleHealth.snapshot.sleepText : "7h 12m"
    }

    private var waterValue: String {
        appleHealth.isConnected ? appleHealth.snapshot.waterGoalText : "3/8"
    }

    private var stepsProgress: Double {
        appleHealth.isConnected ? appleHealth.snapshot.stepsProgress : 0.64
    }

    private var sleepProgress: Double {
        appleHealth.isConnected ? appleHealth.snapshot.sleepProgress : 0.9
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
