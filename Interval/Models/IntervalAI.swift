import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels

@Generable
struct DoctorEmailDraftContent {
    @Guide(description: "A concise email subject line, 3 to 8 words, plain language, no quotes.")
    var subject: String

    @Guide(description: "A ready-to-send email body in first person from the patient. Keep it concise, grounded in the provided request and summary, and avoid markdown.")
    var body: String
}
#else
struct DoctorEmailDraftContent {
    var subject: String
    var body: String
}
#endif

/// Grounds Foundation Models with the user's medical profile and wraps
/// `LanguageModelSession` with availability checks + a fallback path.
/// On Xcode versions that don't include FoundationModels (pre-Xcode 26),
/// the AI feature gracefully degrades to an unavailable state.
@MainActor
@Observable
final class IntervalAI {

    enum Status {
        case available
        case unavailable(String)
    }

    var status: Status = .unavailable("Checking…")

#if canImport(FoundationModels)
    private(set) var session: LanguageModelSession?
    private let model = SystemLanguageModel.default
#endif

    /// Builds a fresh session with instructions derived from the user's health
    /// profile. Call after the model container has data so the AI has context.
    func prepare(with context: ModelContext) {
#if canImport(FoundationModels)
        switch model.availability {
        case .available:
            status = .available
            let instructions = Self.buildInstructions(context: context)
            session = LanguageModelSession(instructions: instructions)
        case .unavailable(let reason):
            status = .unavailable(Self.describe(reason))
            session = nil
        }
#else
        status = .unavailable("Apple Intelligence requires Xcode 26 / iOS 26.")
#endif
    }

