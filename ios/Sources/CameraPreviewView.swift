import AVFoundation
import SwiftUI
import UIKit

@MainActor
public final class CameraController: NSObject, ObservableObject {
    public let session = AVCaptureSession()
    @Published public var liveComponents: [DetectedComponent] = []
    @Published public var isAuthorized = false
    @Published public var cameraError: String?
    @Published public var isTorchOn = false

    private let videoQueue = DispatchQueue(label: "com.craigmerry.circuitlens.video", qos: .userInitiated)
    private let ciContext = CIContext()
    private let scanner = BoardScanner()
    private var isScanningFrame = false
    private var lastScanTime: TimeInterval = 0
    private var latestCGImage: CGImage?

    // Temporal tracker so detected AR labels stay locked & smooth across live frames
    private struct TrackedItem {
        var component: DetectedComponent
        var lastSeen: TimeInterval
    }
    private var tracked: [String: TrackedItem] = [:]
    private let retentionWindow: TimeInterval = 2.4

    public override init() {
        super.init()
    }

    public func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.isAuthorized = granted
                    if granted { self?.configureAndRun() }
                    else { self?.cameraError = "Camera permission is needed to scan circuit boards." }
                }
            }
        default:
            isAuthorized = false
            cameraError = "Enable Camera access in Settings to scan circuit boards."
        }
    }

    public func stop() {
        setTorch(enabled: false)
        videoQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    public func toggleTorch() {
        setTorch(enabled: !isTorchOn)
    }

    public func setTorch(enabled: Bool) {
        let target = enabled
        videoQueue.async { [session, weak self] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
                  device.hasTorch else {
                Task { @MainActor in self?.isTorchOn = false }
                return
            }
            do {
                try device.lockForConfiguration()
                device.torchMode = target ? .on : .off
                device.unlockForConfiguration()
                Task { @MainActor in self?.isTorchOn = target }
            } catch {
                Task { @MainActor in self?.isTorchOn = false }
            }
        }
    }

    public func captureSnapshot() -> UIImage? {
        guard let cg = latestCGImage else { return nil }
        return UIImage(cgImage: cg)
    }

    private func configureAndRun() {
        videoQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.inputs.isEmpty {
                if !self.session.isRunning { self.session.startRunning() }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080

            // Prefer multi-cam systems that auto-switch to macro close-ups seamlessly
            let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)

            guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                Task { @MainActor in self.cameraError = "No back camera available (use Demo Board in Simulator)." }
                return
            }

            if self.session.canAddInput(input) { self.session.addInput(input) }

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(output) { self.session.addOutput(output) }

            if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }

            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            device.unlockForConfiguration()

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    private func updateTracked(with found: [DetectedComponent], at now: TimeInterval) {
        let alpha = 0.55 // smooth bounding box motion
        for item in found {
            let key = item.designator
            if let prev = tracked[key] {
                let p = prev.component
                let smoothed = DetectedComponent(
                    designator: item.designator,
                    category: item.category,
                    partMarking: item.partMarking ?? p.partMarking,
                    partHint: item.partHint ?? p.partHint,
                    boxX: p.boxX * (1 - alpha) + item.boxX * alpha,
                    boxY: p.boxY * (1 - alpha) + item.boxY * alpha,
                    boxW: p.boxW * (1 - alpha) + item.boxW * alpha,
                    boxH: p.boxH * (1 - alpha) + item.boxH * alpha
                )
                tracked[key] = TrackedItem(component: smoothed, lastSeen: now)
            } else {
                tracked[key] = TrackedItem(component: item, lastSeen: now)
            }
        }

        // Expire items not seen recently
        tracked = tracked.filter { now - $0.value.lastSeen <= retentionWindow }
        liveComponents = tracked.values
            .map(\.component)
            .sorted { $0.designator < $1.designator }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let now = Date.timeIntervalSinceReferenceDate
        Task { @MainActor in
            self.latestCGImage = cgImage
            guard !self.isScanningFrame, now - self.lastScanTime >= 0.55 else { return }
            self.isScanningFrame = true
            self.lastScanTime = now
            let found = await self.scanner.scan(cgImage: cgImage, accurate: false)
            self.updateTracked(with: found, at: now)
            self.isScanningFrame = false
        }
    }
}

public struct CameraPreviewView: UIViewRepresentable {
    public let session: AVCaptureSession

