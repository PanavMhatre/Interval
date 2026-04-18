import Foundation
import SwiftData

@MainActor
enum SampleData {

    /// Seeds the container the very first time the app launches so every tab
    /// has something realistic to render. Idempotent — checks if a profile
    /// already exists.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<UserProfile>())
        guard existing?.isEmpty ?? true else { return }

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
        let aprPanel = MedicalDocument(
            title: "Blood panel — LabCorp",
            kind: .labPanel,
            provider: "Dr. Patel",
            capturedAt: time(9, 0, dayOffset: -1),
            summary: "Iron dipped; A1C flagged.",
            flagged: true
        )
        let febPanel = MedicalDocument(
            title: "Blood panel — LabCorp",
            kind: .labPanel,
            provider: "Dr. Patel",
            capturedAt: cal.date(byAdding: .day, value: -66, to: today) ?? today,
            summary: "Iron low; otherwise within range.",
            flagged: false
        )
        let physical = MedicalDocument(
            title: "Annual physical",
            kind: .visitNote,
            provider: "Dr. Patel",
            capturedAt: cal.date(byAdding: .month, value: -3, to: today) ?? today,
            summary: "BP 128/82. Recommend continued monitoring.",
            flagged: false
        )
        [aprPanel, febPanel, physical].forEach(context.insert)

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
}
