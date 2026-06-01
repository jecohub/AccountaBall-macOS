import Foundation
import Vision
import AppKit

class OCRService {
    func extractText(from image: CGImage) async -> String {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: "")
                    return
                }
                let strings = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
                let filtered = self.filterText(strings)
                continuation.resume(returning: self.joinedText(filtered))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            try? handler.perform([request])
        }
    }

    func filterText(_ strings: [String]) -> [String] {
        strings.filter { $0.count >= 3 }
    }

    func joinedText(_ strings: [String]) -> String {
        strings.joined(separator: "\n")
    }
}
