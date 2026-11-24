import AVFoundation
import SwiftUI
import UIKit
import Vision

@MainActor
public final class CameraController: NSObject, ObservableObject {
    public let session = AVCaptureSession()
    @Published public var liveComponents: [DetectedComponent] = []
    @Published public var frameAspectRatio: Double = 9.0 / 16.0
    @Published public var isAuthorized = false
    @Published public var cameraError: String?
    @Published public var isTorchOn = false

    private let videoQueue = DispatchQueue(label: "com.craigmerry.circuitlens.video", qos: .userInitiated)
    private let ocrQueue = DispatchQueue(label: "com.craigmerry.circuitlens.ocr", qos: .userInitiated)
    private let ciContext = CIContext()

    // Accessed only on videoQueue
    private nonisolated(unsafe) var isRunningOCR = false
    private nonisolated(unsafe) var lastOCRTime: TimeInterval = 0
    private nonisolated(unsafe) var lastFlowTime: TimeInterval = 0
    private nonisolated(unsafe) var previousPixelBuffer: CVPixelBuffer?
    private nonisolated(unsafe) var latestPixelBuffer: CVPixelBuffer?

    // Board-locked temporal tracker on MainActor (deadband anti-jitter + optical flow shift)
    private struct TrackedItem {
        var component: DetectedComponent
        var lastSeen: TimeInterval
    }
    private var tracked: [String: TrackedItem] = [:]
    private let retentionWindow: TimeInterval = 4.0

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

    public func resetTracking() {
        tracked.removeAll()
        liveComponents = []
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
        var pb: CVPixelBuffer?
        videoQueue.sync {
            pb = self.latestPixelBuffer
        }
        guard let pb else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pb)
        guard let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
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

    /// Shift all locked labels smoothly by the board's frame-to-frame optical translation (zero bounce!).
    private func applyOpticalShift(dx: Double, dy: Double) {
        guard !tracked.isEmpty else { return }
        guard abs(dx) > 0.0005 || abs(dy) > 0.0005 else { return }

        var updated: [String: TrackedItem] = [:]
        for (key, item) in tracked {
            let c = item.component
            let nx = c.boxX - dx
            let ny = c.boxY - dy
            // Keep only labels still within visible bounds
            if nx > -0.15 && nx < 1.15 && ny > -0.15 && ny < 1.15 {
                let shifted = DetectedComponent(
                    designator: c.designator,
                    category: c.category,
                    partMarking: c.partMarking,
                    partHint: c.partHint,
                    boxX: nx,
                    boxY: ny,
                    boxW: c.boxW,
                    boxH: c.boxH
                )
                updated[key] = TrackedItem(component: shifted, lastSeen: item.lastSeen)
            }
        }
        tracked = updated
        liveComponents = tracked.values
            .map(\.component)
            .sorted { $0.designator < $1.designator }
    }

