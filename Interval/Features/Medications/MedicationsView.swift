import SwiftUI
import SwiftData

private enum DoseStatus {
    case taken
    case dueNow
    case upcoming
}

private enum TimePeriod: Int, CaseIterable {
    case morning
    case afternoon
    case evening

    var label: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        }
    }

    var systemImage: String {
        switch self {
        case .morning: "sun.max.fill"
        case .afternoon: "sun.haze.fill"
        case .evening: "moon.fill"
        }
    }

    var accent: Color {
        switch self {
        case .morning: Theme.Palette.sunny
        case .afternoon: Theme.Palette.coralDeep
        case .evening: Theme.Palette.ink
        }
    }
}

private struct ScheduledDose: Identifiable {
    let medication: Medication
    let log: DoseLog?
    let scheduledTime: Date

    var id: String { "\(medication.persistentModelID)-\(scheduledTime.timeIntervalSince1970)" }

    var status: DoseStatus {
        if log?.isTaken == true { return .taken }
        return scheduledTime <= .now ? .dueNow : .upcoming
    }

    var period: TimePeriod {
        let hour = Calendar.current.component(.hour, from: scheduledTime)
        switch hour {
        case 5..<12:
            return TimePeriod.morning
        case 12..<17:
            return TimePeriod.afternoon
        default:
            return TimePeriod.evening
        }
    }

    var detailText: String {
        var parts = [medication.doseText]
        if let notes = medication.notes, !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " • ")
    }

    var intakeTags: [DoseIntakeTag] {
        var tags: [DoseIntakeTag] = []
        if medication.withFood {
            tags.append(DoseIntakeTag(id: "food", title: "With food", icon: "fork.knife"))
        }
        if medication.withWater {
            tags.append(DoseIntakeTag(id: "water", title: "With water", icon: "drop.fill"))
        }
        return tags
    }
}

private struct DoseIntakeTag: Identifiable {
    let id: String
    let title: String
    let icon: String
}

