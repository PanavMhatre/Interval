import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query private var doseLogs: [DoseLog]
    @Query private var profiles: [UserProfile]

    @State private var showAdd = false
    @State private var innerTab: InnerTab = .schedule

    enum InnerTab: String, CaseIterable, Identifiable {
        case schedule = "Schedule"
        case medicines = "Medicines"
        case interactions = "Interactions"
        var id: String { rawValue }
    }

    private var allergies: [String] { profiles.first?.allergies ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                SectionHeader(
                    eyebrow: "Today",
                    title: "Medications",
                    subtitle: tabSubtitle
                )

                innerTabPicker

                tabContent
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
            .animation(.smooth(duration: 0.25), value: innerTab)
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddMedicationView()
            }
            .presentationDetents([.large])
        }
    }

    private var tabSubtitle: String {
        switch innerTab {
        case .schedule:     "Your day at a glance."
        case .medicines:    "Everything you're taking — organized."
        case .interactions: "Known drug interactions and what to avoid."
        }
    }

    // MARK: Inner tab picker

    private var innerTabPicker: some View {
        HStack(spacing: 6) {
            ForEach(InnerTab.allCases) { tab in
                Button {
                    Haptics.select()
                    withAnimation(.snappy) { innerTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(Theme.Font.body(13, weight: .semibold))
                        .foregroundStyle(innerTab == tab ? .white : Theme.Palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(innerTab == tab ? Theme.Palette.ink : Color.clear))
                        .overlay(Capsule().strokeBorder(Theme.Palette.ink.opacity(innerTab == tab ? 0 : 0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch innerTab {
        case .schedule:     scheduleTab
        case .medicines:    medicinesTab
        case .interactions: interactionsTab
        }
    }

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            AdherenceScoreCard(logs: doseLogs, medications: medications)
            scheduleRibbon
            todaysUpcomingList
        }
    }

    private var medicinesTab: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            if medications.isEmpty {
                emptyMedsState
            } else {
                ForEach(medications, id: \.persistentModelID) { med in
                    medicationCard(med)
                }
            }
            addMedicationButton
        }
    }

    private var interactionsTab: some View {
        InteractionsTabContent(medications: medications, allergies: allergies)
    }

    // MARK: Today's upcoming list (schedule tab)

    private var todaysUpcomingList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Today's doses".uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.inkMuted)
            VStack(spacing: 8) {
                ForEach(todaysDoseLogs, id: \.persistentModelID) { log in
                    doseRow(log)
                }
                if todaysDoseLogs.isEmpty {
                    Text("No doses scheduled for today.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private var todaysDoseLogs: [DoseLog] {
        doseLogs
            .filter { Calendar.current.isDateInToday($0.scheduledFor) }
            .sorted { $0.scheduledFor < $1.scheduledFor }
    }

    private func doseRow(_ log: DoseLog) -> some View {
        HStack(spacing: 12) {
            Text(log.scheduledFor.formatted(.dateTime.hour().minute()))
                .font(Theme.Font.mono(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkMuted)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.medication?.name ?? "—")
                    .font(Theme.Font.body(14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                if let med = log.medication {
                    Text(med.doseText)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }
            Spacer()
            if log.isTaken {
                StatusChip(text: "Taken", kind: .done)
            } else if log.scheduledFor <= .now {
                StatusChip(text: "Now", kind: .now)
            } else {
                StatusChip(text: "Later", kind: .later)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
    }

    // MARK: Shared bits

    private var addMedicationButton: some View {
        Button {
            Haptics.tap()
            showAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Add medication")
            }
            .font(Theme.Font.body(15, weight: .semibold))
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(
                        Theme.Palette.ink.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyMedsState: some View {
        VStack(spacing: 6) {
            Image(systemName: "pills.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Palette.inkMuted)
            Text("No medications yet")
                .font(Theme.Font.body(15, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Add your first med to unlock reminders and interaction checks.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Space.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: Ribbon

    private var scheduleRibbon: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("24-hour ribbon · today".uppercased())
                    .font(Theme.Font.eyebrow)
                    .tracking(1)
                    .foregroundStyle(Theme.Palette.inkMuted)
                Spacer()
                Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }

            RibbonView(medications: medications, logs: doseLogs)
                .frame(height: 64)
        }
        .padding(Theme.Space.md)
        .softCard()
    }

    // MARK: Medication card

    private func medicationCard(_ med: Medication) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Palette.peachTint)
                        .frame(width: 40, height: 40)
                    Image(systemName: "pills.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(med.name)
                            .font(Theme.Font.body(17, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        if let brand = med.brand, !brand.isEmpty {
                            Text("· \(brand)")
                                .font(Theme.Font.body(13))
                                .foregroundStyle(Theme.Palette.inkMuted)
                        }
                    }
                    Text(med.doseText + " · " + med.form.displayName)
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    markTaken(med)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(nextLogToday(for: med)?.isTaken == true ? Theme.Palette.sageDeep : Theme.Palette.coral)
                }
                .buttonStyle(.plain)
            }

            DashedHairline()

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Palette.inkMuted)
                    Text(med.scheduleText)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer()
                if med.withFood {
                    PillTag(text: "with food", icon: "fork.knife")
                }
                if med.withWater {
                    PillTag(text: "water", icon: "drop.fill")
                }
            }
        }
        .padding(Theme.Space.md)
        .softCard()
    }

    private func nextLogToday(for med: Medication) -> DoseLog? {
        doseLogs.first { $0.medication?.persistentModelID == med.persistentModelID && Calendar.current.isDateInToday($0.scheduledFor) }
    }

    private func markTaken(_ med: Medication) {
        let log = nextLogToday(for: med)
        if let log {
            if log.isTaken {
                log.takenAt = nil
                Haptics.select()
            } else {
                log.takenAt = .now
                Haptics.success()
            }
        } else {
            let newLog = DoseLog(medication: med, scheduledFor: .now, takenAt: .now)
            context.insert(newLog)
            Haptics.success()
        }
        try? context.save()
    }
}

// MARK: - 24-hour ribbon

struct RibbonView: View {
    let medications: [Medication]
    let logs: [DoseLog]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Palette.paperSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    )
                // Tick marks at 0, 6, 12, 18, 24
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    let x = width * Double(h) / 24.0
                    VStack(spacing: 4) {
                        Text("\(h)")
                            .font(Theme.Font.mono(10, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                    .offset(x: x + 4, y: -20)
                }
                // Dose dots
                ForEach(todaysDoses(), id: \.self) { dose in
                    let x = width * (Double(dose.hour) + Double(dose.minute) / 60.0) / 24.0
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(dose.taken ? Theme.Palette.sage : Theme.Palette.peachTint)
                                .frame(width: 16, height: 16)
                            Circle()
                                .strokeBorder(dose.taken ? Theme.Palette.sageDeep : Theme.Palette.coralDeep, lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                        }
                        Text(dose.shortName)
                            .font(Theme.Font.body(9, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    .offset(x: x - 8, y: 10)
                }
            }
        }
    }

    private struct Dose: Hashable {
        let hour: Int
        let minute: Int
        let shortName: String
        let taken: Bool
    }

    private func todaysDoses() -> [Dose] {
        let cal = Calendar.current
        return logs
            .filter { cal.isDateInToday($0.scheduledFor) }
            .sorted(by: { $0.scheduledFor < $1.scheduledFor })
            .map { log in
                let comps = cal.dateComponents([.hour, .minute], from: log.scheduledFor)
                let name = log.medication?.name ?? "?"
                return Dose(
                    hour: comps.hour ?? 0,
                    minute: comps.minute ?? 0,
                    shortName: String(name.prefix(4)),
                    taken: log.isTaken
                )
            }
    }
}

#Preview {
    NavigationStack {
        MedicationsView()
    }
    .modelContainer(previewContainer())
}
