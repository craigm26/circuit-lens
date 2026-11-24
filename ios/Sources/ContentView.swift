import SwiftUI
import UIKit

public struct ContentView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var explainer = BoardExplainer()

    @State private var level: LearningLevel = .kid
    @State private var frozenImage: UIImage?
    @State private var frozenComponents: [DetectedComponent] = []
    @State private var selectedComponent: DetectedComponent?
    @State private var showInspector = false
    @State private var questionText = ""
    @State private var studioURL = StudioSync.defaultEndpoint
    @State private var syncStatus: String?
    @State private var isFreezing = false

    private let scanner = BoardScanner()

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let frozen = frozenImage {
                    Image(uiImage: frozen)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                    AROverlayView(components: frozenComponents) { comp in
                        selectedComponent = comp
                        showInspector = true
                    }
                } else if camera.isAuthorized && camera.cameraError == nil {
                    CameraPreviewView(session: camera.session)
                        .ignoresSafeArea()
                    AROverlayView(components: camera.liveComponents) { comp in
                        selectedComponent = comp
                        frozenComponents = camera.liveComponents
                        showInspector = true
                        Task { await explainer.analyze(components: frozenComponents, level: level) }
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "cpu")
                            .font(.system(size: 52))
                            .foregroundStyle(.cyan)
                        Text("CircuitLens AR")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text(camera.cameraError ?? "Point your iPhone at any circuit board to read silkscreen codes (C3, IC5, RY2) and ask Apple Intelligence how it works.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Button("Try Demo Board (MIP290 Power PCB)") {
                            loadDemoBoard()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    }
                }

                // Top HUD bar
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CIRCUITLENS · AR PCB READER")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text(activeComponents.isEmpty ? "Aim at silkscreen codes (C3, IC5, RY2)" : "\(activeComponents.count) components detected")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        Spacer()
                        Picker("Level", selection: $level) {
                            ForEach(LearningLevel.allCases) { lvl in
                                Text(lvl.rawValue).tag(lvl)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.yellow)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                    Spacer()

                    // Bottom controls
                    HStack(spacing: 12) {
                        Button {
                            loadDemoBoard()
                        } label: {
                            Label("Demo", systemImage: "sparkles")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button {
                            freezeAndScan()
                        } label: {
                            HStack(spacing: 6) {
                                if isFreezing {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: frozenImage == nil ? "camera.viewfinder" : "arrow.counterclockwise")
                                }
                                Text(frozenImage == nil ? "Freeze & Explain" : "Live Camera")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .foregroundStyle(.black)

                        if !activeComponents.isEmpty {
                            Button {
                                if frozenComponents.isEmpty { frozenComponents = camera.liveComponents }
                                showInspector = true
                                Task { await explainer.analyze(components: activeComponents, level: level) }
                            } label: {
                                Label("Ask AI", systemImage: "brain")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            .onAppear { camera.start() }
            .onDisappear { camera.stop() }
            .sheet(isPresented: $showInspector) {
                BoardInspectorSheet(
                    components: activeComponents,
                    selected: $selectedComponent,
                    level: $level,
                    explainer: explainer,
                    questionText: $questionText,
                    studioURL: $studioURL,
                    syncStatus: $syncStatus,
                    frozenImage: frozenImage
                )
            }
        }
    }

    private var activeComponents: [DetectedComponent] {
        frozenComponents.isEmpty ? camera.liveComponents : frozenComponents
    }

    private func loadDemoBoard() {
        frozenImage = nil
        frozenComponents = DesignatorCatalog.demoBoard
        selectedComponent = DesignatorCatalog.demoBoard.first
        showInspector = true
        Task { await explainer.analyze(components: frozenComponents, level: level) }
    }

    private func freezeAndScan() {
        if frozenImage != nil {
            frozenImage = nil
            frozenComponents = []
            return
        }
        guard let snap = camera.captureSnapshot(), let cg = snap.cgImage else {
            loadDemoBoard()
            return
        }
        isFreezing = true
        frozenImage = snap
        Task {
            let found = await scanner.scan(cgImage: cg, accurate: true)
            frozenComponents = found.isEmpty ? camera.liveComponents : found
            isFreezing = false
            showInspector = true
            await explainer.analyze(components: frozenComponents, level: level)
        }
    }
}

private struct BoardInspectorSheet: View {
    let components: [DetectedComponent]
    @Binding var selected: DetectedComponent?
    @Binding var level: LearningLevel
    @ObservedObject var explainer: BoardExplainer
    @Binding var questionText: String
    @Binding var studioURL: String
    @Binding var syncStatus: String?
    let frozenImage: UIImage?

    var body: some View {
        NavigationStack {
            List {
                if let safety = explainer.summary?.safetyNote {
                    Section {
                        Label(safety, systemImage: "bolt.trianglebadge.exclamationmark.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    } header: {
                        Text("Family Safety Check")
                    }
                }

                Section {
                    Picker("Explain for", selection: $level) {
                        ForEach(LearningLevel.allCases) { lvl in
                            Text(lvl.rawValue).tag(lvl)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: level) { _, newVal in
                        Task { await explainer.analyze(components: components, level: newVal) }
                    }

                    if explainer.isThinking && explainer.summary == nil {
                        ProgressView("Reading the whole board...")
                    } else if let s = explainer.summary {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.deviceGuess).font(.headline)
                            Text(s.wholeBoardStory).font(.subheadline)
                            Text("Flow: \(s.signalFlow)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text("Engine: \(s.engineUsed)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Whole-Device Explanation")
                }

                Section {
                    ForEach(components) { comp in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle().fill(comp.category.color).frame(width: 9, height: 9)
                                Text(comp.displayTitle).font(.subheadline.bold().monospaced())
                                Spacer()
                                Text(comp.category.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(comp.partHint ?? comp.category.kidAnalogy)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .onTapGesture {
                            selected = comp
                            questionText = "What does \(comp.designator) do on this board?"
                        }
                    }
                } header: {
                    Text("Detected Components (\(components.count))")
                }

                Section {
                    ForEach(explainer.chatTurns) { turn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q: \(turn.question)").font(.subheadline.bold())
                            Text(turn.answer).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    HStack {
                        TextField("Ask about this board...", text: $questionText)
                            .textFieldStyle(.roundedBorder)
                        Button("Ask") {
                            let q = questionText
                            questionText = ""
                            Task { await explainer.ask(question: q, components: components, level: level) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(questionText.trimmingCharacters(in: .whitespaces).isEmpty || explainer.isThinking)
                    }
                } header: {
                    Text(explainer.isAppleIntelligenceAvailable ? "Ask Apple Intelligence" : "Ask About This Board")
                }

                Section {
                    TextField("Studio URL", text: $studioURL)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task {
                            syncStatus = "Saving to family studio..."
                            do {
                                let saved = try await StudioSync.upload(
                                    endpoint: studioURL,
                                    title: explainer.summary?.deviceGuess ?? "Scanned PCB",
                                    level: level,
                                    summary: explainer.summary,
                                    components: components,
                                    chatTurns: explainer.chatTurns,
                                    image: frozenImage
                                )
                                syncStatus = "Saved: \(saved)"
                            } catch {
                                syncStatus = "Could not reach \(studioURL) (\(error.localizedDescription))"
                            }
                        }
                    } label: {
                        Label("Save Teardown to pi-nas.local", systemImage: "square.and.arrow.up")
                    }
                    if let status = syncStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Family Electronics Studio")
                }
            }
            .navigationTitle("Board Explorer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
