import Foundation
import SwiftData
import UIKit

@MainActor
enum SampleData {

    private struct ShowcaseDocumentPayload {
        let title: String
        let kind: DocumentKind
        let provider: String?
        let capturedAt: Date
        let summary: String
        let flagged: Bool
        let lines: [String]
    }

    /// Seeds the container the very first time the app launches so every tab
    /// has something realistic to render. Idempotent — checks if a profile
    /// already exists.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<UserProfile>())
        if !(existing?.isEmpty ?? true) {
            ensureAfternoonMedicationIfNeeded(context)
            ensureShowcaseDocumentsIfNeeded(context)
            return
        }

        let profile = UserProfile(hasCompletedOnboarding: false)
        context.insert(profile)

        let cal = Calendar.current
        let today = Date()
        func time(_ h: Int, _ m: Int = 0, dayOffset: Int = 0) -> Date {
            var comps = cal.dateComponents([.year, .month, .day], from: today)
            comps.hour = h; comps.minute = m
            let base = cal.date(from: comps) ?? today
            return cal.date(byAdding: .day, value: dayOffset, to: base) ?? base
        }

        // Medications
        let lisinopril = Medication(
            name: "Lisinopril", brand: "Zestril",
            doseAmount: 10, doseUnit: "mg", form: .tablet,
            schedule: .daily, intervalHours: 24,
            withFood: false, withWater: true,
            preferredTimes: ["7:00 AM"],
            notes: "For blood pressure"
        )
        let metformin = Medication(
            name: "Metformin", brand: nil,
            doseAmount: 500, doseUnit: "mg", form: .tablet,
            schedule: .daily, intervalHours: 24,
            withFood: true, withWater: true,
            preferredTimes: ["6:00 PM"],
            notes: "Take with dinner"
        )
        let iron = Medication(
            name: "Iron supplement", brand: "Ferrous sulfate",
            doseAmount: 65, doseUnit: "mg", form: .tablet,
            schedule: .daily, intervalHours: 24,
            withFood: false, withWater: true,
            preferredTimes: ["8:00 AM"],
            notes: "Morning — away from calcium"
        )
        [lisinopril, metformin, iron].forEach(context.insert)

        // Dose logs for today
        context.insert(DoseLog(medication: lisinopril,  scheduledFor: time(7), takenAt: time(7, 6)))
        context.insert(DoseLog(medication: iron,        scheduledFor: time(8), takenAt: time(8, 12)))
        context.insert(DoseLog(medication: metformin,   scheduledFor: time(18))) // upcoming

        // Documents + labs
        let showcase = showcaseDocumentPayloads(referenceDate: today, calendar: cal)

        let aprPanel = MedicalDocument(
            title: showcase.apr.title,
            kind: showcase.apr.kind,
            provider: showcase.apr.provider,
            capturedAt: showcase.apr.capturedAt,
            summary: showcase.apr.summary,
            flagged: showcase.apr.flagged,
            imageData: makeShowcaseDocumentImageData(showcase.apr)
        )
        let febPanel = MedicalDocument(
            title: showcase.feb.title,
            kind: showcase.feb.kind,
            provider: showcase.feb.provider,
            capturedAt: showcase.feb.capturedAt,
            summary: showcase.feb.summary,
            flagged: showcase.feb.flagged,
            imageData: makeShowcaseDocumentImageData(showcase.feb)
        )
        let physical = MedicalDocument(
            title: showcase.physical.title,
            kind: showcase.physical.kind,
            provider: showcase.physical.provider,
            capturedAt: showcase.physical.capturedAt,
            summary: showcase.physical.summary,
            flagged: showcase.physical.flagged,
            imageData: makeShowcaseDocumentImageData(showcase.physical)
        )
        let prescription = MedicalDocument(
            title: showcase.prescription.title,
            kind: showcase.prescription.kind,
            provider: showcase.prescription.provider,
            capturedAt: showcase.prescription.capturedAt,
            summary: showcase.prescription.summary,
            flagged: showcase.prescription.flagged,
            imageData: makeShowcaseDocumentImageData(showcase.prescription)
        )
        [aprPanel, febPanel, physical, prescription].forEach(context.insert)