struct MedicationsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query private var doseLogs: [DoseLog]

    @State private var showAdd = false

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

    private var groupedDoses: [(period: TimePeriod, doses: [ScheduledDose])] {
        TimePeriod.allCases.compactMap { period in
            let doses = todaysDoses.filter { $0.period == period }
            return doses.isEmpty ? nil : (period, doses)
        }
    }

    private var takenCount: Int {
        todaysDoses.filter { $0.status == .taken }.count
    }

    private var dueNowCount: Int {
        todaysDoses.filter { $0.status == .dueNow }.count
    }

    private var totalCount: Int {
        todaysDoses.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerSection
                summaryBanner

                if groupedDoses.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedDoses, id: \.period) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(group.period)
                            VStack(spacing: 12) {
                                ForEach(group.doses) { dose in
                                    doseCard(dose)
                                }
                            }
                        }
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
    }

    private var pageBackground: some View {
        LinearGradient(
            colors: [Theme.Palette.paper, Theme.Palette.paperSoft.opacity(0.96)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(Theme.Font.body(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.sageDeep)
                    .textCase(.uppercase)

                Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                    .font(Theme.Font.display(34, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
            }

            Spacer()

            HStack(spacing: 4) {
                Text("\(takenCount)")
                    .foregroundStyle(Theme.Palette.sageDeep)
                Text("/ \(totalCount) Taken")
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .font(Theme.Font.body(15, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Theme.Palette.paperSoft)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Palette.hairline.opacity(0.7), lineWidth: 1)
            )
        }
    }

    // MARK: Summary

    private var summaryBanner: some View {
        let hasUrgentDose = dueNowCount > 0

        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: hasUrgentDose ? "exclamationmark.circle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(hasUrgentDose ? "Needs Attention" : "All Clear!")
                    .font(Theme.Font.display(24, weight: .bold))
                    .foregroundStyle(.white)

                Text(summaryBodyText(hasUrgentDose: hasUrgentDose))
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: hasUrgentDose
                            ? [Theme.Palette.coralDeep, Theme.Palette.coral]
                            : [Theme.Palette.sageDeep, Theme.Palette.sage],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: (hasUrgentDose ? Theme.Palette.coralDeep : Theme.Palette.sageDeep).opacity(0.18), radius: 16, y: 10)
    }

    private func summaryBodyText(hasUrgentDose: Bool) -> String {
        if hasUrgentDose {
            return "\(dueNowCount) medication\(dueNowCount == 1 ? "" : "s") need attention in your schedule. You can mark them now from below."
        }
        return "No interactions detected in your current medication schedule. Looking good!"
    }

    // MARK: Sections

    private func sectionHeader(_ period: TimePeriod) -> some View {
        HStack(spacing: 8) {
            Image(systemName: period.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(period.accent)

            Text(period.label)
                .font(Theme.Font.body(17, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    // MARK: Cards

    @ViewBuilder
    private func doseCard(_ dose: ScheduledDose) -> some View {
        switch dose.status {
        case .taken:
            takenCard(dose)
        case .dueNow:
            dueNowCard(dose)
        case .upcoming:
            upcomingCard(dose)
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

                Text(dose.detailText)
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkMuted)
                    .lineLimit(2)

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

                Text(dose.detailText)
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(2)

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

                Text(dose.detailText)
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(2)

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

            Text("Add a medication and Interval will group it into your daily timeline automatically.")
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

    // MARK: Atoms

    private enum IconTone {
        case taken
        case urgent
        case upcoming
    }

    private func medIcon(for medication: Medication, tone: IconTone) -> some View {
        let fill: Color = {
            switch tone {
            case .taken: Theme.Palette.paperSoft
            case .urgent: Theme.Palette.peachTint
            case .upcoming: Theme.Palette.paperSoft
            }
        }()

        let foreground: Color = {
            switch tone {
            case .taken: Theme.Palette.sageDeep
            case .urgent: Theme.Palette.coralDeep
            case .upcoming: Theme.Palette.inkMuted
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

                accessory()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 12) {
                intakeTagRow(dose.intakeTags, tone: tone)

                HStack {
                    Spacer()
                    accessory()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    @ViewBuilder
    private func dueNowHeader(_ dose: ScheduledDose) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 8) {
                    doseName(dose)
                    dueNowBadge
                }

                Spacer(minLength: 8)

                dueNowTime(dose)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    doseName(dose)
                    dueNowBadge
                }

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
            case .taken: Theme.Palette.paperSoft
            case .urgent: Theme.Palette.peachTint
            case .upcoming: Theme.Palette.paperSoft
            }
        }()

        let foreground: Color = {
            switch tone {
            case .taken: Theme.Palette.inkMuted
            case .urgent: Theme.Palette.coralDeep
            case .upcoming: Theme.Palette.inkSoft
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
        case .tablet, .capsule:
            return "pills.fill"
        case .liquid, .drops:
            return "drop.fill"
        case .injection:
            return "syringe.fill"
        case .patch:
            return "cross.case.fill"
        case .inhaler:
            return "cross.vial.fill"
        }
    }

    // MARK: Add button

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
            .background(
                Capsule()
                    .fill(Theme.Palette.sunny)
            )
            .shadow(color: Theme.Palette.sunny.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 36)
    }

    // MARK: Actions

    private func markTaken(_ dose: ScheduledDose) {
        if let log = dose.log {
            if log.isTaken {
                log.takenAt = nil
                Haptics.select()
            } else {
                log.takenAt = .now
                Haptics.success()
            }
        } else {
            let log = DoseLog(medication: dose.medication, scheduledFor: dose.scheduledTime, takenAt: .now)
            context.insert(log)
            Haptics.success()
        }

        try? context.save()
    }

    // MARK: Helpers

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

#Preview {
    NavigationStack { MedicationsView() }
        .modelContainer(previewContainer())
}
