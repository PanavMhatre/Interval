import SwiftUI
import SwiftData

struct ProfileView: View {
    @EnvironmentObject private var appleHealth: AppleHealthStore
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query(sort: [SortDescriptor(\LabResult.capturedAt, order: .reverse)]) private var labs: [LabResult]
    @Query(sort: [SortDescriptor(\MedicalDocument.capturedAt, order: .reverse)]) private var documents: [MedicalDocument]
    @Query(sort: [SortDescriptor(\HealthInsight.createdAt, order: .reverse)]) private var insights: [HealthInsight]

    private var profile: UserProfile? { profiles.first }

    private var featuredLab: LabResult? {
        labs.first(where: { $0.status != .normal }) ?? labs.first
    }

    private var supportingLabs: [LabResult] {
        guard let featuredLab else { return Array(labs.prefix(2)) }
        return Array(
            labs
                .filter { $0.persistentModelID != featuredLab.persistentModelID }
                .prefix(2)
        )
    }

    private var quickCards: [MiniMetricCardModel] {
        var cards = supportingLabs.map(miniMetricCard)

        if cards.count < 2 {
            cards.append(
                MiniMetricCardModel(
                    id: "meds",
                    title: "Active meds",
                    value: "\(medications.count)",
                    unit: nil,
                    caption: medications.isEmpty ? "Nothing loaded" : "Scheduled today",
                    statusText: medications.isEmpty ? "Empty" : "Loaded",
                    accent: Theme.Palette.sageDeep,
                    tint: Theme.Palette.mint,
                    statusFill: Theme.Palette.mint,
                    statusForeground: Theme.Palette.sageDeep
                )
            )
        }

        if cards.count < 2 {
            cards.append(
                MiniMetricCardModel(
                    id: "docs",
                    title: "Documents",
                    value: "\(documents.count)",
                    unit: nil,
                    caption: "Scanned and indexed",
                    statusText: "Synced",
                    accent: Theme.Palette.ink,
                    tint: Theme.Palette.paperSoft,
                    statusFill: Theme.Palette.paperSoft,
                    statusForeground: Theme.Palette.inkSoft
                )
            )
        }

        return Array(cards.prefix(2))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identityPanel

                if let featuredLab {
                    featuredMetricCard(featuredLab)
                } else {
                    emptyMetricCard
                }

                supportingMetricsGrid
                tagsGrid
                medicationsPanel
                appleHealthPanel
                recordsPanel
                sharePanel
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

    private var identityPanel: some View {
        panelCard(accent: Theme.Palette.peachTint, accentSize: 170, alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Health profile")
                            .font(Theme.Font.body(12, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.Palette.inkMuted)
                            .textCase(.uppercase)

                        Text(profile?.name ?? "Your profile")
                            .font(Theme.Font.display(30, weight: .bold))
                            .foregroundStyle(Theme.Palette.ink)

                        Text(headerLine)
                            .font(Theme.Font.body(14, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }

                    Spacer()

                    AvatarCircle(initials: profile?.initials ?? "?", size: 72)
                }

                FlowLayout(spacing: 8) {
                    PillTag(text: profile?.location ?? "No location")
                    PillTag(
                        text: "\(documents.count) records",
                        fill: Theme.Palette.paperSoft,
                        border: Theme.Palette.hairline,
                        foreground: Theme.Palette.ink
                    )
                    PillTag(
                        text: "On-device",
                        fill: Theme.Palette.peachTint,
                        border: Theme.Palette.coral.opacity(0.28),
                        foreground: Theme.Palette.coralDeep,
                        icon: "lock.fill"
                    )
                }

                LazyVGrid(columns: profileSummaryColumns, spacing: 10) {
                    headerStat(title: "Blood", value: profile?.bloodType ?? "—")
                    headerStat(title: "Height", value: heightString)
                    headerStat(title: "Conditions", value: "\(profile?.conditions.count ?? 0)")
                }
            }
        }
    }

    private var headerLine: String {
        let age = profile.map { String($0.age) } ?? "—"
        let sex = profile?.sex ?? "Unknown"
        return "\(age) years old • \(sex)"
    }

    private var heightString: String {
        guard let inches = profile?.heightInches else { return "—" }
        return "\(inches / 12)'\(inches % 12)\""
    }

    private var profileSummaryColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private func headerStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Font.body(11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Palette.inkMuted)
                .textCase(.uppercase)
            Text(value)
                .font(Theme.Font.body(15, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Palette.paperSoft)
        )
    }

    // MARK: Main metric

