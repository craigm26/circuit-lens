import Foundation
import ARKit
import CoreVideo
import simd

/// Physical board dimensions and component height relief captured via iPhone Pro LiDAR depth maps.
public struct LiDARMeasurement: Codable, Equatable, Sendable {
    public let distanceMM: Int
    public let estimatedWidthMM: Int
    public let estimatedHeightMM: Int
    public let maxComponentReliefMM: Int
    public let lidarAvailable: Bool
    public let sampledAt: Date

    public init(
        distanceMM: Int,
        estimatedWidthMM: Int,
        estimatedHeightMM: Int,
        maxComponentReliefMM: Int,
        lidarAvailable: Bool = true,
        sampledAt: Date = Date()
    ) {
        self.distanceMM = distanceMM
        self.estimatedWidthMM = estimatedWidthMM
        self.estimatedHeightMM = estimatedHeightMM
        self.maxComponentReliefMM = maxComponentReliefMM
        self.lidarAvailable = lidarAvailable
        self.sampledAt = sampledAt
    }

    public var summaryBadge: String {
        "~\(estimatedWidthMM) × \(estimatedHeightMM) mm · \(maxComponentReliefMM) mm relief"
    }

    public var promptDescription: String {
        "LiDAR physical scan: board approx \(estimatedWidthMM) mm × \(estimatedHeightMM) mm (measured at \(distanceMM) mm distance), tallest component relief ~\(maxComponentReliefMM) mm above PCB plane."
    }
}

public struct BoardPhotoAngle: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let imageFilename: String
    public let detectedCount: Int
    public let capturedAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        imageFilename: String,
        detectedCount: Int,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.imageFilename = imageFilename
        self.detectedCount = detectedCount
        self.capturedAt = capturedAt
    }
}

/// Unified multi-angle + LiDAR profile for any circuit board (known or unknown).
public struct BoardProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date
    public var lidar: LiDARMeasurement?
    public var components: [DetectedComponent]
    public var photos: [BoardPhotoAngle]
    public var summary: BoardSummaryResult?
    public var chatTurns: [ChatTurn]

    public init(
        id: UUID = UUID(),
        name: String = "Unknown Circuit Board",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lidar: LiDARMeasurement? = nil,
        components: [DetectedComponent] = [],
        photos: [BoardPhotoAngle] = [],
        summary: BoardSummaryResult? = nil,
        chatTurns: [ChatTurn] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lidar = lidar
        self.components = components
        self.photos = photos
        self.summary = summary
        self.chatTurns = chatTurns
    }

    /// Merge newly scanned components from an additional photo angle into this profile.
    /// Deduplicates by designator (or chip partMarking for unnamed ICs) and enriches missing markings.
    public mutating func merge(newComponents: [DetectedComponent]) {
        var byKey: [String: DetectedComponent] = [:]
        for c in components {
            let key = Self.mergeKey(for: c)
            byKey[key] = c
        }

        for incoming in newComponents {
            let key = Self.mergeKey(for: incoming)
            if let existing = byKey[key] {
                let mergedMarking = existing.partMarking ?? incoming.partMarking
                let mergedHint = existing.partHint ?? incoming.partHint
                byKey[key] = DetectedComponent(
                    designator: existing.designator,
                    category: existing.category,
                    partMarking: mergedMarking,
                    partHint: mergedHint,
                    boxX: existing.boxX,
                    boxY: existing.boxY,
                    boxW: existing.boxW,
                    boxH: existing.boxH
                )
            } else {
                byKey[key] = incoming
            }
        }

        self.components = byKey.values.sorted { $0.designator < $1.designator }
        self.updatedAt = Date()
    }

    private static func mergeKey(for component: DetectedComponent) -> String {
        if component.designator.hasPrefix("IC?"), let marking = component.partMarking {
            return "MARK:\(marking)"
        }
        return "DES:\(component.designator)"
    }

    /// Group detected components into high-level functional zones for unknown-board understanding.
    public var functionalZones: [(zone: String, items: [DetectedComponent])] {
        let order = [
            "Power & Protection",
            "Brains & Timing",
            "Switching & Control",
            "I/O, Ports & Sensors",
            "Passives & Filtering"
        ]
        var grouped: [String: [DetectedComponent]] = [:]
        for c in components {
            grouped[c.category.functionalZone, default: []].append(c)
        }
        return order.compactMap { zone in
            guard let items = grouped[zone], !items.isEmpty else { return nil }
            return (zone, items)
        }
    }
}

/// Runs a short ARKit LiDAR depth burst to estimate physical PCB width, height, and tallest component relief.
@MainActor
public final class LiDARMeasureController: NSObject, ObservableObject, ARSessionDelegate {
    @Published public var isScanning = false
    @Published public var latestMeasurement: LiDARMeasurement?
    @Published public var statusMessage: String?

