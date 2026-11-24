import SwiftUI
import UIKit

public struct ContentView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var explainer = BoardExplainer()
    @StateObject private var lidar = LiDARMeasureController()
    @StateObject private var profileStore = BoardProfileStore()

    @State private var level: LearningLevel = .kid
    @State private var activeProfile: BoardProfile?
    @State private var frozenImage: UIImage?
    @State private var frozenComponents: [DetectedComponent] = []
    @State private var selectedComponent: DetectedComponent?
    @State private var isLiveCardExpanded = true
    @State private var showInspector = false
    @State private var showLibrary = false
    @State private var isAddingAngle = false
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
                    AROverlayView(
                        components: frozenComponents,
                        frameAspectRatio: Double(frozen.size.width / max(1, frozen.size.height)),
                        selectedID: selectedComponent?.id
                    ) { comp in
                        withAnimation(.spring(response: 0.25)) {
                            selectedComponent = (selectedComponent?.id == comp.id) ? nil : comp
                        }
                    }
                } else if camera.isAuthorized && camera.cameraError == nil {
                    CameraPreviewView(session: camera.session)
                        .ignoresSafeArea()
                    AROverlayView(
                        components: camera.liveComponents,
                        frameAspectRatio: camera.frameAspectRatio,
                        selectedID: selectedComponent?.id
                    ) { comp in
                        withAnimation(.spring(response: 0.25)) {
                            selectedComponent = (selectedComponent?.id == comp.id) ? nil : comp
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "cpu")
                            .font(.system(size: 52))
                            .foregroundStyle(.cyan)
                        Text("CircuitLens AR")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text(camera.cameraError ?? "Point your iPhone at any circuit board to see live AR symbol labels and real-time AI analysis.")
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

                // Top & Bottom Floating HUD
                VStack(spacing: 8) {
                    // Top HUD bar
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(activeComponents.isEmpty ? .gray : .green)
                                        .frame(width: 7, height: 7)
                                    Text(isAddingAngle ? "MAPPING ANGLE #\((activeProfile?.photos.count ?? 0) + 1)" : "CIRCUITLENS AR")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isAddingAngle ? .orange : .cyan)
                                }
                                Text(hudSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                            Spacer()

                            // Torch button for dim circuit boards
                            Button {
                                camera.toggleTorch()
                            } label: {
                                Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(camera.isTorchOn ? .yellow : .white)
                            }
                            .buttonStyle(.bordered)
                            .tint(camera.isTorchOn ? .yellow : .white)

                            // Saved Boards Library
                            Button {
                                showLibrary = true
                            } label: {
                                Label("\(profileStore.profiles.count)", systemImage: "square.stack.3d.up.fill")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)

                            // Learning Level
                            Picker("Level", selection: $level) {
                                ForEach(LearningLevel.allCases) { lvl in
                                    Text(lvl.rawValue).tag(lvl)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.yellow)
                        }

                        if let badge = activeProfile?.lidar?.summaryBadge ?? lidar.latestMeasurement?.summaryBadge {
                            HStack(spacing: 6) {
                                Image(systemName: "cube.transparent")
                                    .foregroundStyle(.mint)
                                Text("LiDAR: \(badge)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.mint)
                                Spacer()
                                if let count = activeProfile?.photos.count, count > 0 {
                                    Text("\(count) \(count == 1 ? "angle" : "angles")")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.cyan)
                                }
                            }
                        } else if let status = lidar.statusMessage {
                            HStack(spacing: 6) {
                                if lidar.isScanning {
                                    ProgressView().controlSize(.mini).tint(.mint)
                                }
                                Text(status)
                                    .font(.caption2)
                                    .foregroundStyle(.mint)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    Spacer()

                    // Inline Quick-Inspect Card when user taps any AR symbol on the live board
                    if let comp = selectedComponent {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: comp.category.sfSymbol)
                                    .foregroundStyle(comp.category.color)
                                Text(comp.displayTitle)
                                    .font(.subheadline.bold().monospaced())
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(comp.category.functionalZone)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(comp.category.color.opacity(0.25), in: Capsule())
                                    .foregroundStyle(comp.category.color)
                                Button {
                                    withAnimation { selectedComponent = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            Text(comp.partHint ?? comp.category.kidAnalogy)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.92))
                            HStack {
                                Button {
                                    questionText = "What does \(comp.displayTitle) do on this board?"
                                    openQuickInspect(components: activeComponents)
                                } label: {
                                    Label("Ask AI about \(comp.designator)", systemImage: "sparkles")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .controlSize(.small)
                                Spacer()
                            }
                        }
                        .padding(11)
                        .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(comp.category.color.opacity(0.7), lineWidth: 1.2))
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Real-Time "Live AI Analysis" Card directly over the live camera view
                    liveAIAnalysisCard
                        .padding(.horizontal, 12)

                    // Bottom Action Dock
                    HStack(spacing: 10) {
                        Button {
                            runLiDARMeasure()
                        } label: {
                            HStack(spacing: 4) {
                                if lidar.isScanning {
                                    ProgressView().controlSize(.small).tint(.mint)
                                } else {
                                    Image(systemName: "ruler")
                                }
                                Text("LiDAR")
                                    .font(.subheadline.bold())
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.mint)
                        .disabled(lidar.isScanning)

                        Button {
                            captureAndMapAngle()
                        } label: {
                            HStack(spacing: 6) {
                                if isFreezing {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: frozenImage == nil ? "camera.viewfinder" : "arrow.counterclockwise")
                                }
                                Text(primaryButtonTitle)
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isAddingAngle ? .orange : .cyan)
                        .foregroundStyle(.black)
                        .disabled(lidar.isScanning || isFreezing)

                        if !activeComponents.isEmpty || activeProfile != nil {
                            Button {
                                if activeProfile == nil {
                                    openQuickInspect(components: activeComponents)
                                } else {
                                    showInspector = true
                                }
                            } label: {
                                Label("Ask AI", systemImage: "brain")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        } else {
                            Button {
                                loadDemoBoard()
                            } label: {
                                Label("Demo", systemImage: "sparkles")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                    }
                    .padding(11)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .onAppear { camera.start() }
            .onDisappear {
                lidar.cancel()
                camera.stop()
            }
            .onChange(of: camera.liveComponents) { _, newComps in
                guard frozenImage == nil, !newComps.isEmpty else { return }
                Task {
                    await explainer.liveAnalyzeIfNeeded(
                        components: newComps,
                        lidar: activeProfile?.lidar ?? lidar.latestMeasurement,
                        level: level
                    )
                }
            }
            .onChange(of: level) { _, newLevel in
                guard !activeComponents.isEmpty else { return }
                Task {
                    await explainer.liveAnalyzeIfNeeded(
                        components: activeComponents,
                        lidar: activeProfile?.lidar ?? lidar.latestMeasurement,
                        level: newLevel
                    )
                }
            }
            .sheet(isPresented: $showInspector) {
                if let profile = activeProfile {
                    BoardInspectorSheet(
                        profile: profile,
                        selected: $selectedComponent,
                        level: $level,
                        explainer: explainer,
                        profileStore: profileStore,
                        questionText: $questionText,
                        studioURL: $studioURL,
                        syncStatus: $syncStatus,
                        primaryImage: primaryProfileImage(for: profile),
                        onUpdateProfile: { updated in
                            activeProfile = updated
                            profileStore.save(updated)
                        },
                        onAddAngle: {
                            showInspector = false
                            frozenImage = nil
                            isAddingAngle = true
                            camera.start()
                        },
                        onMeasureLiDAR: {
                            showInspector = false
                            frozenImage = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                runLiDARMeasure()
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showLibrary) {
                BoardLibrarySheet(
                    store: profileStore,
                    onSelect: { chosen in
                        activeProfile = chosen
                        frozenComponents = chosen.components
                        frozenImage = chosen.photos.first.flatMap { profileStore.loadPhoto(filename: $0.imageFilename) }
                        explainer.summary = chosen.summary
                        explainer.chatTurns = chosen.chatTurns
                        showLibrary = false
                        showInspector = true
                    },
                    onNewBoard: {
                        activeProfile = nil
                        frozenImage = nil
                        frozenComponents = []
                        selectedComponent = nil
                        isAddingAngle = false
                        explainer.summary = nil
                        explainer.chatTurns = []
                        showLibrary = false
                        camera.start()
                    }
                )
            }
        }
    }

    // MARK: - Live AI Analysis HUD Card

    @ViewBuilder
    private var liveAIAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: explainer.isLiveAnalyzing || explainer.isThinking ? "sparkles" : "brain.head.profile")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                Text(explainer.isLiveAnalyzing || explainer.isThinking ? "LIVE AI ANALYZING..." : "LIVE AI ANALYSIS")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.cyan)
                if explainer.isLiveAnalyzing || explainer.isThinking {
                    ProgressView().controlSize(.mini).tint(.cyan)
                }
                Spacer()
                if explainer.summary?.safetyNote != nil {
                    Label("HV", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.28), in: Capsule())
                        .foregroundStyle(.red)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLiveCardExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isLiveCardExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            if let s = explainer.summary {
                Text(s.deviceGuess)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if isLiveCardExpanded {
                    Text(s.wholeBoardStory)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)

                    HStack(spacing: 6) {
                        Text(s.signalFlow)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.yellow)
                            .lineLimit(1)
                        Spacer()
                        Text(explainer.isAppleIntelligenceAvailable ? "Apple Intelligence" : "On-Device")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            } else {
                Text(activeComponents.isEmpty
                     ? "Point your camera slowly over any circuit board — AR labels and live AI explanation will appear automatically."
                     : "Reading \(activeComponents.count) symbols on this board...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.cyan.opacity(0.35), lineWidth: 1)
        )
        .onTapGesture {
            if !activeComponents.isEmpty {
                openQuickInspect(components: activeComponents)
            }
        }
    }

    private var activeComponents: [DetectedComponent] {
        if let profile = activeProfile, !profile.components.isEmpty {
            return profile.components
        }
        return frozenComponents.isEmpty ? camera.liveComponents : frozenComponents
    }

    private var hudSubtitle: String {
        if isAddingAngle {
            return "Aim at another side or close-up IC, then tap Add Angle"
        }
        if activeComponents.isEmpty {
            return "Scanning live for symbols (C3, R12, U1, IC5)…"
        }
        return "\(activeComponents.count) board symbols locked in AR"
    }

    private var primaryButtonTitle: String {
        if frozenImage != nil && !isAddingAngle {
            return "Live Camera"
        }
        if isAddingAngle {
            return "Add Angle"
        }
        return "Map Board"
    }

    private func primaryProfileImage(for profile: BoardProfile) -> UIImage? {
        if let frozenImage { return frozenImage }
        return profile.photos.first.flatMap { profileStore.loadPhoto(filename: $0.imageFilename) }
    }

    private func runLiDARMeasure() {
        camera.stop()
        lidar.runMeasurementBurst { measurement in
            camera.start()
            guard let measurement else { return }
            if var existing = activeProfile {
                existing.lidar = measurement
                activeProfile = existing
                profileStore.save(existing)
            } else {
                let fresh = BoardProfile(
                    name: "Measured Unknown Board",
                    lidar: measurement,
                    components: camera.liveComponents
                )
                activeProfile = fresh
                profileStore.save(fresh)
            }
        }
    }

    private func openQuickInspect(components: [DetectedComponent]) {
        var profile = activeProfile ?? BoardProfile(
            name: explainer.summary?.deviceGuess ?? "Scanned Circuit Board",
            lidar: lidar.latestMeasurement,
            components: components
        )
        profile.merge(newComponents: components)
        activeProfile = profile
        frozenComponents = profile.components
        profileStore.save(profile)
        showInspector = true
        Task {
            await explainer.analyze(profile: profile, level: level)
            if var updated = activeProfile {
                updated.summary = explainer.summary
                if let guess = explainer.summary?.deviceGuess,
                   updated.name == "Scanned Circuit Board" || updated.name == "Unknown Circuit Board" {
                    updated.name = guess
                }
                activeProfile = updated
                profileStore.save(updated)
            }
        }
    }

    private func loadDemoBoard() {
        frozenImage = nil
        isAddingAngle = false
        let demoProfile = BoardProfile(
            name: "MIP290 Appliance Power PCB (Demo)",
            lidar: LiDARMeasurement(distanceMM: 260, estimatedWidthMM: 92, estimatedHeightMM: 64, maxComponentReliefMM: 18, lidarAvailable: true),
            components: DesignatorCatalog.demoBoard
        )
        activeProfile = demoProfile
        frozenComponents = demoProfile.components
        selectedComponent = demoProfile.components.first
        explainer.chatTurns = []
        showInspector = true
        Task {
            await explainer.analyze(profile: demoProfile, level: level)
            if var updated = activeProfile {
                updated.summary = explainer.summary
                activeProfile = updated
                profileStore.save(updated)
            }
        }
    }

    private func captureAndMapAngle() {
        if frozenImage != nil && !isAddingAngle {
            frozenImage = nil
            frozenComponents = []
            selectedComponent = nil
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
            let scanned = found.isEmpty ? camera.liveComponents : found

            var profile: BoardProfile
            if isAddingAngle, let existing = activeProfile {
                profile = existing
            } else if let existing = activeProfile, existing.photos.isEmpty, existing.lidar != nil {
                profile = existing
            } else {
                profile = BoardProfile(
                    name: explainer.summary?.deviceGuess ?? "Unknown Circuit Board",
                    lidar: lidar.latestMeasurement
                )
                explainer.chatTurns = []
            }

            let angleNumber = profile.photos.count + 1
            let angleLabel = angleNumber == 1 ? "Overview" : "Angle \(angleNumber)"
            if let filename = profileStore.savePhoto(snap, profileID: profile.id) {
                profile.photos.append(BoardPhotoAngle(
                    label: angleLabel,
                    imageFilename: filename,
                    detectedCount: scanned.count
                ))
            }
            profile.merge(newComponents: scanned)
            if profile.lidar == nil {
                profile.lidar = lidar.latestMeasurement
            }

            activeProfile = profile
            frozenComponents = profile.components
            isAddingAngle = false
            isFreezing = false
            profileStore.save(profile)
            showInspector = true

            await explainer.analyze(profile: profile, level: level)
            if var updated = activeProfile {
                updated.summary = explainer.summary
                if let guess = explainer.summary?.deviceGuess,
                   updated.name == "Unknown Circuit Board" || updated.name == "Measured Unknown Board" {
                    updated.name = guess
                }
                activeProfile = updated
                profileStore.save(updated)
            }
        }
    }
}

private struct BoardInspectorSheet: View {
    let profile: BoardProfile
    @Binding var selected: DetectedComponent?
    @Binding var level: LearningLevel
    @ObservedObject var explainer: BoardExplainer
    @ObservedObject var profileStore: BoardProfileStore
    @Binding var questionText: String
    @Binding var studioURL: String
    @Binding var syncStatus: String?
    let primaryImage: UIImage?
    let onUpdateProfile: (BoardProfile) -> Void
    let onAddAngle: () -> Void
    let onMeasureLiDAR: () -> Void

    @State private var boardName: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Board Name", text: $boardName)
                        .font(.headline)
                        .onAppear { boardName = profile.name }
                        .onChange(of: boardName) { _, newName in
                            var updated = profile
                            updated.name = newName
                            onUpdateProfile(updated)
                        }

                    if let lidar = profile.lidar {
                        HStack {
                            Label("LiDAR Size", systemImage: "cube.transparent")
                                .font(.subheadline)
                            Spacer()
                            Text(lidar.summaryBadge)
                                .font(.caption.monospaced())
                                .foregroundStyle(.mint)
                        }
                    } else {
                        Button {
                            onMeasureLiDAR()
                        } label: {
                            Label(
                                LiDARMeasureController.isLiDARSupported
                                    ? "Measure Board Dimensions with LiDAR"
                                    : "LiDAR Sensor Not Available on This Device",
                                systemImage: "ruler"
                            )
                        }
                        .disabled(!LiDARMeasureController.isLiDARSupported)
                    }

                    if !profile.photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(profile.photos) { angle in
                                    VStack(spacing: 4) {
                                        if let img = profileStore.loadPhoto(filename: angle.imageFilename) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 78, height: 58)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        Text("\(angle.label) (\(angle.detectedCount))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Button {
                        onAddAngle()
                    } label: {
                        Label("Add Another Photo Angle (Close-up / Back Side)", systemImage: "camera.badge.plus")
                            .font(.subheadline.bold())
                    }
                    .tint(.orange)
                } header: {
                    Text("Board Profile (\(profile.photos.count) \(profile.photos.count == 1 ? "Photo" : "Photos") · \(profile.components.count) Parts)")
                }

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
                        Task { await explainer.analyze(profile: profile, level: newVal) }
                    }

                    if explainer.isThinking && explainer.summary == nil {
                        ProgressView("Building whole-board profile...")
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
                    Text("Whole-Board Explanation")
                }

                ForEach(profile.functionalZones, id: \.zone) { group in
                    Section {
                        ForEach(group.items) { comp in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: comp.category.sfSymbol)
                                        .foregroundStyle(comp.category.color)
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
                                questionText = "What does \(comp.displayTitle) do on this board?"
                            }
                        }
                    } header: {
                        Text("\(group.zone) (\(group.items.count))")
                    }
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
                            Task {
                                await explainer.ask(question: q, profile: profile, level: level)
                                var updated = profile
                                updated.chatTurns = explainer.chatTurns
                                onUpdateProfile(updated)
                            }
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
                            syncStatus = "Saving board profile to family studio..."
                            do {
                                let saved = try await StudioSync.upload(
                                    endpoint: studioURL,
                                    title: boardName.isEmpty ? (explainer.summary?.deviceGuess ?? "Scanned PCB") : boardName,
                                    level: level,
                                    summary: explainer.summary,
                                    lidar: profile.lidar,
                                    photoCount: max(1, profile.photos.count),
                                    components: profile.components,
                                    chatTurns: explainer.chatTurns,
                                    image: primaryImage
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
            .navigationTitle("Board Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BoardLibrarySheet: View {
    @ObservedObject var store: BoardProfileStore
    let onSelect: (BoardProfile) -> Void
    let onNewBoard: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.profiles.isEmpty {
                    ContentUnavailableView(
                        "No Saved Boards Yet",
                        systemImage: "cpu",
                        description: Text("Point your camera at any circuit board and tap Map Board to build a profile with LiDAR and multi-angle photos.")
                    )
                } else {
                    ForEach(store.profiles) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack(spacing: 12) {
                                if let first = item.photos.first,
                                   let img = store.loadPhoto(filename: first.imageFilename) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.cyan.opacity(0.15))
                                        .frame(width: 56, height: 56)
                                        .overlay(Image(systemName: "cpu").foregroundStyle(.cyan))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text("\(item.components.count) parts · \(item.photos.count) \(item.photos.count == 1 ? "photo" : "photos")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let lidar = item.lidar {
                                        Text(lidar.summaryBadge)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.mint)
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            store.delete(store.profiles[idx])
                        }
                    }
                }
            }
            .navigationTitle("My Boards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onNewBoard()
                    } label: {
                        Label("New Scan", systemImage: "plus")
                    }
                }
            }
        }
    }
}
