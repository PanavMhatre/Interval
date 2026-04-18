import Foundation
import SwiftData

enum DocumentKind: String, Codable, CaseIterable, Identifiable {
    case labPanel, prescription, visitNote, imaging, other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .labPanel: "Lab panel"
        case .prescription: "Prescription"
        case .visitNote: "Visit note"
        case .imaging: "Imaging"
        case .other: "Other"
        }
    }
    var iconName: String {
        switch self {
        case .labPanel: "drop.fill"
        case .prescription: "pills.fill"
        case .visitNote: "stethoscope"
        case .imaging: "xray"
        case .other: "doc.text.fill"
        }
    }
}

@Model
final class MedicalDocument {
    var title: String
    var kindRaw: String
    var provider: String?
    var capturedAt: Date
    var summary: String
    var flagged: Bool

    @Relationship(deleteRule: .cascade, inverse: \LabResult.document)
    var results: [LabResult] = []

    init(
        title: String,
        kind: DocumentKind = .labPanel,
        provider: String? = nil,
        capturedAt: Date = .now,
        summary: String = "",
        flagged: Bool = false
    ) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.provider = provider
        self.capturedAt = capturedAt
        self.summary = summary
        self.flagged = flagged
    }

    var kind: DocumentKind { DocumentKind(rawValue: kindRaw) ?? .other }
}

enum LabStatus: String, Codable {
    case normal, low, high
    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .low: "Low"
        case .high: "High"
        }
    }
}

@Model
final class LabResult {
    var document: MedicalDocument?
    var metric: String
    var value: Double
    var unit: String
    var referenceLow: Double?
    var referenceHigh: Double?
    var capturedAt: Date
    var statusRaw: String

    init(
        document: MedicalDocument? = nil,
        metric: String,
        value: Double,
        unit: String,
        referenceLow: Double? = nil,
        referenceHigh: Double? = nil,
        capturedAt: Date = .now,
        status: LabStatus = .normal
    ) {
        self.document = document
        self.metric = metric
        self.value = value
        self.unit = unit
        self.referenceLow = referenceLow
        self.referenceHigh = referenceHigh
        self.capturedAt = capturedAt
        self.statusRaw = status.rawValue
    }

    var status: LabStatus { LabStatus(rawValue: statusRaw) ?? .normal }

    var valueText: String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value)) \(unit)"
            : String(format: "%.1f %@", value, unit)
    }
}

enum InsightKind: String, Codable {
    case trend, reminder, flag
    var eyebrow: String {
        switch self {
        case .trend: "Insight"
        case .reminder: "Reminder"
        case .flag: "Flag"
        }
    }
}

@Model
final class HealthInsight {
    var title: String
    var detail: String
    var kindRaw: String
    var createdAt: Date
    var dismissed: Bool

    init(title: String, detail: String, kind: InsightKind, createdAt: Date = .now, dismissed: Bool = false) {
        self.title = title
        self.detail = detail
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.dismissed = dismissed
    }

    var kind: InsightKind { InsightKind(rawValue: kindRaw) ?? .trend }
}
