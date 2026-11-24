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
    private let ciContext = CIContext()

    // Accessed only on videoQueue
    private nonisolated(unsafe) var isScanningFrame = false
    private nonisolated(unsafe) var lastScanTime: TimeInterval = 0
    private nonisolated(unsafe) var latestPixelBuffer: CVPixelBuffer?

    // Temporal tracker on MainActor so AR highlights stay steady on the PCB
    private struct TrackedItem {
        var component: DetectedComponent
        var lastSeen: TimeInterval
    }
    private var tracked: [String: TrackedItem] = [:]
    private let retentionWindow: TimeInterval = 1.8

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

    private func updateTracked(with found: [DetectedComponent], aspect: Double, at now: TimeInterval) {
        if abs(frameAspectRatio - aspect) > 0.01 {
            frameAspectRatio = aspect
        }
        let alpha = 0.65 // fast, responsive tracking directly over moving board symbols
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
        self.latestPixelBuffer = pixelBuffer

        let now = Date.timeIntervalSinceReferenceDate
        guard !self.isScanningFrame, now - self.lastScanTime >= 0.35 else { return }
        self.isScanningFrame = true
        self.lastScanTime = now

        let w = Double(CVPixelBufferGetWidth(pixelBuffer))
        let h = Double(CVPixelBufferGetHeight(pixelBuffer))
        let aspect = h > 0 ? (w / h) : (9.0 / 16.0)

        // Run Vision OCR directly on CVPixelBuffer off the main thread (no CGImage copy!)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.009

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        var found: [DetectedComponent] = []
        do {
            try handler.perform([request])
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            found = BoardScanner.extractComponents(from: observations)
        } catch {
            found = []
        }
        self.isScanningFrame = false

        let detected = found
        Task { @MainActor [weak self] in
            self?.updateTracked(with: detected, aspect: aspect, at: now)
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

/// Direct, pixel-exact on-symbol AR overlay pinned right onto each detected board symbol.
public struct AROverlayView: View {
    public let components: [DetectedComponent]
    public let frameAspectRatio: Double
    public let selectedID: String?
    public let onSelect: (DetectedComponent) -> Void

    public init(
        components: [DetectedComponent],
        frameAspectRatio: Double = 9.0 / 16.0,
        selectedID: String? = nil,
        onSelect: @escaping (DetectedComponent) -> Void
    ) {
        self.components = components
        self.frameAspectRatio = frameAspectRatio
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(components) { comp in
                    let rect = projectAspectFill(comp: comp, in: geo.size)
                    let isSelected = selectedID == comp.id

                    // Tight glowing highlight frame directly hugging the physical symbol on the PCB
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.yellow : comp.category.color, lineWidth: isSelected ? 3.0 : 2.0)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(comp.category.color.opacity(isSelected ? 0.28 : 0.14))
                        )
                        .frame(width: max(30, rect.width + 10), height: max(22, rect.height + 8))
                        .position(x: rect.midX, y: rect.midY)

                    // High-contrast direct on-symbol AR tag seated right at the symbol's top edge
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
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.86))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.yellow : comp.category.color, lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: min(max(56, rect.midX), geo.size.width - 56),
                        y: max(96, rect.minY - 14)
                    )
                }
            }
            .animation(.easeOut(duration: 0.12), value: components.map(\.id))
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