    /// Reconcile fresh OCR detections using deadband anti-jitter so locked labels stay static on the board.
    private func reconcileOCR(with found: [DetectedComponent], aspect: Double, at now: TimeInterval) {
        if abs(frameAspectRatio - aspect) > 0.01 {
            frameAspectRatio = aspect
        }

        let deadband = 0.018 // < 1.8% drift = zero movement (eliminates OCR sub-pixel bounce!)
        let blendAlpha = 0.25 // gentle drift correction when hand moves steadily

        for item in found {
            let key = item.designator
            if let prev = tracked[key] {
                let p = prev.component
                let dist = hypot(item.boxX - p.boxX, item.boxY - p.boxY)
                let finalX: Double
                let finalY: Double
                let finalW: Double
                let finalH: Double

                if dist < deadband {
                    // Stay rock-solid static on the board!
                    finalX = p.boxX
                    finalY = p.boxY
                    finalW = p.boxW
                    finalH = p.boxH
                } else if dist < 0.14 {
                    finalX = p.boxX * (1 - blendAlpha) + item.boxX * blendAlpha
                    finalY = p.boxY * (1 - blendAlpha) + item.boxY * blendAlpha
                    finalW = p.boxW * (1 - blendAlpha) + item.boxW * blendAlpha
                    finalH = p.boxH * (1 - blendAlpha) + item.boxH * blendAlpha
                } else {
                    finalX = item.boxX
                    finalY = item.boxY
                    finalW = item.boxW
                    finalH = item.boxH
                }

                let merged = DetectedComponent(
                    designator: item.designator,
                    category: item.category,
                    partMarking: item.partMarking ?? p.partMarking,
                    partHint: item.partHint ?? p.partHint,
                    boxX: finalX,
                    boxY: finalY,
                    boxW: finalW,
                    boxH: finalH
                )
                tracked[key] = TrackedItem(component: merged, lastSeen: now)
            } else {
                tracked[key] = TrackedItem(component: item, lastSeen: now)
            }
        }

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
        let now = Date.timeIntervalSinceReferenceDate
        let w = Double(CVPixelBufferGetWidth(pixelBuffer))
        let h = Double(CVPixelBufferGetHeight(pixelBuffer))
        let aspect = h > 0 ? (w / h) : (9.0 / 16.0)

        // 1. Lightweight ~20fps optical-flow board registration so locked labels stay static on the PCB
        if let prev = self.previousPixelBuffer, now - self.lastFlowTime >= 0.045 {
            self.lastFlowTime = now
            let regReq = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: pixelBuffer)
            let regHandler = VNImageRequestHandler(cvPixelBuffer: prev, options: [:])
            if let _ = try? regHandler.perform([regReq]),
               let obs = regReq.results?.first as? VNImageTranslationAlignmentObservation {
                let tx = Double(obs.alignmentTransform.tx)
                let ty = Double(obs.alignmentTransform.ty)
                let dx = w > 0 ? (tx / w) : 0
                let dy = h > 0 ? (ty / h) : 0
                if abs(dx) < 0.08 && abs(dy) < 0.08 {
                    Task { @MainActor [weak self] in
                        self?.applyOpticalShift(dx: dx, dy: dy)
                    }
                }
            }
        }
        self.previousPixelBuffer = pixelBuffer
        self.latestPixelBuffer = pixelBuffer

        // 2. High-accuracy Vision OCR every 0.60s on a separate queue (never blocks optical flow or UI)
        guard !self.isRunningOCR, now - self.lastOCRTime >= 0.60 else { return }
        self.isRunningOCR = true
        self.lastOCRTime = now

        let retainedBuffer = pixelBuffer
        self.ocrQueue.async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.009

            let handler = VNImageRequestHandler(cvPixelBuffer: retainedBuffer, options: [:])
            var found: [DetectedComponent] = []
            do {
                try handler.perform([request])
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                found = BoardScanner.extractComponents(from: observations)
            } catch {
                found = []
            }

            let detected = found
            self?.videoQueue.async {
                self?.isRunningOCR = false
            }
            Task { @MainActor [weak self] in
                self?.reconcileOCR(with: detected, aspect: aspect, at: now)
            }
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

/// Board-locked AR overlay with Power / Data / Safety circuit layers and animated signal-flow traces.
public struct AROverlayView: View {
    public let components: [DetectedComponent]
    public let frameAspectRatio: Double
    public let activeLayer: CircuitLayer
    public let selectedID: String?
    public let onSelect: (DetectedComponent) -> Void

    public init(
        components: [DetectedComponent],
        frameAspectRatio: Double = 9.0 / 16.0,
        activeLayer: CircuitLayer = .all,
        selectedID: String? = nil,
        onSelect: @escaping (DetectedComponent) -> Void
    ) {
        self.components = components
        self.frameAspectRatio = frameAspectRatio
        self.activeLayer = activeLayer
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0) * 28.0)

