import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query private var doseLogs: [DoseLog]

    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                SectionHeader(
                    eyebrow: "Today",
                    title: "Medications",
                    subtitle: "Everything you're taking — organized."
                )

                scheduleRibbon

                ForEach(medications, id: \.persistentModelID) { med in
                    medicationCard(med)
                }

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
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddMedicationView()
            }
            .presentationDetents([.large])
        }
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
