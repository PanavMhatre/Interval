import Foundation
import SwiftData

@Model
final class SymptomLog {
    var symptom: String
    var severity: Int
    var occurredAt: Date
    var notes: String?
    var relatedMedName: String?
    var createdAt: Date

    init(
        symptom: String,
        severity: Int = 3,
        occurredAt: Date = .now,
        notes: String? = nil,
        relatedMedName: String? = nil,
        createdAt: Date = .now
    ) {
        self.symptom = symptom
        self.severity = max(1, min(5, severity))
        self.occurredAt = occurredAt
        self.notes = notes
        self.relatedMedName = relatedMedName
        self.createdAt = createdAt
    }

    var severityLabel: String { SymptomLog.label(for: severity) }

    static func label(for severity: Int) -> String {
        switch severity {
        case 1: "Mild"
        case 2: "Mild+"
        case 3: "Moderate"
        case 4: "Strong"
        case 5: "Severe"
        default: "Moderate"
        }
    }
}

enum SymptomCatalog {
    struct Preset {
        let name: String
        let icon: String
    }

    static let common: [Preset] = [
        .init(name: "Cough",       icon: "lungs.fill"),
        .init(name: "Headache",    icon: "brain.head.profile"),
        .init(name: "Nausea",      icon: "face.dashed"),
        .init(name: "Fatigue",     icon: "bed.double.fill"),
        .init(name: "Dizziness",   icon: "arrow.triangle.2.circlepath"),
        .init(name: "Rash",        icon: "allergens.fill"),
        .init(name: "Sore throat", icon: "mouth.fill"),
        .init(name: "Heartburn",   icon: "flame.fill")
    ]

    static func icon(for symptom: String) -> String {
        let key = symptom.lowercased()
        return common.first { key.contains($0.name.lowercased()) }?.icon ?? "heart.text.square.fill"
    }
}