        // Lab results
        context.insert(LabResult(document: aprPanel, metric: "A1C",  value: 6.2,  unit: "%",    referenceLow: 4.0, referenceHigh: 5.6, capturedAt: aprPanel.capturedAt, status: .high))
        context.insert(LabResult(document: aprPanel, metric: "Iron", value: 52,   unit: "µg/dL", referenceLow: 60,  referenceHigh: 170, capturedAt: aprPanel.capturedAt, status: .low))
        context.insert(LabResult(document: aprPanel, metric: "Vitamin D", value: 38, unit: "ng/mL", referenceLow: 30, referenceHigh: 100, capturedAt: aprPanel.capturedAt, status: .normal))
        context.insert(LabResult(document: febPanel, metric: "Iron", value: 46,   unit: "µg/dL", referenceLow: 60,  referenceHigh: 170, capturedAt: febPanel.capturedAt, status: .low))
        context.insert(LabResult(document: febPanel, metric: "A1C",  value: 5.9,  unit: "%",    referenceLow: 4.0, referenceHigh: 5.6, capturedAt: febPanel.capturedAt, status: .high))

        // Insights
        context.insert(HealthInsight(
            title: "Your iron is up 18% since February",
            detail: "Nice. Your last 3 labs show steady improvement.",
            kind: .trend
        ))
        context.insert(HealthInsight(
            title: "Metformin at 6:00 PM",
            detail: "Take with food. Next reminder in 2h 40m.",
            kind: .reminder
        ))
        context.insert(HealthInsight(
            title: "A1C result came back elevated",
            detail: "From the lab you scanned yesterday. Tap to review.",
            kind: .flag
        ))