    private func featuredMetricCard(_ lab: LabResult) -> some View {
        panelCard(
            accent: lab.status == .normal ? Theme.Palette.mint : Theme.Palette.peachTint,
            accentSize: 240,
            alignment: .topTrailing
        ) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(lab.status == .normal ? Theme.Palette.mint : Theme.Palette.peachTint)
                            .frame(width: 48, height: 48)

                        Image(systemName: metricIconName(for: lab.metric))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(metricAccent(for: lab.status))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(lab.metric)
                            .font(Theme.Font.body(19, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)

                        Text(metricContextLine(for: lab))
                            .font(Theme.Font.body(13, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }

                    Spacer()

                    metricStatusBadge(for: lab.status)
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(metricValueText(for: lab))
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.ink)

                    Text(lab.unit)
                        .font(Theme.Font.body(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .padding(.bottom, 7)
                }

                if let rangeModel = rangeBarModel(for: lab) {
                    VStack(alignment: .leading, spacing: 10) {
                        GeometryReader { proxy in
                            let width = proxy.size.width
                            let markerX = width * rangeModel.valuePosition
                            let rangeWidth = width * max(0.06, rangeModel.highPosition - rangeModel.lowPosition)

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Theme.Palette.paperSoft)
                                    .frame(height: 14)

                                Capsule()
                                    .fill((lab.status == .normal ? Theme.Palette.mint : Theme.Palette.peachTint).opacity(0.88))
                                    .frame(width: rangeWidth, height: 14)
                                    .offset(x: width * rangeModel.lowPosition)

                                Circle()
                                    .fill(metricAccent(for: lab.status))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                                    .offset(x: min(max(markerX - 9, 0), max(width - 18, 0)))
                            }
                        }
                        .frame(height: 18)

                        HStack {
                            Text(metricRangeLabel(rangeModel.low))
                            Spacer()
                            Text("Reference Range")
                            Spacer()
                            Text(metricRangeLabel(rangeModel.high))
                        }
                        .font(Theme.Font.body(12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted)
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    Label(
                        lab.capturedAt.formatted(.dateTime.month(.abbreviated).day()),
                        systemImage: "calendar"
                    )
                    .font(Theme.Font.body(12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkMuted)

                    Spacer()

                    if let insight = insights.first {
                        Text(insight.title)
                            .font(Theme.Font.body(12, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var emptyMetricCard: some View {
        panelCard(accent: Theme.Palette.mint, accentSize: 220, alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Latest reading")
                    .font(Theme.Font.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkMuted)

                Text("No labs yet")
                    .font(Theme.Font.display(26, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)

                Text("Scan a document and the profile will reshape itself around the latest result.")
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    private func metricContextLine(for lab: LabResult) -> String {
        let source = lab.document?.provider ?? lab.document?.title ?? "Latest result"
        return "\(source) • \(lab.capturedAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func metricValueText(for lab: LabResult) -> String {
        if lab.value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(lab.value))"
        }
        return String(format: "%.1f", lab.value)
    }

    private func metricRangeLabel(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func metricIconName(for metric: String) -> String {
        let key = metric.lowercased()
        if key.contains("vitamin") { return "sun.max.fill" }
        if key.contains("pressure") || key.contains("bp") { return "heart.text.square.fill" }
        if key.contains("sleep") { return "moon.zzz.fill" }
        return "drop.fill"
    }

    private func metricAccent(for status: LabStatus) -> Color {
        switch status {
        case .normal: Theme.Palette.sageDeep
        case .low, .high: Theme.Palette.coralDeep
        }
    }

    private func metricStatusBadge(for status: LabStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status == .normal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
            Text(status.displayName)
                .font(Theme.Font.body(14, weight: .semibold))
        }
        .foregroundStyle(status == .normal ? Theme.Palette.sageDeep : Theme.Palette.coralDeep)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(status == .normal ? Theme.Palette.mint : Theme.Palette.peachTint)
        )
    }

    private func rangeBarModel(for lab: LabResult) -> RangeBarModel? {
        guard let low = lab.referenceLow, let high = lab.referenceHigh, high > low else { return nil }

        let spread = high - low
        let lowerBound = low - spread * 0.35
        let upperBound = high + spread * 0.35
        let total = upperBound - lowerBound

        guard total > 0 else { return nil }

        func normalize(_ value: Double) -> CGFloat {
            CGFloat(min(max((value - lowerBound) / total, 0), 1))
        }

        return RangeBarModel(
            low: low,
            high: high,
            lowPosition: normalize(low),
            highPosition: normalize(high),
            valuePosition: normalize(lab.value)
        )
    }

    // MARK: Secondary metric cards

    private var supportingMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(quickCards) { card in
                miniMetricCardView(card)
            }
        }
    }

    private func miniMetricCard(_ lab: LabResult) -> MiniMetricCardModel {
        let positive = lab.status == .normal
        return MiniMetricCardModel(
            id: String(describing: lab.persistentModelID),
            title: lab.metric,
            value: metricValueText(for: lab),
            unit: lab.unit,
            caption: positive ? "Within range" : statusCaption(for: lab.status),
            statusText: positive ? "Healthy" : lab.status.displayName,
            accent: positive ? Theme.Palette.sageDeep : Theme.Palette.coralDeep,
            tint: positive ? Theme.Palette.mint : Theme.Palette.peachTint,
            statusFill: positive ? Theme.Palette.mint : Theme.Palette.peachTint,
            statusForeground: positive ? Theme.Palette.sageDeep : Theme.Palette.coralDeep
        )
    }

    private func miniMetricCardView(_ card: MiniMetricCardModel) -> some View {
        panelCard(accent: card.tint, accentSize: 120, alignment: .topTrailing, radius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Text(card.title)
                        .font(Theme.Font.body(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)

                    Spacer()

                    Circle()
                        .fill(card.accent.opacity(0.9))
                        .frame(width: 10, height: 10)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(card.value)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Palette.ink)

                        if let unit = card.unit, !unit.isEmpty {
                            Text(unit)
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.inkMuted)
                                .lineLimit(1)
                        }
                    }

                    Text(card.caption)
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                }

                Text(card.statusText)
                    .font(Theme.Font.body(14, weight: .semibold))
                    .foregroundStyle(card.statusForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(card.statusFill))
            }
        }
    }

    private func statusCaption(for status: LabStatus) -> String {
        switch status {
        case .normal: "Within range"
        case .low: "Below range"
        case .high: "Above range"
        }
    }

    // MARK: Profile sections

    private var tagsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tagPanel(
                title: "Conditions",
                accent: Theme.Palette.paperSoft,
                items: profile?.conditions ?? [],
                emptyText: "No conditions logged",
                foreground: Theme.Palette.ink
            )

            tagPanel(
                title: "Allergies",
                accent: Theme.Palette.peachTint,
                items: profile?.allergies ?? [],
                emptyText: "No allergies logged",
                foreground: Theme.Palette.coralDeep
            )
        }
    }

