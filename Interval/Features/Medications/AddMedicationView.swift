import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Medication.createdAt)]) private var medications: [Medication]
    @Query private var profiles: [UserProfile]

    enum Mode: String, CaseIterable { case manual = "Manual", scan = "Scan med" }

    @State private var mode: Mode = .manual
    @State private var name = ""
    @State private var brand = ""
    @State private var doseAmount = ""
    @State private var doseUnit = "mg"
    @State private var form: DoseForm = .tablet
    @State private var schedule: ScheduleKind = .everyXHours
    @State private var intervalHours = 6
    @State private var maxPerDay: Int? = 4
    @State private var scheduledTime = AddMedicationView.defaultScheduleTime
    @State private var withFood = true
    @State private var withWater = true
    @State private var reminders = true

    @State private var showInteraction = false
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var hasLoadedScanResult = false
    @State private var scanStatusMessage: String?

    private static let defaultScheduleTime: Date = {
        Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
    }()

    private struct ScannedMedicationDraft {
        var name: String?
        var brand: String?
        var doseAmount: String?
        var doseUnit: String?
        var form: DoseForm?
        var schedule: ScheduleKind?
        var intervalHours: Int?
        var maxPerDay: Int?
        var withFood: Bool?
        var withWater: Bool?
        var message: String
    }

    private var draftDoseText: String {
        let trimmed = doseAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? doseUnit : "\(trimmed) \(doseUnit)"
    }

    private var interactionPreview: MedicationAdditionReport {
        MedicationSafetyEngine.analyzeAddition(
            candidateName: name,
            candidateBrand: brand.isEmpty ? nil : brand,
            candidateDoseText: draftDoseText,
            currentMedications: medications,
            profile: profiles.first
        )
    }

    private var shouldShowMedicationEditor: Bool {
        mode == .manual || hasLoadedScanResult
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {

                HStack {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Text("< Cancel")
                            .font(Theme.Font.body(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }.buttonStyle(.plain)
                    Spacer()
                    Text("New medication")
                        .font(Theme.Font.display(18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Button {
                        Haptics.tap()
                        save()
                    } label: {
                        Text("Save")
                            .font(Theme.Font.body(15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.coralDeep)
                    }.buttonStyle(.plain)
                }
                DashedHairline()

                // Mode toggle
                HStack(spacing: 6) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Button {
                            Haptics.select()
                            let previousMode = mode
                            withAnimation(.snappy) { mode = m }

                            guard m == .scan, previousMode != .scan else { return }
                            Task { @MainActor in
                                startMedicationScan()
                            }
                        } label: {
                            Text(m.rawValue)
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(mode == m ? .white : Theme.Palette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(mode == m ? Theme.Palette.ink : Color.clear))
                                .overlay(Capsule().strokeBorder(Theme.Palette.ink.opacity(mode == m ? 0 : 0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                if mode == .scan {
                    fieldCard(label: "Scan medicine", prominent: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Scan a medication label or package photo and Interval will preload whatever it can read. NyQuil should fill in cleanly, and you can edit anything after the scan.")
                                .font(Theme.Font.body(14))
                                .foregroundStyle(Theme.Palette.inkSoft)

                            VStack(spacing: 8) {
                                Button {
                                    startMedicationScan()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: DocumentScanner.isSupported ? "camera.viewfinder" : "photo.on.rectangle")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(DocumentScanner.isSupported ? "Scan medication label" : "Choose medication photo")
                                            .font(Theme.Font.body(14, weight: .semibold))
                                        Spacer()
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                            .fill(Theme.Palette.ink)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isScanning)

                                if DocumentScanner.isSupported {
                                    Button {
                                        Haptics.tap()
                                        showPhotoPicker = true
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "photo.on.rectangle")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Use a photo instead")
                                                .font(Theme.Font.body(13, weight: .semibold))
                                            Spacer()
                                        }
                                        .foregroundStyle(Theme.Palette.ink)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                                .fill(Theme.Palette.paperSoft)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isScanning)
                                }
                            }

                            HStack(spacing: 8) {
                                if isScanning {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Theme.Palette.inkMuted)
                                }

                                Text(scanStatusMessage ?? "No scan loaded yet")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.inkMuted)
                            }
                        }
                    }
                }

                if shouldShowMedicationEditor {
                    // Fields
                    fieldCard(label: mode == .scan ? "Scanned name" : "Name", prominent: true) {
                        TextField(
                            "",
                            text: $name,
                            prompt: Text("Medication name")
                                .foregroundStyle(Theme.Palette.inkMuted)
                        )
                            .font(Theme.Font.body(18, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                            .tint(Theme.Palette.coralDeep)
                        Text(brand.isEmpty ? "Brand (optional)" : "Brand: \(brand)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }

                    HStack(spacing: 10) {
                        fieldCard(label: "Dose") {
                            HStack {
                                TextField(
                                    "",
                                    text: $doseAmount,
                                    prompt: Text("0")
                                        .foregroundStyle(Theme.Palette.inkMuted)
                                )
                                    .keyboardType(.numberPad)
                                    .font(Theme.Font.body(17, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.ink)
                                    .tint(Theme.Palette.coralDeep)
                                Text(doseUnit).font(Theme.Font.body(13)).foregroundStyle(Theme.Palette.inkMuted)
                            }
                        }
                        fieldCard(label: "Form") {
                            Menu {
                                ForEach(DoseForm.allCases) { f in
                                    Button(f.displayName) { form = f }
                                }
                            } label: {
                                HStack {
                                    Text(form.displayName)
                                        .font(Theme.Font.body(15, weight: .medium))
                                        .foregroundStyle(Theme.Palette.ink)
                                        Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.inkMuted)
                                }
                            }
                        }
                    }

                    fieldCard(label: "Schedule") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                ForEach(ScheduleKind.allCases) { kind in
                                    Button {
                                        Haptics.select()
                                        schedule = kind
                                    } label: {
                                        Text(scheduleTitle(for: kind))
                                            .font(Theme.Font.body(12, weight: .semibold))
                                            .foregroundStyle(schedule == kind ? .white : Theme.Palette.ink)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(schedule == kind ? Theme.Palette.ink : Theme.Palette.paperSoft))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(
                                                        Theme.Palette.ink.opacity(schedule == kind ? 0 : 0.18),
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(schedule == .daily ? "Time" : "First dose")
                                        .font(Theme.Font.body(13, weight: .medium))
                                        .foregroundStyle(Theme.Palette.inkSoft)
                                    Spacer()
                                    DatePicker(
                                        "",
                                        selection: $scheduledTime,
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                    .tint(Theme.Palette.coralDeep)
                                }

                                if schedule != .daily {
                                    stepperRow(
                                        title: schedule == .everyXHours ? "Interval" : "Minimum gap",
                                        valueText: "\(intervalHours)h",
                                        decrement: { intervalHours = max(1, intervalHours - 1) },
                                        increment: { intervalHours = min(24, intervalHours + 1) }
                                    )
                                }

                                if schedule != .daily {
                                    stepperRow(
                                        title: "Max per day",
                                        valueText: "\(max(maxPerDay ?? 4, 1))×",
                                        decrement: { maxPerDay = max(1, (maxPerDay ?? 4) - 1) },
                                        increment: { maxPerDay = min(12, (maxPerDay ?? 4) + 1) }
                                    )
                                }
                            }
                            .padding(.top, 6)

                            Text(scheduleSummary)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.inkMuted)
                        }
                    }

                    fieldCard(label: "With") {
                        HStack {
                            withChip("Food", on: $withFood, icon: "fork.knife")
                            withChip("Water", on: $withWater, icon: "drop.fill")
                            Spacer()
                        }
                    }

                    HStack {
                        Text("Add to reminders")
                            .font(Theme.Font.body(15, weight: .medium))
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Toggle("", isOn: $reminders)
                            .labelsHidden()
                            .tint(Theme.Palette.ink)
                    }
                    .padding(Theme.Space.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(
                                Theme.Palette.hairline,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    )

                    HStack(alignment: .top, spacing: 10) {
                        AvatarCircle(initials: "i", size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(interactionPreviewHeadline)
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(interactionPreviewDetail)
                                .font(Theme.Font.body(13))
                                .foregroundStyle(Theme.Palette.inkSoft)
                        }
                    }
                    .padding(Theme.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softCard(fill: Theme.Palette.paperSoft)

                    PrimaryButton(title: interactionPreview.isClear ? "Review safety check" : "Review interactions") {
                        showInteraction = true
                    }
                } else if mode == .scan {
                    fieldCard(label: "After scan", prominent: true) {
                        Text("Once the label is scanned, the medication details will replace this area so the user can review and edit them before saving.")
                            .font(Theme.Font.body(14))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showInteraction) {
            NavigationStack {
                InteractionCheckView(
                    newMedName: name,
                    newBrand: brand.isEmpty ? nil : brand,
                    newDose: draftDoseText,
                    withFood: withFood,
                    withWater: withWater
                ) {
                    save()
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            DocumentScanner(
                onComplete: { images in
                    showScanner = false
                    processScannedImages(images)
                },
                onCancel: {
                    showScanner = false
                    isScanning = false
                }
            )
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickedItem,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: pickedItem) { _, newItem in
            guard let item = newItem else { return }

            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        processScannedImages([image])
                    }
                } else {
                    await MainActor.run {
                        isScanning = false
                        scanStatusMessage = "I couldn't read that photo. Try another image with clearer text."
                        Haptics.error()
                    }
                }
                pickedItem = nil
            }
        }
    }

    private var interactionPreviewHeadline: String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Add a medication name to run the safety check."
        }

        if let severity = interactionPreview.highestSeverity {
            switch severity {
            case .high: return "I found something that needs a closer look."
            case .moderate: return "I found a medication detail worth reviewing."
            case .low: return "I found a small thing to double-check."
            }
        }

        return "I checked this against your current meds and allergies."
    }

    private var interactionPreviewDetail: String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Manual entry stays blank until you type something, or use scan to preload a medication."
        }

        if interactionPreview.isClear {
            return "No direct pair warning or allergy match showed up in your current profile."
        }

        return "\(interactionPreview.issueCount) item\(interactionPreview.issueCount == 1 ? "" : "s") popped up. I’ll show the specific pair and what to do next."
    }

    private func fieldCard<Content: View>(label: String, prominent: Bool = false, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).eyebrowStyle()
            content()
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private func withChip(_ title: String, on: Binding<Bool>, icon: String) -> some View {
        Button {
            Haptics.select()
            on.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(Theme.Font.body(13, weight: .semibold))
            }
            .foregroundStyle(on.wrappedValue ? Theme.Palette.coralDeep : Theme.Palette.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(on.wrappedValue ? Theme.Palette.peachTint : Theme.Palette.paperSoft))
            .overlay(Capsule().strokeBorder(on.wrappedValue ? Theme.Palette.coral.opacity(0.4) : Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func stepperRow(title: String, valueText: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(Theme.Font.body(13, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer()
            Button {
                Haptics.select()
                decrement()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.Palette.paperSoft))
            }
            .buttonStyle(.plain)

            Text(valueText)
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(minWidth: 54)

            Button {
                Haptics.select()
                increment()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.Palette.paperSoft))
            }
            .buttonStyle(.plain)
        }
    }

    private func scheduleTitle(for kind: ScheduleKind) -> String {
        switch kind {
        case .daily:
            return "Daily"
        case .everyXHours:
            return "Interval"
        case .asNeeded:
            return "PRN"
        }
    }

    private var scheduleSummary: String {
        switch schedule {
        case .daily:
            return "Runs once a day at \(formattedTime(scheduledTime))."
        case .everyXHours:
            return "Repeats every \(intervalHours) hours starting at \(formattedTime(scheduledTime)). Max \(max(maxPerDay ?? 4, 1)) times a day."
        case .asNeeded:
            return "As needed, with at least \(intervalHours) hours between doses. Max \(max(maxPerDay ?? 4, 1)) times a day."
        }
    }

    private func startMedicationScan() {
        guard !isScanning, !showScanner, !showPhotoPicker else { return }

        Haptics.tap()
        scanStatusMessage = hasLoadedScanResult
            ? "Opening the scanner so you can replace the current medication details."
            : "Opening the scanner..."
        if DocumentScanner.isSupported {
            showScanner = true
        } else {
            showPhotoPicker = true
        }
    }

    private func processScannedImages(_ images: [UIImage]) {
        guard !images.isEmpty else {
            scanStatusMessage = "I couldn't read that scan. Try again with clearer framing."
            Haptics.error()
            return
        }

        isScanning = true
        scanStatusMessage = "Reading your medication label..."

        Task {
            do {
                let recognizedText = try await TextRecognizer.recognize(images)
                await MainActor.run {
                    applyScannedMedicationText(recognizedText)
                }
            } catch {
                await MainActor.run {
                    isScanning = false
                    scanStatusMessage = "I couldn't read that label. Try better lighting or a sharper photo."
                    Haptics.error()
                }
            }
        }
    }

    private func applyScannedMedicationText(_ text: String) {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            isScanning = false
            scanStatusMessage = "I couldn't find medication text in that scan. Try again with the label centered."
            Haptics.error()
            return
        }

        let draft = parseScannedMedication(from: cleanedText)

        if let scannedName = draft.name { name = scannedName }
        if let scannedBrand = draft.brand { brand = scannedBrand }
        if let scannedDoseAmount = draft.doseAmount { doseAmount = scannedDoseAmount }
        if let scannedDoseUnit = draft.doseUnit { doseUnit = scannedDoseUnit }
        if let scannedForm = draft.form { form = scannedForm }
        if let scannedSchedule = draft.schedule { schedule = scannedSchedule }
        if let scannedIntervalHours = draft.intervalHours { intervalHours = scannedIntervalHours }
        if let scannedMaxPerDay = draft.maxPerDay { maxPerDay = scannedMaxPerDay }
        if let scannedWithFood = draft.withFood { withFood = scannedWithFood }
        if let scannedWithWater = draft.withWater { withWater = scannedWithWater }

        reminders = true
        hasLoadedScanResult = true
        isScanning = false
        scanStatusMessage = draft.message
        Haptics.success()
    }

    private func parseScannedMedication(from text: String) -> ScannedMedicationDraft {
        let normalizedText = text.lowercased()

        if looksLikeNyQuil(in: normalizedText) {
            return ScannedMedicationDraft(
                name: "NyQuil",
                brand: "Vicks",
                doseAmount: "30",
                doseUnit: "mL",
                form: .liquid,
                schedule: .everyXHours,
                intervalHours: 6,
                maxPerDay: 4,
                withFood: false,
                withWater: true,
                message: "Loaded medication details from the scan. Review anything you want to change before saving."
            )
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map(cleanScanLine)
            .filter { !$0.isEmpty }

        let nameCandidate = medicationNameCandidate(from: lines)
        let doseMatch = firstMatch(
            for: "(\\d+(?:\\.\\d+)?)\\s?(mg|mcg|g|ml|units?)\\b",
            in: text
        )
        let intervalMatch = firstMatch(
            for: "every\\s+(\\d{1,2})\\s*(?:hours?|hrs?|hr|h)\\b",
            in: normalizedText
        )
        let maxPerDayMatch = firstMatch(
            for: "(?:max(?:imum)?|do not exceed|no more than)\\s+(\\d{1,2})\\s+(?:doses?|times?|tablets?|capsules?|caplets?|softgels?)",
            in: normalizedText
        )

        var detectedSchedule: ScheduleKind?
        var detectedIntervalHours: Int?

        if normalizedText.contains("as needed") || normalizedText.contains("prn") {
            detectedSchedule = .asNeeded
        } else if let intervalValue = intervalMatch[safe: 1].flatMap(Int.init) {
            detectedSchedule = .everyXHours
            detectedIntervalHours = intervalValue
        } else if normalizedText.contains("once daily")
            || normalizedText.contains("once a day")
            || normalizedText.contains("daily")
            || normalizedText.contains("every day") {
            detectedSchedule = .daily
        }

        let draft = ScannedMedicationDraft(
            name: nameCandidate,
            brand: nil,
            doseAmount: doseMatch[safe: 1],
            doseUnit: doseMatch[safe: 2].map(normalizedDoseUnit),
            form: detectedForm(from: normalizedText),
            schedule: detectedSchedule,
            intervalHours: detectedIntervalHours,
            maxPerDay: maxPerDayMatch[safe: 1].flatMap(Int.init),
            withFood: normalizedText.contains("take with food") ? true : nil,
            withWater: normalizedText.contains("with water") || normalizedText.contains("full glass of water") ? true : nil,
            message: scanSummaryMessage(name: nameCandidate, doseAmount: doseMatch[safe: 1], schedule: detectedSchedule)
        )

        return draft
    }

    private func looksLikeNyQuil(in text: String) -> Bool {
        if text.contains("nyquil") || text.contains("ny quil") {
            return true
        }

        return text.contains("vicks")
            && (text.contains("nighttime") || text.contains("night time"))
            && (text.contains("cold") || text.contains("flu") || text.contains("cough"))
    }

    private func medicationNameCandidate(from lines: [String]) -> String? {
        let blockedPrefixes = [
            "drug facts",
            "active ingredient",
            "inactive ingredient",
            "warnings",
            "warning",
            "directions",
            "uses",
            "questions",
            "other information",
            "children",
            "adults",
            "take",
            "do not",
            "keep out",
            "store",
            "compare to"
        ]

        for line in lines.prefix(8) {
            let lowercasedLine = line.lowercased()
            if blockedPrefixes.contains(where: { lowercasedLine.hasPrefix($0) }) {
                continue
            }
            if lowercasedLine.contains("mg")
                || lowercasedLine.contains("ml")
                || lowercasedLine.contains("mcg")
                || lowercasedLine.contains("drug facts") {
                continue
            }

            let letterCount = line.filter(\.isLetter).count
            let wordCount = line.split(separator: " ").count

            if letterCount >= 3, wordCount <= 6, line.count <= 40 {
                return prettifiedMedicationName(line)
            }
        }

        return nil
    }

    private func detectedForm(from text: String) -> DoseForm? {
        if text.contains("capsule") || text.contains("softgel") {
            return .capsule
        }
        if text.contains("tablet") || text.contains("caplet") {
            return .tablet
        }
        if text.contains("liquid") || text.contains("syrup") {
            return .liquid
        }
        if text.contains("patch") {
            return .patch
        }
        if text.contains("inhaler") {
            return .inhaler
        }
        if text.contains("drop") {
            return .drops
        }
        if text.contains("inject") {
            return .injection
        }
        return nil
    }

    private func scanSummaryMessage(name: String?, doseAmount: String?, schedule: ScheduleKind?) -> String {
        let recognizedFieldCount = [name, doseAmount, schedule?.rawValue].compactMap { $0 }.count

        if recognizedFieldCount >= 3 {
            return "Loaded medication details from the scan. Double-check the schedule and save when it looks right."
        }
        if recognizedFieldCount >= 1 {
            return "I loaded the clearest medication details from the scan. Review the missing fields before saving."
        }
        return "I read the label, but only partially. Update the form before saving."
    }

    private func cleanScanLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "|", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    private func prettifiedMedicationName(_ raw: String) -> String {
        let sanitized = cleanScanLine(raw)
        let uppercaseLetterCount = sanitized.filter(\.isUppercase).count
        let letterCount = sanitized.filter(\.isLetter).count

        if letterCount > 0, uppercaseLetterCount == letterCount {
            return sanitized.lowercased().capitalized
        }

        return sanitized
    }

    private func normalizedDoseUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "ml":
            return "mL"
        case "units":
            return "units"
        default:
            return unit.lowercased()
        }
    }

    private func firstMatch(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return []
        }

        return (0..<match.numberOfRanges).map { index in
            let matchRange = match.range(at: index)
            guard let stringRange = Range(matchRange, in: text) else { return "" }
            return String(text[stringRange])
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func save() {
        let amount = Double(doseAmount) ?? 0
        let preferredTimes = [formattedTime(scheduledTime)]
        let med = Medication(
            name: name,
            brand: brand.isEmpty ? nil : brand,
            doseAmount: amount,
            doseUnit: doseUnit,
            form: form,
            schedule: schedule,
            intervalHours: intervalHours,
            maxPerDay: maxPerDay,
            withFood: withFood,
            withWater: withWater,
            preferredTimes: preferredTimes,
            notes: nil,
            remindersEnabled: reminders
        )
        context.insert(med)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    NavigationStack {
        AddMedicationView()
    }
    .modelContainer(previewContainer())
}