        try? context.save()
    }

    private static func ensureShowcaseDocumentsIfNeeded(_ context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard let profile = profiles.first, isShowcaseProfile(profile) else { return }

        let documents = (try? context.fetch(FetchDescriptor<MedicalDocument>())) ?? []
        let showcase = showcaseDocumentPayloads(referenceDate: .now, calendar: .current)

        [
            showcase.apr,
            showcase.feb,
            showcase.physical,
            showcase.prescription
        ].forEach { payload in
            upsertShowcaseDocument(payload, existingDocuments: documents, context: context)
        }

        try? context.save()
    }

    private static func ensureAfternoonMedicationIfNeeded(_ context: ModelContext) {
        let calendar = Calendar.current

        let medications = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []

        let hasAfternoonLog = logs.contains { log in
            guard calendar.isDateInToday(log.scheduledFor) else { return false }
            let hour = calendar.component(.hour, from: log.scheduledFor)
            return (12..<17).contains(hour)
        }

        let hasAfternoonPreference = medications.contains { medication in
            medication.preferredTimes.contains { raw in
                parseHour(raw).map { (12..<17).contains($0) } ?? false
            }
        }

        guard !hasAfternoonLog && !hasAfternoonPreference else { return }

        let afternoonMedication =
            medications.first(where: { $0.name == "Amoxicillin" }) ??
            Medication(
                name: "Amoxicillin",
                brand: nil,
                doseAmount: 500,
                doseUnit: "mg",
                form: .capsule,
                schedule: .daily,
                intervalHours: 24,
                withFood: true,
                withWater: true,
                preferredTimes: ["1:00 PM"],
                notes: "Take with food"
            )

        if !medications.contains(where: { $0.persistentModelID == afternoonMedication.persistentModelID }) {
            context.insert(afternoonMedication)
        }

        let hasTodayDose = logs.contains { log in
            guard log.medication?.persistentModelID == afternoonMedication.persistentModelID else { return false }
            return calendar.isDateInToday(log.scheduledFor)
        }

        if !hasTodayDose {
            context.insert(
                DoseLog(
                    medication: afternoonMedication,
                    scheduledFor: dateForToday(hour: 13, minute: 0, calendar: calendar)
                )
            )
        }

        try? context.save()
    }

    private static func parseHour(_ raw: String) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        guard let date = formatter.date(from: raw) else { return nil }
        return Calendar.current.component(.hour, from: date)
    }

    private static func dateForToday(hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? .now
    }

    private static func isShowcaseProfile(_ profile: UserProfile) -> Bool {
        profile.name == "Sarah K." && profile.location == "Austin, TX"
    }

    private static func showcaseDocumentPayloads(
        referenceDate: Date,
        calendar: Calendar
    ) -> (
        apr: ShowcaseDocumentPayload,
        feb: ShowcaseDocumentPayload,
        physical: ShowcaseDocumentPayload,
        prescription: ShowcaseDocumentPayload
    ) {
        let aprDate = dateAt(hour: 9, minute: 0, dayOffset: -1, referenceDate: referenceDate, calendar: calendar)
        let febDate = calendar.date(byAdding: .day, value: -66, to: referenceDate) ?? referenceDate
        let physicalDate = calendar.date(byAdding: .month, value: -3, to: referenceDate) ?? referenceDate
        let prescriptionDate = calendar.date(byAdding: .day, value: -14, to: referenceDate) ?? referenceDate

        let apr = ShowcaseDocumentPayload(
            title: "Blood panel — LabCorp",
            kind: .labPanel,
            provider: "Dr. Patel",
            capturedAt: aprDate,
            summary: "Iron dipped; A1C flagged.",
            flagged: true,
            lines: [
                "Comprehensive blood panel",
                "A1C  6.2%   High",
                "Iron  52 ug/dL   Low",
                "Vitamin D  38 ng/mL   Normal"
            ]
        )

        let feb = ShowcaseDocumentPayload(
            title: "Blood panel — LabCorp",
            kind: .labPanel,
            provider: "Dr. Patel",
            capturedAt: febDate,
            summary: "Iron low; otherwise within range.",
            flagged: false,
            lines: [
                "Follow-up blood panel",
                "A1C  5.9%   High",
                "Iron  46 ug/dL   Low",
                "Vitamin D  34 ng/mL   Normal"
            ]
        )

        let physical = ShowcaseDocumentPayload(
            title: "Annual physical",
            kind: .visitNote,
            provider: "Dr. Patel",
            capturedAt: physicalDate,
            summary: "BP 128/82. Recommend continued monitoring.",
            flagged: false,
            lines: [
                "Blood pressure 128/82",
                "Prediabetes lifestyle counseling",
                "Continue home BP checks",
                "Follow-up in 3 months"
            ]
        )

        let prescription = ShowcaseDocumentPayload(
            title: "Prescription summary",
            kind: .prescription,
            provider: "Central Pharmacy",
            capturedAt: prescriptionDate,
            summary: "Active medications synced to your profile.",
            flagged: false,
            lines: [
                "Lisinopril 10 mg — daily at 7:00 AM",
                "Iron supplement 65 mg — daily at 8:00 AM",
                "Metformin 500 mg — daily at 6:00 PM",
                "Notes: take metformin with dinner"
            ]
        )

        return (apr, feb, physical, prescription)
    }

    private static func dateAt(
        hour: Int,
        minute: Int,
        dayOffset: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = hour
        components.minute = minute
        let base = calendar.date(from: components) ?? referenceDate
        return calendar.date(byAdding: .day, value: dayOffset, to: base) ?? base
    }

    private static func upsertShowcaseDocument(
        _ payload: ShowcaseDocumentPayload,
        existingDocuments: [MedicalDocument],
        context: ModelContext
    ) {
        if let existing = existingDocuments.first(where: { $0.title == payload.title && $0.summary == payload.summary }) {
            if existing.imageData == nil {
                existing.imageData = makeShowcaseDocumentImageData(payload)
            }
            existing.provider = existing.provider ?? payload.provider
            existing.flagged = payload.flagged
            if existing.kindRaw != payload.kind.rawValue {
                existing.kindRaw = payload.kind.rawValue
            }
            return
        }

        context.insert(
            MedicalDocument(
                title: payload.title,
                kind: payload.kind,
                provider: payload.provider,
                capturedAt: payload.capturedAt,
                summary: payload.summary,
                flagged: payload.flagged,
                imageData: makeShowcaseDocumentImageData(payload)
            )
        )
    }

    private static func makeShowcaseDocumentImageData(_ payload: ShowcaseDocumentPayload) -> Data? {
        let canvasSize = CGSize(width: 920, height: 1240)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)

        let image = renderer.image { _ in
            let background = UIColor(hex: "#f6efe9")
            let pageFill = UIColor.white
            let pageStroke = UIColor(hex: "#e8d6ca")
            let accent = UIColor(hex: payload.flagged ? "#a43c12" : "#904d00")
            let softAccent = UIColor(hex: payload.flagged ? "#ffdbcf" : "#ffdcc3")
            let titleColor = UIColor(hex: "#241912")
            let bodyColor = UIColor(hex: "#564334")
            let mutedColor = UIColor(hex: "#897362")

            background.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

            let pageRect = CGRect(x: 48, y: 36, width: 824, height: 1168)
            let pagePath = UIBezierPath(roundedRect: pageRect, cornerRadius: 34)
            pageFill.setFill()
            pagePath.fill()
            pageStroke.setStroke()
            pagePath.lineWidth = 2
            pagePath.stroke()

            let accentRect = CGRect(x: pageRect.minX + 28, y: pageRect.minY + 28, width: 164, height: 38)
            let accentPath = UIBezierPath(roundedRect: accentRect, cornerRadius: 19)
            softAccent.setFill()
            accentPath.fill()

            let tagAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: accent
            ]
            NSString(string: payload.kind.displayName.uppercased())
                .draw(in: accentRect.insetBy(dx: 16, dy: 8), withAttributes: tagAttributes)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .bold),
                .foregroundColor: titleColor
            ]
            NSString(string: payload.title)
                .draw(
                    in: CGRect(x: pageRect.minX + 28, y: pageRect.minY + 84, width: pageRect.width - 56, height: 60),
                    withAttributes: titleAttributes
                )

            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: mutedColor
            ]
            NSString(string: "\(payload.provider ?? payload.kind.displayName) • \(payload.capturedAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                .draw(
                    in: CGRect(x: pageRect.minX + 28, y: pageRect.minY + 148, width: pageRect.width - 56, height: 30),
                    withAttributes: subtitleAttributes
                )

            let summaryAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: titleColor
            ]
            NSString(string: payload.summary)
                .draw(
                    in: CGRect(x: pageRect.minX + 28, y: pageRect.minY + 208, width: pageRect.width - 56, height: 70),
                    withAttributes: summaryAttributes
                )

            let lineStartY = pageRect.minY + 310
            let rowHeight: CGFloat = 106

            for (index, line) in payload.lines.enumerated() {
                let rowRect = CGRect(
                    x: pageRect.minX + 28,
                    y: lineStartY + CGFloat(index) * (rowHeight + 16),
                    width: pageRect.width - 56,
                    height: rowHeight
                )

                let rowPath = UIBezierPath(roundedRect: rowRect, cornerRadius: 24)
                UIColor(hex: "#fff8f5").setFill()
                rowPath.fill()
                UIColor(hex: "#efe0d4").setStroke()
                rowPath.lineWidth = 1
                rowPath.stroke()

                let dotRect = CGRect(x: rowRect.minX + 20, y: rowRect.midY - 16, width: 32, height: 32)
                let dotPath = UIBezierPath(ovalIn: dotRect)
                (index == 1 && payload.flagged ? accent : UIColor(hex: "#904d00").withAlphaComponent(0.14)).setFill()
                dotPath.fill()

                let lineAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                    .foregroundColor: bodyColor
                ]
                NSString(string: line)
                    .draw(
                        in: CGRect(x: rowRect.minX + 68, y: rowRect.minY + 32, width: rowRect.width - 88, height: 40),
                        withAttributes: lineAttributes
                    )
            }

            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: mutedColor
            ]
            NSString(string: "Interval Records Preview")
                .draw(
                    in: CGRect(x: pageRect.minX + 28, y: pageRect.maxY - 54, width: pageRect.width - 56, height: 24),
                    withAttributes: footerAttributes
                )
        }

        return image.jpegData(compressionQuality: 0.88)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255

        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