    public func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    public func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    public final class PreviewUIView: UIView {
        public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        public var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Rich AR overlay pinning glowing target boxes + leader pins + readable symbol labels over ALL detected board symbols.
public struct AROverlayView: View {
    public let components: [DetectedComponent]
    public let selectedID: String?
    public let onSelect: (DetectedComponent) -> Void

    public init(
        components: [DetectedComponent],
        selectedID: String? = nil,
        onSelect: @escaping (DetectedComponent) -> Void
    ) {
        self.components = components
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geo in
            let placed = computeLabelPositions(in: geo.size)

            ZStack {
                // 1. Target reticles & leader pins directly over each detected board symbol
                ForEach(placed, id: \.component.id) { item in
                    let comp = item.component
                    let isSelected = selectedID == comp.id
                    let rect = item.boxRect

                    // Glowing target box over the actual silkscreen/chip bounding box
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(comp.category.color, lineWidth: isSelected ? 2.5 : 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(comp.category.color.opacity(isSelected ? 0.24 : 0.10))
                        )
                        .frame(width: max(26, rect.width + 10), height: max(20, rect.height + 8))
                        .position(x: rect.midX, y: rect.midY)

                    // Leader line connecting the board symbol to its AR label card
                    Path { path in
                        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                        path.addLine(to: CGPoint(x: item.labelCenter.x, y: item.labelCenter.y + 18))
                    }
                    .stroke(comp.category.color.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, dash: [3, 2]))

                    // Anchor dot on the symbol
                    Circle()
                        .fill(comp.category.color)
                        .frame(width: 6, height: 6)
                        .position(x: rect.midX, y: rect.midY)
                }

                // 2. Floating AR Symbol Callout Cards (designator + role/chip marking)
                ForEach(placed, id: \.component.id) { item in
                    let comp = item.component
                    let isSelected = selectedID == comp.id

                    Button {
                        onSelect(comp)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: comp.category.sfSymbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(comp.category.color)
                                .frame(width: 16, height: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(comp.designator)
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(.white)
                                    if let marking = comp.partMarking, !marking.isEmpty {
                                        Text(marking)
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.yellow)
                                            .lineLimit(1)
                                    }
                                }
                                Text(comp.category.rawValue + " · " + comp.category.shortRole)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.black.opacity(isSelected ? 0.92 : 0.78))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(comp.category.color, lineWidth: isSelected ? 2.2 : 1.3)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .position(item.labelCenter)
                }
            }
            .animation(.easeOut(duration: 0.18), value: components.map(\.id))
        }
    }

    private struct PlacedLabel {
        let component: DetectedComponent
        let boxRect: CGRect
        let labelCenter: CGPoint
    }

    /// Compute non-overlapping AR label positions gently nudged above each board symbol.
    private func computeLabelPositions(in size: CGSize) -> [PlacedLabel] {
        let topSafe: CGFloat = 110
        let bottomSafe: CGFloat = max(topSafe + 60, size.height - 235)
        let halfW: CGFloat = 78
        let minDy: CGFloat = 40
        let minDx: CGFloat = 132

        var placed: [PlacedLabel] = []
        let sorted = components.sorted { $0.boxY > $1.boxY } // top-to-bottom on screen

        for comp in sorted {
            let rx = comp.boxX * size.width
            let rw = comp.boxW * size.width
            let rh = comp.boxH * size.height
            let ry = (1.0 - comp.boxY - comp.boxH) * size.height
            let rect = CGRect(x: rx, y: ry, width: rw, height: rh)

            var lx = min(max(halfW, rect.midX), size.width - halfW)
            var ly = min(max(topSafe, rect.minY - 26), bottomSafe)

            // Simple collision push so dense board symbols remain readable
            for _ in 0..<4 {
                var nudged = false
                for existing in placed {
                    if abs(existing.labelCenter.x - lx) < minDx && abs(existing.labelCenter.y - ly) < minDy {
                        ly = (ly - minDy >= topSafe) ? (ly - minDy) : min(bottomSafe, ly + minDy)
                        lx = min(max(halfW, lx + (lx < size.width * 0.5 ? 24 : -24)), size.width - halfW)
                        nudged = true
                    }
                }
                if !nudged { break }
            }

            placed.append(PlacedLabel(
                component: comp,
                boxRect: rect,
                labelCenter: CGPoint(x: lx, y: ly)
            ))
        }
        return placed
    }
}
