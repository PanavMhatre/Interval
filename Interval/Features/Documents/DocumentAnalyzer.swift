import Foundation
import FoundationModels
import SwiftData

/// Structured output schema for Foundation Models — one medical document.
@Generable
struct ExtractedDocument {
    @Guide(description: "A short, human-friendly title such as 'Blood panel — LabCorp' or 'Rx: Metformin 500mg'. No quotes.")
    var title: String

    @Guide(description: "Document kind. Exactly one of: labPanel, prescription, visitNote, imaging, other.")
    var kind: String

    @Guide(description: "The provider, clinic, or lab name if stated. Empty string if unknown.")
    var provider: String

    @Guide(description: "A one-sentence plain-language summary of what's notable. No jargon, no hedging.")
    var summary: String

    @Guide(description: "Whether anything looks abnormal or worth a patient's attention.")
    var flagged: Bool

    @Guide(description: "Each measured lab value in the document. Empty list if none.", .count(0...12))
    var labs: [ExtractedLab]
}

@Generable
struct ExtractedLab {
    @Guide(description: "Name of the test, e.g. 'A1C', 'Iron', 'Vitamin D', 'LDL'")
    var metric: String
    @Guide(description: "Numeric value of the measurement")
    var value: Double
    @Guide(description: "Unit, e.g. '%', 'mg/dL', 'ng/mL', 'µg/dL'")
    var unit: String
    @Guide(description: "Status relative to the reference range. Exactly one of: normal, low, high.")
    var status: String
}

/// Turns raw OCR text into a structured `ExtractedDocument` using an
/// on-device Foundation Models session.
@MainActor
final class DocumentAnalyzer {

    enum AnalyzeError: LocalizedError {
        case modelUnavailable(String)
        case emptyText
        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let m): m
            case .emptyText: "I couldn't read any text on that page."
            }
        }
    }

    func analyze(ocrText: String) async throws -> ExtractedDocument {
        let cleaned = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw AnalyzeError.emptyText }

        let model = SystemLanguageModel.default
        switch model.availability {
        case .unavailable(let reason):
            // Heuristic fallback so the UX still works on devices without
            // Apple Intelligence.
            _ = reason
            return Self.heuristic(from: cleaned)
        case .available:
            break
        }

        let session = LanguageModelSession(instructions: """
            You extract structured medical information from OCR'd documents.
            The text may be noisy — ignore garbage characters.
            Only include lab values that are clearly measurements with a number and a unit.
            Determine status by comparing the value to any reference range present;
            if no range is given, use normal.
            Keep the summary to one sentence, plain language, no hedging disclaimers.
            Never invent values that aren't in the text.
            """)

        let prompt = """
            OCR TEXT:
            \(cleaned)
            """

        let response = try await session.respond(to: prompt, generating: ExtractedDocument.self)
        return response.content
    }

    // MARK: - Heuristic fallback

    private static func heuristic(from text: String) -> ExtractedDocument {
        let lower = text.lowercased()
        let kind: String
        if lower.contains("rx") || lower.contains("prescription") { kind = "prescription" }
        else if lower.contains("result") || lower.contains("reference") || lower.contains("mg/dl") { kind = "labPanel" }
        else if lower.contains("x-ray") || lower.contains("mri") || lower.contains("ct ") { kind = "imaging" }
        else if lower.contains("visit") || lower.contains("progress note") { kind = "visitNote" }
        else { kind = "other" }

        // Attempt to pull out simple "metric: value unit" lines
        var labs: [ExtractedLab] = []
        let pattern = #"([A-Za-z][A-Za-z0-9 \-]{1,20})[:\s]+([0-9]+\.?[0-9]*)\s*(%|mg\/dL|ng\/mL|µg\/dL|mmol\/L|bpm)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches.prefix(6) where m.numberOfRanges >= 4 {
                let metric = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let valueStr = ns.substring(with: m.range(at: 2))
                let unit = ns.substring(with: m.range(at: 3))
                if let value = Double(valueStr) {
                    labs.append(ExtractedLab(metric: metric, value: value, unit: unit, status: "normal"))
                }
            }
        }

        return ExtractedDocument(
            title: kind == "labPanel" ? "Lab panel" : "Scanned document",
            kind: kind,
            provider: "",
            summary: "Imported from scan. Apple Intelligence is off, so details weren't interpreted.",
            flagged: false,
            labs: labs
        )
    }
}

// MARK: - Persistence

@MainActor
extension DocumentAnalyzer {
    /// Persists an `ExtractedDocument` into SwiftData as a `MedicalDocument`
    /// with attached `LabResult`s. Returns the saved document.
    @discardableResult
    func persist(_ extracted: ExtractedDocument, into context: ModelContext) -> MedicalDocument {
        let kind: DocumentKind = {
            switch extracted.kind.lowercased() {
            case "labpanel":     .labPanel
            case "prescription": .prescription
            case "visitnote":    .visitNote
            case "imaging":      .imaging
            default:             .other
            }
        }()

        let doc = MedicalDocument(
            title: extracted.title.isEmpty ? "Scanned document" : extracted.title,
            kind: kind,
            provider: extracted.provider.isEmpty ? nil : extracted.provider,
            capturedAt: .now,
            summary: extracted.summary,
            flagged: extracted.flagged
        )
        context.insert(doc)

        for lab in extracted.labs {
            let status: LabStatus = {
                switch lab.status.lowercased() {
                case "low":  .low
                case "high": .high
                default:     .normal
                }
            }()
            context.insert(LabResult(
                document: doc,
                metric: lab.metric,
                value: lab.value,
                unit: lab.unit,
                capturedAt: .now,
                status: status
            ))
        }

        try? context.save()
        return doc
    }
}