    /// Streams a response for the user's prompt. Yields snapshots of the
    /// evolving text so the UI can render it as it arrives.
    func stream(userPrompt: String) -> AsyncThrowingStream<String, Error> {
#if canImport(FoundationModels)
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self, let session = self.session else {
                    continuation.finish(throwing: Self.fallbackError)
                    return
                }
                do {
                    let stream = session.streamResponse(to: userPrompt)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
#else
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: Self.fallbackError)
        }
#endif
    }

    var isResponding: Bool {
#if canImport(FoundationModels)
        session?.isResponding ?? false
#else
        false
#endif
    }

    func generateDoctorDraft(
        request: String,
        summary: String,
        doctorName: String?,
        patientName: String?
    ) async -> DoctorEmailDraftContent {
        let cleanedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedRequest.isEmpty else {
            return Self.fallbackDoctorDraft(
                request: cleanedRequest,
                summary: cleanedSummary,
                doctorName: doctorName,
                patientName: patientName
            )
        }

#if canImport(FoundationModels)
        switch model.availability {
        case .available:
            let session = LanguageModelSession(instructions: Self.doctorDraftInstructions)
            let prompt = """
            PATIENT NAME: \(patientName ?? "The patient")
            DOCTOR NAME: \(doctorName ?? "Doctor")

            WHAT THE PATIENT WANTS TO SAY:
            \(cleanedRequest)

            HEALTH SUMMARY TO USE AS FACTUAL CONTEXT:
            \(cleanedSummary)
            """

            do {
                let response = try await session.respond(to: prompt, generating: DoctorEmailDraftContent.self)
                let subject = response.content.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = response.content.body.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !subject.isEmpty, !body.isEmpty else {
                    return Self.fallbackDoctorDraft(
                        request: cleanedRequest,
                        summary: cleanedSummary,
                        doctorName: doctorName,
                        patientName: patientName
                    )
                }

                return DoctorEmailDraftContent(subject: subject, body: body)
            } catch {
                return Self.fallbackDoctorDraft(
                    request: cleanedRequest,
                    summary: cleanedSummary,
                    doctorName: doctorName,
                    patientName: patientName
                )
            }
        case .unavailable:
            return Self.fallbackDoctorDraft(
                request: cleanedRequest,
                summary: cleanedSummary,
                doctorName: doctorName,
                patientName: patientName
            )
        }
#else
        return Self.fallbackDoctorDraft(
            request: cleanedRequest,
            summary: cleanedSummary,
            doctorName: doctorName,
            patientName: patientName
        )
#endif
    }

    // MARK: - Shared Helpers

    private static func buildInstructions(context: ModelContext) -> String {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let meds = (try? context.fetch(FetchDescriptor<Medication>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let labs = (try? context.fetch(FetchDescriptor<LabResult>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []

        let medsList = meds.isEmpty ? "None on file." :
            meds.map { "• \($0.name) \($0.doseText) — \($0.scheduleText)" }.joined(separator: "\n")
        let labsList = labs.isEmpty ? "None on file." :
            labs.prefix(8)
                .map { "• \($0.metric): \($0.valueText) (\($0.status.displayName)) — \($0.capturedAt.formatted(.dateTime.month(.abbreviated).day().year()))" }
                .joined(separator: "\n")
        let conditions = profile?.conditions.joined(separator: ", ") ?? "—"
        let allergies  = profile?.allergies.joined(separator: ", ") ?? "—"
        let name       = profile?.name ?? "the user"

        return """
        You are Interval — a warm, concise, on-device health companion for \(name).
        You are NOT a doctor. Never prescribe, diagnose, or claim certainty. \
        Always recommend consulting a medical professional for clinical decisions.

        TONE: Friendly, plain language. Default to 1 short paragraph. No jargon unless the user uses it.
        Prefer short, direct answers that lean on app-native visuals instead of long explanations.
        Avoid hedging disclaimers on every message — one gentle reminder when it's actually relevant.

        USER CONTEXT (treat as trusted background; never quote verbatim unless asked):
        Conditions: \(conditions)
        Allergies: \(allergies)
        Active medications:
        \(medsList)
        Recent labs (most recent first):
        \(labsList)

        GUIDELINES:
        • If asked about a medication interaction, cross-check against the list above and note which specific med is the concern.
        • If asked about a lab value, compare to the most recent on file and note the direction of change.
        • If a question is outside this context (e.g. unrelated general medical), answer briefly and suggest asking a doctor.
        • Never invent values. If you don't have the data, say so.
        • Use short paragraphs with natural line breaks so the UI can format the reply cleanly.
        • Prefer app-native graphic tokens over extra sentences whenever a chart, card, trend, interaction check, or scenario planner would help.
        • If a quick lab visual would help and you are referring to a real metric in the user's data, append one line exactly like [[graphic:lab:A1C]].
        • If trend context would help, append one line exactly like [[graphic:trend:A1C]].
        • If a medication card would help, append one line exactly like [[graphic:med:Metformin]].
        • If the user asks a what-if or scenario question about a medication, append one line exactly like [[graphic:simulation:Metformin]].
        • If an interaction check would help, append one line exactly like [[graphic:interaction:Ibuprofen:Lisinopril]].
        • If a small takeaway card would help, append one line exactly like [[callout:positive:short grounded takeaway]] or [[callout:caution:short grounded takeaway]].
        • Avoid markdown tables, long bullet lists, or dense blocks of text.
        • Only use those token lines when they are grounded in the user's real data.
        """
    }

#if canImport(FoundationModels)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:           "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in Settings to chat with Interval."
        case .modelNotReady:               "Interval's model is still downloading. Check back in a minute."
        @unknown default:                  "Apple Intelligence isn't available right now."
        }
    }
#endif

    private static var doctorDraftInstructions: String {
        """
        You write concise, warm emails from a patient to a clinician.
        Write in first person as the patient.
        Keep the email easy to scan and medically grounded.
        Do not invent facts, symptoms, dates, or medication details not present in the request or summary.
        Focus on the patient's ask first, then include only the most relevant context.
        Keep the subject line short.
        Keep the body to 1 to 3 short paragraphs, or one short paragraph plus a compact context list if helpful.
        Do not use markdown headings, tables, or exaggerated urgency.
        """
    }

    private static var fallbackError: Error {
        NSError(domain: "IntervalAI", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Apple Intelligence isn't available on this device."
        ])
    }

    private static func fallbackDoctorDraft(
        request: String,
        summary: String,
        doctorName: String?,
        patientName: String?
    ) -> DoctorEmailDraftContent {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = summary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let contextLines = Array(lines.prefix(4))
        let greetingName = doctorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? doctorName! : "Doctor"
        let senderName = patientName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? patientName! : "Patient"
        let greetingLine: String = {
            let lower = greetingName.lowercased()
            if lower.hasPrefix("dr.") || lower.hasPrefix("doctor ") {
                return "Hi \(greetingName),"
            }
            return "Hi Dr. \(greetingName),"
        }()

        let subjectSource = trimmedRequest.isEmpty ? "follow up question" : trimmedRequest
        let subjectWords = subjectSource
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(6)
            .map(String.init)
        let subject = subjectWords.isEmpty
            ? "Health follow-up"
            : subjectWords.joined(separator: " ").capitalized

        var bodySections: [String] = []
        bodySections.append(greetingLine)

        if trimmedRequest.isEmpty {
            bodySections.append("I wanted to follow up with a quick question about my recent health records in Interval.")
        } else {
            bodySections.append("I'm reaching out through Interval with a quick question: \(trimmedRequest)")
        }

        if !contextLines.isEmpty {
            let formattedContext = contextLines.map { "- \($0)" }.joined(separator: "\n")
            bodySections.append("A few relevant details from my record:\n\(formattedContext)")
        }

        bodySections.append("Thank you,\n\(senderName)")

        return DoctorEmailDraftContent(
            subject: subject,
            body: bodySections.joined(separator: "\n\n")
        )
    }
}