    private let arSession = ARSession()
    private var burstTask: Task<Void, Never>?
    private var samples: [LiDARMeasurement] = []

    public static var isLiDARSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
            || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }

    public override init() {
        super.init()
        arSession.delegate = self
    }

    /// Capture a 2.2-second LiDAR burst, compute median dimensions & component relief, then stop ARSession cleanly.
    public func runMeasurementBurst(onComplete: @escaping (LiDARMeasurement?) -> Void) {
        guard Self.isLiDARSupported else {
            statusMessage = "LiDAR not available on this device — using multi-photo mapping."
            onComplete(nil)
            return
        }

        burstTask?.cancel()
        samples.removeAll()
        isScanning = true
        statusMessage = "Hold steady ~20–35 cm above the board..."

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])

        burstTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard let self else { return }
            self.arSession.pause()
            self.isScanning = false

            guard !self.samples.isEmpty else {
                self.statusMessage = "Could not lock LiDAR depth — move slightly farther from the PCB and retry."
                onComplete(nil)
                return
            }

            let sortedW = self.samples.map(\.estimatedWidthMM).sorted()
            let sortedH = self.samples.map(\.estimatedHeightMM).sorted()
            let sortedD = self.samples.map(\.distanceMM).sorted()
            let sortedR = self.samples.map(\.maxComponentReliefMM).sorted()
            let mid = self.samples.count / 2

            let result = LiDARMeasurement(
                distanceMM: sortedD[mid],
                estimatedWidthMM: sortedW[mid],
                estimatedHeightMM: sortedH[mid],
                maxComponentReliefMM: sortedR[mid],
                lidarAvailable: true
            )
            self.latestMeasurement = result
            self.statusMessage = "Measured: \(result.summaryBadge)"
            onComplete(result)
        }
    }

    public func cancel() {
        burstTask?.cancel()
        arSession.pause()
        isScanning = false
    }

    /// Extract scalar LiDAR metrics synchronously on the ARKit callback queue so ARFrame is never retained.
    public nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let depthMap = depthData.depthMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatStride = bytesPerRow / MemoryLayout<Float32>.size
        let ptr = baseAddress.assumingMemoryBound(to: Float32.self)

        // Sample the central 60% ROI where the user aims at the circuit board
        let x0 = Int(Double(width) * 0.20)
        let x1 = Int(Double(width) * 0.80)
        let y0 = Int(Double(height) * 0.20)
        let y1 = Int(Double(height) * 0.80)

        var depths: [Float] = []
        depths.reserveCapacity((x1 - x0) * (y1 - y0))

        for y in y0..<y1 {
            let row = ptr + y * floatStride
            for x in x0..<x1 {
                let z = row[x]
                if z.isFinite && z > 0.12 && z < 1.50 {
                    depths.append(z)
                }
            }
        }

        guard depths.count >= 40 else { return }
        depths.sort()

        // 70th percentile approximates the flat PCB substrate plane; 5th percentile approximates tallest component tops
        let boardPlaneZ = depths[Int(Double(depths.count) * 0.70)]
        let peakTopZ = depths[Int(Double(depths.count) * 0.05)]
        let reliefMeters = max(0, min(0.08, boardPlaneZ - peakTopZ))

        // Estimate physical span of the central 60% board ROI using camera intrinsics
        let intrinsics = frame.camera.intrinsics
        let imgRes = frame.camera.imageResolution
        let fx = max(1, Float(intrinsics[0, 0]))
        let fy = max(1, Float(intrinsics[1, 1]))
        let roiPixelsX = Float(imgRes.width) * 0.60
        let roiPixelsY = Float(imgRes.height) * 0.60

        let spanWidthMM = Int(((roiPixelsX / fx) * boardPlaneZ * 1000.0).rounded())
        let spanHeightMM = Int(((roiPixelsY / fy) * boardPlaneZ * 1000.0).rounded())
        let distMM = Int((boardPlaneZ * 1000.0).rounded())
        let reliefMM = Int((reliefMeters * 1000.0).rounded())

        guard spanWidthMM > 15, spanHeightMM > 15 else { return }

        let measurement = LiDARMeasurement(
            distanceMM: distMM,
            estimatedWidthMM: max(spanWidthMM, spanHeightMM),
            estimatedHeightMM: min(spanWidthMM, spanHeightMM),
            maxComponentReliefMM: reliefMM,
            lidarAvailable: true
        )

        Task { @MainActor [weak self] in
            guard let self, self.isScanning else { return }
            self.samples.append(measurement)
        }
    }
}
