import Foundation
import SwiftData

enum DoseForm: String, Codable, CaseIterable, Identifiable {
    case tablet, capsule, liquid, injection, patch, inhaler, drops
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case daily
    case everyXHours
    case asNeeded
    var id: String { rawValue }
}

@Model
final class Medication {
    var name: String
    var brand: String?
    var doseAmount: Double
    var doseUnit: String
    var formRaw: String
    var scheduleKindRaw: String
    var intervalHours: Int
    var maxPerDay: Int?
    var withFood: Bool
    var withWater: Bool
    var preferredTimesJSON: String
    var notes: String?
    var remindersEnabled: Bool
    var createdAt: Date
    var quantityRemaining: Int?

    @Relationship(deleteRule: .cascade, inverse: \DoseLog.medication)
    var logs: [DoseLog] = []

    init(
        name: String,
        brand: String? = nil,
        doseAmount: Double,
        doseUnit: String = "mg",
        form: DoseForm = .tablet,
        schedule: ScheduleKind = .daily,
        intervalHours: Int = 24,
        maxPerDay: Int? = nil,
        withFood: Bool = false,
        withWater: Bool = true,
        preferredTimes: [String] = [],
        notes: String? = nil,
        remindersEnabled: Bool = true,
        createdAt: Date = .now,
        quantityRemaining: Int? = nil
    ) {
        self.name = name
        self.brand = brand
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.formRaw = form.rawValue
        self.scheduleKindRaw = schedule.rawValue
        self.intervalHours = intervalHours
        self.maxPerDay = maxPerDay
        self.withFood = withFood
        self.withWater = withWater
        self.preferredTimesJSON = (try? String(data: JSONEncoder().encode(preferredTimes), encoding: .utf8)) ?? "[]"
        self.notes = notes
        self.remindersEnabled = remindersEnabled
        self.createdAt = createdAt
        self.quantityRemaining = quantityRemaining
    }

    var form: DoseForm {
        DoseForm(rawValue: formRaw) ?? .tablet
    }

    var schedule: ScheduleKind {
        ScheduleKind(rawValue: scheduleKindRaw) ?? .daily
    }

    var preferredTimes: [String] {
        guard let data = preferredTimesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var doseText: String {
        let amount = doseAmount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(doseAmount))
            : String(doseAmount)
        return "\(amount) \(doseUnit)"
    }

    var scheduleText: String {
        switch schedule {
        case .daily:
            if preferredTimes.count == 1 { return "Daily · \(preferredTimes[0])" }
            if !preferredTimes.isEmpty { return "Daily · \(preferredTimes.joined(separator: ", "))" }
            return "Daily"
        case .everyXHours:
            return "Every \(intervalHours)h" + (maxPerDay.map { " · max \($0)×" } ?? "")
        case .asNeeded:
            return "As needed" + (intervalHours > 0 ? " · every \(intervalHours)h" : "")
        }
    }
}

@Model
final class DoseLog {
    var medication: Medication?
    var scheduledFor: Date
    var takenAt: Date?

    init(medication: Medication? = nil, scheduledFor: Date, takenAt: Date? = nil) {
        self.medication = medication
        self.scheduledFor = scheduledFor
        self.takenAt = takenAt
    }

    var isTaken: Bool { takenAt != nil }
}
