import Foundation
import Vision
import CoreImage

public final class BoardScanner: Sendable {
    public init() {}

    /// Run Vision OCR on a CGImage and pair silkscreen designators with nearby IC markings.
    public func scan(cgImage: CGImage, accurate: Bool) async -> [DetectedComponent] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: Self.extractComponents(from: observations))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = accurate ? 0.008 : 0.011

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    public static func extractComponents(from observations: [VNRecognizedTextObservation]) -> [DetectedComponent] {
        struct ChipHit {
            let marking: String
            let hint: String?
            let center: CGPoint
        }

        var rawDesignators: [(String, ComponentCategory, CGRect)] = []
        var chipHits: [ChipHit] = []

        for obs in observations {
            guard let top = obs.topCandidates(1).first else { continue }
            let box = obs.boundingBox
            let center = CGPoint(x: box.midX, y: box.midY)
            let tokens = top.string.split { !$0.isLetter && !$0.isNumber }.map(String.init)

            for token in tokens {
                if let (des, cat) = DesignatorCatalog.classifyDesignator(token) {
                    rawDesignators.append((des, cat, box))
                } else if let chip = DesignatorCatalog.matchChipMarking(token) {
                    chipHits.append(ChipHit(marking: chip.marking, hint: chip.hint, center: center))
                }
            }
        }

        var seen = Set<String>()
        var results: [DetectedComponent] = []

        for (des, cat, box) in rawDesignators {
            guard seen.insert(des).inserted else { continue }
            var matchedMarking: String?
            var matchedHint: String?

            if cat == .ic {
                let center = CGPoint(x: box.midX, y: box.midY)
                if let nearest = chipHits.min(by: {
                    hypot($0.center.x - center.x, $0.center.y - center.y) <
                    hypot($1.center.x - center.x, $1.center.y - center.y)
                }), hypot(nearest.center.x - center.x, nearest.center.y - center.y) < 0.25 {
                    matchedMarking = nearest.marking
                    matchedHint = nearest.hint
                }
            }

            results.append(DetectedComponent(
                designator: des,
                category: cat,
                partMarking: matchedMarking,
                partHint: matchedHint,
                boxX: box.origin.x,
                boxY: box.origin.y,
                boxW: box.size.width,
                boxH: box.size.height
            ))
        }

        // Include standalone recognized or unknown laser-etched chips if no nearby IC designator claimed them
        var unknownChipIndex = 1
        for chip in chipHits {
            if !results.contains(where: { $0.partMarking == chip.marking }) {
                let des = "IC?\(unknownChipIndex)"
                unknownChipIndex += 1
                results.append(DetectedComponent(
                    designator: des,
                    category: .ic,
                    partMarking: chip.marking,
                    partHint: chip.hint,
                    boxX: max(0, chip.center.x - 0.08),
                    boxY: max(0, chip.center.y - 0.05),
                    boxW: 0.16,
                    boxH: 0.10
                ))
            }
        }

        return results.sorted { $0.designator < $1.designator }
    }
}
