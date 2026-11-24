import AVFoundation
import SwiftUI
import UIKit

@MainActor
public final class CameraController: NSObject, ObservableObject {
    public let session = AVCaptureSession()
    @Published public var liveComponents: [DetectedComponent] = []
    @Published public var isAuthorized = false
    @Published public var cameraError: String?

    private let videoQueue = DispatchQueue(label: "com.craigmerry.circuitlens.video", qos: .userInitiated)
    private let ciContext = CIContext()
    private let scanner = BoardScanner()
    private var isScanningFrame = false
    private var lastScanTime: TimeInterval = 0
    private var latestCGImage: CGImage?

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
        videoQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
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

            let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
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
            guard !self.isScanningFrame, now - self.lastScanTime >= 0.45 else { return }
            self.isScanningFrame = true
            self.lastScanTime = now
            let found = await self.scanner.scan(cgImage: cgImage, accurate: false)
            self.liveComponents = found
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

/// Floating AR silkscreen callout pills pinned to Vision bounding boxes.
public struct AROverlayView: View {
    public let components: [DetectedComponent]
    public let onSelect: (DetectedComponent) -> Void

    public var body: some View {
        GeometryReader { geo in
            ForEach(components) { comp in
                let x = (comp.boxX + comp.boxW * 0.5) * geo.size.width
                let y = (1.0 - (comp.boxY + comp.boxH * 0.5)) * geo.size.height
                Button {
                    onSelect(comp)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(comp.category.color)
                            .frame(width: 7, height: 7)
                        Text(comp.displayTitle)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.78), in: Capsule())
                    .overlay(Capsule().stroke(comp.category.color, lineWidth: 1.5))
                }
                .position(
                    x: min(max(64, x), geo.size.width - 64),
                    y: min(max(44, y), geo.size.height - 44)
                )
            }
        }
    }
}
