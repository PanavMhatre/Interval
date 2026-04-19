import Foundation
@preconcurrency import Vision
import UIKit

/// Runs Vision's text recognition on one or more images and returns a single
/// newline-joined transcript suitable for passing to a language model.
enum TextRecognizer {

    static func recognize(_ images: [UIImage]) async throws -> String {
        var pages: [String] = []
        for image in images {
            if let text = try await recognize(image), !text.isEmpty {
                pages.append(text)
            }
        }
        return pages.joined(separator: "\n\n--- page break ---\n\n")
    }

    static func recognize(_ image: UIImage) async throws -> String? {
        guard let cg = image.cgImage else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = ((req.results as? [VNRecognizedTextObservation]) ?? []).sorted {
                    let yDistance = abs($0.boundingBox.midY - $1.boundingBox.midY)
                    if yDistance > 0.03 {
                        return $0.boundingBox.midY > $1.boundingBox.midY
                    }
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                let lines = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
