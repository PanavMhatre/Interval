import Foundation
import FoundationModels
import SwiftData

/// Grounds Foundation Models with the user's medical profile and wraps
/// `LanguageModelSession` with availability checks + a fallback path.
@MainActor
@Observable
final class IntervalAI {

    enum Status {
        case available
        case unavailable(String)
    }

    var status: Status = .unavailable("Checking…")
    private(set) var session: LanguageModelSession?

    private let model = SystemLanguageModel.default

    /// Builds a fresh session with instructions derived from the user's health
    /// profile. Call after the model container has data so the AI has context.
    func prepare(with context: ModelContext) {
        switch model.availability {
        case .available:
            status = .available
            let instructions = Self.buildInstructions(context: context)
            session = LanguageModelSession(instructions: instructions)
        case .unavailable(let reason):
            status = .unavailable(Self.describe(reason))
            session = nil
        }
    }

    /// Streams a response for the user's prompt. Yields snapshots of the
    /// evolving text so the UI can render it as it arrives.
    func stream(userPrompt: String) -> AsyncThrowingStream<String, Error> {
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
    }

    var isResponding: Bool { session?.isResponding ?? false }

    // MARK: - Instructions

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

        TONE: Friendly, plain language. 2–4 short sentences. No jargon unless the user uses it.
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
        """
    }

    // MARK: - Helpers

    private static var fallbackError: Error {
        NSError(domain: "IntervalAI", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Apple Intelligence isn't available on this device."
        ])
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:       "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in Settings to chat with Interval."
        case .modelNotReady:           "Interval's model is still downloading. Check back in a minute."
        @unknown default:              "Apple Intelligence isn't available right now."
        }
    }
}
