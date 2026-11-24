import Foundation
import Vision
import CoreImage
import CoreVideo

public final class BoardScanner: Sendable {
    private static let visionQueue = DispatchQueue(
        label: "com.craigmerry.circuitlens.vision",
        qos: .userInitiated
    )

    public init() {}

    /// Run Vision OCR directly on a live CVPixelBuffer off the main thread (zero CGImage copy overhead).
    public func scan(pixelBuffer: CVPixelBuffer, accurate: Bool = true) async -> [DetectedComponent] {
        await withCheckedContinuation { continuation in
            Self.visionQueue.async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = accurate ? .accurate : .fast
                request.usesLanguageCorrection = false
                request.minimumTextHeight = 0.009

                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
                do {
                    try handler.perform([request])
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    continuation.resume(returning: Self.extractComponents(from: observations))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Run Vision OCR on a still CGImage off the main thread.
    public func scan(cgImage: CGImage, accurate: Bool = true) async -> [DetectedComponent] {
        await withCheckedContinuation { continuation in
            Self.visionQueue.async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = accurate ? .accurate : .fast
                request.usesLanguageCorrection = false
                request.minimumTextHeight = 0.008

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    continuation.resume(returning: Self.extractComponents(from: observations))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    public static func extractComponents(from observations: [VNRecognizedTextObservation]) -> [DetectedComponent] {
        struct ChipHit {
            let marking: String
            let hint: String?
            let box: CGRect
            let center: CGPoint
        }

        var rawDesignators: [(String, ComponentCategory, CGRect)] = []
        var chipHits: [ChipHit] = []

        for obs in observations {
            guard let top = obs.topCandidates(1).first else { continue }
            let box = obs.boundingBox
            let center = CGPoint(x: box.midX, y: box.midY)
            let rawText = top.string.trimmingCharacters(in: .whitespacesAndNewlines)

            // 1. Check whole string collapsed (handles spaced silkscreen like "C 3", "RY 2", "IC 5")
            let collapsed = rawText.replacingOccurrences(of: " ", with: "")
            if collapsed.count <= 8, let (des, cat) = DesignatorCatalog.classifyDesignator(collapsed) {
                rawDesignators.append((des, cat, box))
                continue
            }

            // 2. Check individual tokens (preserving dots for 3.3V / 4.7K)
            let tokens = rawText.split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init)
            for token in tokens {
                if let (des, cat) = DesignatorCatalog.classifyDesignator(token) {
                    rawDesignators.append((des, cat, box))
                } else if let chip = DesignatorCatalog.matchChipMarking(token) {
                    chipHits.append(ChipHit(marking: chip.marking, hint: chip.hint, box: box, center: center))
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
                }), hypot(nearest.center.x - center.x, nearest.center.y - center.y) < 0.28 {
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
                    boxX: chip.box.origin.x,
                    boxY: chip.box.origin.y,
                    boxW: chip.box.size.width,
                    boxH: chip.box.size.height
                ))
            }
        }

        return results.sorted { $0.designator < $1.designator }
    }
}