            GeometryReader { geo in
                let projected: [(comp: DetectedComponent, rect: CGRect, inLayer: Bool)] = components.map { c in
                    (c, projectAspectFill(comp: c, in: geo.size), c.belongs(to: activeLayer))
                }

                ZStack {
                    // 1. Animated Circuit Layer Flow Trace (Power or Data/Control path)
                    if activeLayer == .power || activeLayer == .data {
                        let chain = projected
                            .filter(\.inLayer)
                            .sorted { $0.comp.flowOrder(for: activeLayer) < $1.comp.flowOrder(for: activeLayer) }

                        if chain.count >= 2 {
                            // Soft glowing under-trace
                            Path { path in
                                path.move(to: CGPoint(x: chain[0].rect.midX, y: chain[0].rect.midY))
                                for node in chain.dropFirst() {
                                    path.addLine(to: CGPoint(x: node.rect.midX, y: node.rect.midY))
                                }
                            }
                            .stroke(activeLayer.tint.opacity(0.32), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))

                            // Animated marching energy/data pulse
                            Path { path in
                                path.move(to: CGPoint(x: chain[0].rect.midX, y: chain[0].rect.midY))
                                for node in chain.dropFirst() {
                                    path.addLine(to: CGPoint(x: node.rect.midX, y: node.rect.midY))
                                }
                            }
                            .stroke(
                                activeLayer.tint,
                                style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round, dash: [12, 10], dashPhase: -phase)
                            )
                        }
                    }

                    // 2. High-Voltage Safety Zone Halos when Safety layer is active
                    if activeLayer == .safety {
                        ForEach(projected.filter(\.inLayer), id: \.comp.id) { item in
                            Circle()
                                .fill(Color.red.opacity(0.20))
                                .overlay(Circle().stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 4], dashPhase: phase)))
                                .frame(width: max(84, item.rect.width * 2.2), height: max(84, item.rect.width * 2.2))
                                .position(x: item.rect.midX, y: item.rect.midY)
                        }
                    }

                    // 3. Static Board-Locked Highlight Frames & Compact On-Symbol Badges
                    ForEach(projected, id: \.comp.id) { item in
                        let comp = item.comp
                        let rect = item.rect
                        let isSelected = selectedID == comp.id
                        let isActive = item.inLayer
                        let accent = activeLayer == .all ? comp.category.color : (isActive ? activeLayer.tint : comp.category.color)

                        // Tight highlight frame hugging the physical symbol on the board
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.yellow : accent, lineWidth: isSelected ? 3.0 : (isActive ? 2.0 : 1.0))
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(accent.opacity(isSelected ? 0.28 : (isActive ? 0.14 : 0.04)))
                            )
                            .frame(width: max(28, rect.width + 8), height: max(22, rect.height + 6))
                            .position(x: rect.midX, y: rect.midY)
                            .opacity(isActive || isSelected ? 1.0 : 0.22)

                        // Compact board-locked badge seated directly on the symbol's top edge
                        if isActive || isSelected {
                            Button {
                                onSelect(comp)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(comp.designator)
                                        .font(.system(size: 12, weight: .black, design: .monospaced))
                                        .foregroundStyle(.yellow)
                                    Text(comp.partMarking ?? comp.category.rawValue)
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.86)))
                                .overlay(Capsule().stroke(isSelected ? Color.yellow : accent, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
                            }
                            .buttonStyle(.plain)
                            .position(
                                x: min(max(54, rect.midX), geo.size.width - 54),
                                y: max(108, rect.minY - 13)
                            )
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Exact `.resizeAspectFill` projection from Vision normalized coordinates (bottom-left origin) to screen points.
    private func projectAspectFill(comp: DetectedComponent, in viewSize: CGSize) -> CGRect {
        let viewW = max(1, viewSize.width)
        let viewH = max(1, viewSize.height)
        let viewAspect = viewW / viewH
        let imgAspect = max(0.2, frameAspectRatio)

        let renderedW: CGFloat
        let renderedH: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        if imgAspect > viewAspect {
            renderedH = viewH
            renderedW = viewH * imgAspect
            offsetX = (viewW - renderedW) * 0.5
            offsetY = 0
        } else {
            renderedW = viewW
            renderedH = viewW / imgAspect
            offsetX = 0
            offsetY = (viewH - renderedH) * 0.5
        }

        let x = offsetX + comp.boxX * renderedW
        let y = offsetY + (1.0 - comp.boxY - comp.boxH) * renderedH
        let w = comp.boxW * renderedW
        let h = comp.boxH * renderedH
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