    private func tagPanel(title: String, accent: Color, items: [String], emptyText: String, foreground: Color) -> some View {
        panelCard(accent: accent, accentSize: 120, alignment: .topTrailing, radius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(Theme.Font.body(17, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)

                if items.isEmpty {
                    Text(emptyText)
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            PillTag(
                                text: item,
                                fill: Theme.Palette.card,
                                border: foreground.opacity(0.18),
                                foreground: foreground
                            )
                        }
                    }
                }
            }
        }
    }

    private var medicationsPanel: some View {
        panelCard(accent: Theme.Palette.paperSoft, accentSize: 180, alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current meds")
                            .font(Theme.Font.body(18, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Text("\(medications.count) active medications")
                            .font(Theme.Font.body(13, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }

                    Spacer()

                    Text("\(medications.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.Palette.paperSoft))
                }

                if medications.isEmpty {
                    Text("No active medications yet.")
                        .font(Theme.Font.body(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(medications.prefix(3).enumerated()), id: \.element.persistentModelID) { index, med in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(med.name)
                                        .font(Theme.Font.body(15, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.ink)
                                    Text(med.scheduleText)
                                        .font(Theme.Font.body(13, weight: .medium))
                                        .foregroundStyle(Theme.Palette.inkMuted)
                                }

                                Spacer()

                                Text(med.doseText)
                                    .font(Theme.Font.body(13, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Theme.Palette.paperSoft))
                            }

                            if index < min(medications.count, 3) - 1 {
                                DashedHairline()
                            }
                        }
                    }
                }
            }
        }
    }

    private var appleHealthPanel: some View {
        panelCard(
            accent: appleHealth.syncState == .connected ? Theme.Palette.mint : Theme.Palette.peachTint,
            accentSize: 180,
            alignment: .topTrailing
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Health")
                            .font(Theme.Font.body(18, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(appleHealthSummaryLine)
                            .font(Theme.Font.body(13, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }

                    Spacer()

                    if appleHealth.isLoading {
                        ProgressView()
                            .tint(Theme.Palette.primary)
                    } else {
                        StatusChip(text: appleHealthStatusText, kind: appleHealthStatusKind)
                    }
                }

                if appleHealth.isConnected {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        appleHealthMetricTile(label: "Steps", value: appleHealth.snapshot.stepsText)
                        appleHealthMetricTile(label: "Sleep", value: appleHealth.snapshot.sleepText)
                        appleHealthMetricTile(label: "Water", value: appleHealth.snapshot.waterGoalText)
                        appleHealthMetricTile(label: "Resting HR", value: appleHealth.snapshot.restingHeartRateText)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Read-only and on-device")
                            .font(Theme.Font.body(12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Palette.inkMuted)

                    Spacer()

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
                        HStack(spacing: 6) {
                            Text(appleHealthButtonTitle)
                            Image(systemName: appleHealth.isConnected ? "arrow.clockwise" : "heart.fill")
                        }
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.Palette.primary))
                    }
                    .buttonStyle(.plain)
                    .disabled(!appleHealth.isAvailable)
                }
            }
        }
    }

    private var recordsPanel: some View {
        panelCard(accent: Theme.Palette.mint, accentSize: 220, alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Loaded into Interval")
                        .font(Theme.Font.body(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("The app is keeping tabs on your labs, records, and trends.")
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkMuted)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    recordsSummaryTile(label: "Lab results", value: "\(labs.count)")
                    recordsSummaryTile(label: "Documents", value: "\(documents.count)")
                    recordsSummaryTile(label: "Insights", value: "\(insights.count)")
                    recordsSummaryTile(label: "Allergies", value: "\(profile?.allergies.count ?? 0)")
                }

                if let latest = documents.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Most recent record")
                            .font(Theme.Font.body(12, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.Palette.inkMuted)
                            .textCase(.uppercase)

                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(latest.flagged ? Theme.Palette.peachTint : Theme.Palette.paperSoft)
                                    .frame(width: 42, height: 42)

                                Image(systemName: latest.kind.iconName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(latest.flagged ? Theme.Palette.coralDeep : Theme.Palette.ink)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(latest.title)
                                    .font(Theme.Font.body(15, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.ink)
                                Text(latest.summary.isEmpty ? "Scanned and stored." : latest.summary)
                                    .font(Theme.Font.body(13, weight: .medium))
                                    .foregroundStyle(Theme.Palette.inkSoft)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func recordsSummaryTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Font.body(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkMuted)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Palette.paperSoft)
        )
    }

    private func appleHealthMetricTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Font.body(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkMuted)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Palette.paperSoft)
        )
    }

    private var appleHealthSummaryLine: String {
        switch appleHealth.syncState {
        case .unavailable:
            return "Apple Health isn't available on this device."
        case .disconnected:
            return "Bring in live steps, sleep, hydration, and heart rate whenever you're ready."
        case .syncing:
            return "Pulling in your latest Apple Health summary now."
        case .waitingForData:
            return "Connected. Your latest Apple Health samples will appear here as soon as they sync."
        case .connected:
            if let lastSync = appleHealth.snapshot.lastSync {
                return "Live data from Apple Health. Last synced \(lastSync.formatted(.dateTime.hour().minute()))."
            }
            return "Live data from Apple Health is showing here."
        }
    }

    private var appleHealthStatusText: String {
        switch appleHealth.syncState {
        case .unavailable: "Unavailable"
        case .disconnected: "Optional"
        case .syncing: "Syncing"
        case .waitingForData: "Linked"
        case .connected: "Live"
        }
    }

    private var appleHealthStatusKind: StatusChip.Kind {
        switch appleHealth.syncState {
        case .connected: .done
        case .waitingForData: .ask
        case .syncing: .ask
        case .disconnected: .later
        case .unavailable: .later
        }
    }

    private var appleHealthButtonTitle: String {
        appleHealth.isConnected ? "Refresh" : "Connect"
    }

    private var sharePanel: some View {
        panelCard(accent: Theme.Palette.peachTint, accentSize: 180, alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Share with doctor")
                        .font(Theme.Font.body(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Create a short-lived packet from the health data already loaded here.")
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.Palette.coral))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Card shell

    private func panelCard<Content: View>(
        accent: Color,
        accentSize: CGFloat,
        alignment: Alignment,
        radius: CGFloat = 32,
        padding: CGFloat = 22,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Palette.card)
                    .overlay(alignment: alignment) {
                        Circle()
                            .fill(accent.opacity(0.45))
                            .frame(width: accentSize, height: accentSize)
                            .offset(x: accentSize * 0.28, y: -accentSize * 0.28)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Theme.Palette.ink.opacity(0.04), radius: 18, y: 8)
    }
}

private struct MiniMetricCardModel: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String?
    let caption: String
    let statusText: String
    let accent: Color
    let tint: Color
    let statusFill: Color
    let statusForeground: Color
}

private struct RangeBarModel {
    let low: Double
    let high: Double
    let lowPosition: CGFloat
    let highPosition: CGFloat
    let valuePosition: CGFloat
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
        .environmentObject(AppleHealthStore.previewConnected)
}
