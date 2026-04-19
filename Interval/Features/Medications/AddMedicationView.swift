import PhotosUI
import SwiftData
import SwiftUI
import UIKit

#if canImport(FoundationModels)
import FoundationModels

@Generable
private struct MedicationLabelExtraction {
    @Guide(description: "Brand name shown prominently on the package, such as Tylenol or Claritin. Empty string if unknown.")
    var brandName: String

    @Guide(description: "Generic medication name or active ingredient, such as Acetaminophen or Loratadine. Empty string if unknown.")
    var medicationName: String
}
#endif

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

    private struct ScannedMedicationDraft: Sendable {
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

    private struct MedicationLabelAlias: Sendable {
        let brand: String
        let brandTokens: [String]
        let genericName: String
        let genericTokens: [String]
        let allowGenericFallbackForCompoundProducts: Bool
    }

    private static let medicationLabelAliases: [MedicationLabelAlias] = [
        MedicationLabelAlias(
            brand: "Tylenol",
            brandTokens: ["tylenol"],
            genericName: "Acetaminophen",
            genericTokens: ["acetaminophen"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Claritin",
            brandTokens: ["claritin"],
            genericName: "Loratadine",
            genericTokens: ["loratadine"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Advil",
            brandTokens: ["advil"],
            genericName: "Ibuprofen",
            genericTokens: ["ibuprofen"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Motrin",
            brandTokens: ["motrin"],
            genericName: "Ibuprofen",
            genericTokens: ["ibuprofen"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Aleve",
            brandTokens: ["aleve"],
            genericName: "Naproxen sodium",
            genericTokens: ["naproxen sodium", "naproxen"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Zyrtec",
            brandTokens: ["zyrtec"],
            genericName: "Cetirizine",
            genericTokens: ["cetirizine"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Benadryl",
            brandTokens: ["benadryl"],
            genericName: "Diphenhydramine",
            genericTokens: ["diphenhydramine"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Mucinex",
            brandTokens: ["mucinex"],
            genericName: "Guaifenesin",
            genericTokens: ["guaifenesin"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Pepcid",
            brandTokens: ["pepcid"],
            genericName: "Famotidine",
            genericTokens: ["famotidine"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Prilosec",
            brandTokens: ["prilosec"],
            genericName: "Omeprazole",
            genericTokens: ["omeprazole"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Imodium",
            brandTokens: ["imodium"],
            genericName: "Loperamide",
            genericTokens: ["loperamide"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Allegra",
            brandTokens: ["allegra"],
            genericName: "Fexofenadine",
            genericTokens: ["fexofenadine"],
            allowGenericFallbackForCompoundProducts: false
        ),
        MedicationLabelAlias(
            brand: "Bayer",
            brandTokens: ["bayer"],
            genericName: "Aspirin",
            genericTokens: ["aspirin"],
            allowGenericFallbackForCompoundProducts: false
        )
    ]

    private static let blockedMedicationNamePrefixes = [
        "drug facts",
        "active ingredient",
        "active ingredients",
        "inactive ingredient",
        "inactive ingredients",
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

    private static let blockedMedicationNameFragments = [
        "24hr",
        "12hr",
        "8hr",
        "allergyrelief",
        "painreliever",
        "feverreducer",
        "nondrowsy",
        "extrastrength",
        "maximumstrength",
        "drugfacts",
        "daytime",
        "nighttime",
        "multisymptom",
        "coldflu",
        "sleepaid",
        "indooroutdoorallergies",
        "relief",
        "antihistamine"
    ]

    private static let compoundProductMarkers = [
        "claritin-d",
        "claritin d",
        "children's",
        " pm ",
        " p.m.",
        " daytime",
        " nighttime",
        " cold",
        " flu",
        " cough",
        " sinus",
        " congestion",
        " severe",
        " multisymptom",
        " multi symptom",
        " multi-symptom"
    ]

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
                let cleanedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !cleanedText.isEmpty else {
                    await MainActor.run {
                        isScanning = false
                        scanStatusMessage = "I couldn't find medication text in that scan. Try again with the label centered."
                        Haptics.error()
                    }
                    return
                }

                let draft = await parseScannedMedication(from: cleanedText)

                await MainActor.run {
                    applyScannedMedicationDraft(draft)
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

    private func applyScannedMedicationDraft(_ draft: ScannedMedicationDraft) {
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

    private func parseScannedMedication(from text: String) async -> ScannedMedicationDraft {
        let heuristicDraft = heuristicMedicationDraft(from: text)

        guard shouldUseFoundationModelAssistance(for: heuristicDraft) else {
            return heuristicDraft
        }

#if canImport(FoundationModels)
        return await foundationModelMedicationDraft(from: text, fallback: heuristicDraft) ?? heuristicDraft
#else
        return heuristicDraft
#endif
    }

    private func heuristicMedicationDraft(from text: String) -> ScannedMedicationDraft {
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

        let brandCandidate = brandCandidate(from: lines)
        let genericCandidate = activeIngredientCandidate(from: lines, preferredBrand: brandCandidate)
            ?? knownGenericNameCandidate(from: lines, preferredBrand: brandCandidate)
            ?? genericNameFallback(for: brandCandidate, in: normalizedText)
        let nameCandidate = genericCandidate
            ?? medicationNameCandidate(from: lines, excludingBrand: brandCandidate)
            ?? brandCandidate
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
            brand: brandCandidate,
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

    private func shouldUseFoundationModelAssistance(for draft: ScannedMedicationDraft) -> Bool {
        guard let name = draft.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return true
        }

        if nameLooksLikeMarketingCopy(name) {
            return true
        }

        guard let brand = draft.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty else {
            return true
        }

        return normalizedScanToken(name) == normalizedScanToken(brand)
    }

#if canImport(FoundationModels)
    private func foundationModelMedicationDraft(
        from text: String,
        fallback: ScannedMedicationDraft
    ) async -> ScannedMedicationDraft? {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable:
            return nil
        }

        let session = LanguageModelSession(instructions: """
            You extract medication label details from OCR text.
            The OCR may be noisy and slightly out of order.
            Identify the prominent brand name when it is clear, such as Tylenol or Claritin.
            Identify the generic medication or active ingredient when it is clear, such as Acetaminophen or Loratadine.
            Prefer the active ingredient for medicationName.
            Never use symptom text, section headers, strengths, dosage forms, or marketing copy as medicationName.
            Return empty strings instead of guessing.
            """)

        do {
            let response = try await session.respond(
                to: "OCR TEXT:\n\(text)",
                generating: MedicationLabelExtraction.self
            )

            let resolvedBrand = resolvedBrandName(from: response.content.brandName) ?? fallback.brand
            let resolvedName = resolvedMedicationName(
                from: response.content.medicationName,
                fallback: fallback.name,
                brand: resolvedBrand
            )

            guard resolvedBrand != fallback.brand || resolvedName != fallback.name else {
                return nil
            }

            return ScannedMedicationDraft(
                name: resolvedName,
                brand: resolvedBrand,
                doseAmount: fallback.doseAmount,
                doseUnit: fallback.doseUnit,
                form: fallback.form,
                schedule: fallback.schedule,
                intervalHours: fallback.intervalHours,
                maxPerDay: fallback.maxPerDay,
                withFood: fallback.withFood,
                withWater: fallback.withWater,
                message: fallback.message
            )
        } catch {
            return nil
        }
    }
#endif

    private func looksLikeNyQuil(in text: String) -> Bool {
        if text.contains("nyquil") || text.contains("ny quil") {
            return true
        }

        return text.contains("vicks")
            && (text.contains("nighttime") || text.contains("night time"))
            && (text.contains("cold") || text.contains("flu") || text.contains("cough"))
    }

    private func brandCandidate(from lines: [String]) -> String? {
        var bestMatch: (brand: String, score: Int)?

        for (index, line) in lines.prefix(12).enumerated() {
            let lowercasedLine = line.lowercased()
            if lowercasedLine.contains("compare to") {
                continue
            }

            let normalizedLine = normalizedScanToken(line)

            for alias in Self.medicationLabelAliases {
                for token in alias.brandTokens {
                    let normalizedToken = normalizedScanToken(token)
                    guard !normalizedToken.isEmpty else { continue }

                    let score: Int
                    if normalizedLine == normalizedToken {
                        score = 170 - (index * 10)
                    } else if normalizedLine.hasPrefix(normalizedToken) {
                        score = 150 - (index * 10)
                    } else if normalizedLine.contains(normalizedToken) {
                        score = 130 - (index * 10)
                    } else {
                        score = 0
                    }

                    guard score > 0 else { continue }

                    if score > (bestMatch?.score ?? 0) {
                        bestMatch = (alias.brand, score)
                    }
                }
            }
        }

        return bestMatch?.brand
    }

    private func activeIngredientCandidate(from lines: [String], preferredBrand: String?) -> String? {
        for (index, line) in lines.prefix(16).enumerated() {
            let lowercasedLine = line.lowercased()
            guard lowercasedLine.contains("active ingredient") || lowercasedLine.contains("drug facts") else {
                continue
            }

            let endIndex = min(index + 3, lines.count)
            for nearbyLine in lines[index..<endIndex] {
                if let matchedGeneric = knownGenericName(in: nearbyLine, preferredBrand: preferredBrand) {
                    return matchedGeneric
                }

                if let extracted = extractedMedicationNameFromStrengthLine(nearbyLine),
                   isAcceptableMedicationName(extracted, excludingBrand: preferredBrand) {
                    return extracted
                }

                let candidate = sanitizedMedicationCandidate(nearbyLine)
                if isAcceptableMedicationName(candidate, excludingBrand: preferredBrand) {
                    return candidate
                }
            }
        }

        return nil
    }

    private func knownGenericNameCandidate(from lines: [String], preferredBrand: String?) -> String? {
        var bestMatch: (name: String, score: Int)?

        for (index, line) in lines.prefix(16).enumerated() {
            guard let matchedGeneric = knownGenericName(in: line, preferredBrand: preferredBrand) else {
                continue
            }

            var score = 120 - (index * 6)
            if line.lowercased().contains("active ingredient") {
                score += 30
            }
            if containsDose(in: line) {
                score += 10
            }

            if score > (bestMatch?.score ?? 0) {
                bestMatch = (matchedGeneric, score)
            }
        }

        return bestMatch?.name
    }

    private func genericNameFallback(for brand: String?, in text: String) -> String? {
        guard
            let brand,
            let alias = Self.medicationLabelAliases.first(where: { $0.brand == brand })
        else {
            return nil
        }

        if !alias.allowGenericFallbackForCompoundProducts,
           Self.compoundProductMarkers.contains(where: { text.contains($0) }) {
            return nil
        }

        return alias.genericName
    }

    private func medicationNameCandidate(from lines: [String], excludingBrand brand: String?) -> String? {
        for line in lines.prefix(10) {
            let lowercasedLine = line.lowercased()
            if Self.blockedMedicationNamePrefixes.contains(where: { lowercasedLine.hasPrefix($0) }) {
                continue
            }

            if let extracted = extractedMedicationNameFromStrengthLine(line),
               isAcceptableMedicationName(extracted, excludingBrand: brand) {
                return extracted
            }

            let candidate = sanitizedMedicationCandidate(line)
            if isAcceptableMedicationName(candidate, excludingBrand: brand) {
                return candidate
            }
        }

        return nil
    }

    private func knownGenericName(in line: String, preferredBrand: String?) -> String? {
        let normalizedLine = normalizedScanToken(line)
        let prioritizedAliases = prioritizedMedicationAliases(preferredBrand: preferredBrand)

        for alias in prioritizedAliases {
            for token in alias.genericTokens {
                let normalizedToken = normalizedScanToken(token)
                guard !normalizedToken.isEmpty else { continue }
                if normalizedLine.contains(normalizedToken) {
                    return alias.genericName
                }
            }
        }

        return nil
    }

    private func prioritizedMedicationAliases(preferredBrand: String?) -> [MedicationLabelAlias] {
        guard let preferredBrand else { return Self.medicationLabelAliases }

        return Self.medicationLabelAliases.sorted { left, right in
            if left.brand == preferredBrand { return true }
            if right.brand == preferredBrand { return false }
            return left.brand < right.brand
        }
    }

    private func extractedMedicationNameFromStrengthLine(_ line: String) -> String? {
        let patterns = [
            "(?i)(?:active ingredients?(?:\\s*\\([^\\)]*\\))?[:\\-\\s]*)?([A-Za-z][A-Za-z\\-]+(?:\\s+[A-Za-z][A-Za-z\\-]+){0,3})(?:\\s+(?:tablets?|capsules?|caplets?|softgels?|gelcaps?|liquid ?gels?|usp))*[,:/ ]+\\d+(?:\\.\\d+)?\\s?(?:mg|mcg|g|ml|units?)\\b",
            "(?i)([A-Za-z][A-Za-z\\-]+(?:\\s+[A-Za-z][A-Za-z\\-]+){0,3})\\s+(?:tablets?|capsules?|caplets?|softgels?|gelcaps?|liquid ?gels?)\\b"
        ]

        for pattern in patterns {
            let match = firstMatch(for: pattern, in: line)
            if let candidate = match[safe: 1] {
                let sanitized = sanitizedMedicationCandidate(candidate)
                if !sanitized.isEmpty {
                    return sanitized
                }
            }
        }

        return nil
    }

    private func sanitizedMedicationCandidate(_ raw: String) -> String {
        var candidate = cleanScanLine(raw)
        guard !candidate.isEmpty else { return "" }

        candidate = replacingMatches(
            for: "(?i)^compare to active ingredient in\\s+",
            in: candidate,
            with: ""
        )
        candidate = replacingMatches(
            for: "(?i)^active ingredients?(?:\\s*\\([^\\)]*\\))?[:\\-\\s]*",
            in: candidate,
            with: ""
        )
        candidate = replacingMatches(
            for: "(?i)^drug facts[:\\-\\s]*",
            in: candidate,
            with: ""
        )
        candidate = replacingMatches(
            for: "(?i)\\b(tablets?|capsules?|caplets?|softgels?|gelcaps?|liquid ?gels?|usp|antihistamine|pain reliever(?:/fever reducer)?|fever reducer|decongestant|sleep aid|cough suppressant|expectorant|nasal decongestant|allergy relief|indoor(?:\\s*&\\s*| and )outdoor allergies|relief)\\b.*$",
            in: candidate,
            with: ""
        )
        candidate = replacingMatches(
            for: "(?i)\\b\\d+(?:\\.\\d+)?\\s?(?:mg|mcg|g|ml|units?)\\b.*$",
            in: candidate,
            with: ""
        )
        candidate = candidate.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))

        guard !nameLooksLikeMarketingCopy(candidate) else {
            return ""
        }

        return prettifiedMedicationName(candidate)
    }

    private func isAcceptableMedicationName(_ candidate: String, excludingBrand brand: String?) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalizedCandidate = normalizedScanToken(trimmed)
        guard normalizedCandidate.count >= 3 else { return false }

        if let brand, normalizedCandidate == normalizedScanToken(brand) {
            return false
        }

        if nameLooksLikeMarketingCopy(trimmed) {
            return false
        }

        let wordCount = trimmed.split(separator: " ").count
        return wordCount <= 4 && trimmed.count <= 40
    }

    private func nameLooksLikeMarketingCopy(_ name: String) -> Bool {
        let normalizedName = normalizedScanToken(name)
        guard !normalizedName.isEmpty else { return true }

        return Self.blockedMedicationNameFragments.contains(where: { normalizedName.contains($0) })
    }

    private func containsDose(in line: String) -> Bool {
        let lowercasedLine = line.lowercased()
        return lowercasedLine.contains("mg")
            || lowercasedLine.contains("mcg")
            || lowercasedLine.contains("ml")
            || lowercasedLine.contains("units")
    }

    private func resolvedBrandName(from raw: String) -> String? {
        let cleaned = cleanScanLine(raw)
        guard !cleaned.isEmpty else { return nil }

        if knownGenericName(in: cleaned, preferredBrand: nil) != nil {
            return nil
        }

        return brandCandidate(from: [cleaned]) ?? prettifiedMedicationName(cleaned)
    }

    private func resolvedMedicationName(from raw: String, fallback: String?, brand: String?) -> String? {
        let candidate = sanitizedMedicationCandidate(raw)
        if isAcceptableMedicationName(candidate, excludingBrand: brand) {
            return candidate
        }
        return fallback
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

    private func normalizedScanToken(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
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

    private func replacingMatches(for pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
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
