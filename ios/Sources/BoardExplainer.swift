import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct BoardSummaryResult: Codable, Equatable, Sendable {
    public let deviceGuess: String
    public let wholeBoardStory: String
    public let signalFlow: String
    public let safetyNote: String?
    public let engineUsed: String
}

public struct ChatTurn: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let question: String
    public let answer: String

    public init(id: UUID = UUID(), question: String, answer: String) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedBoardSummary {
    @Guide(description: "Short friendly title guessing what kind of circuit board this is (3 to 7 words).")
    var deviceGuess: String

    @Guide(description: "2 to 3 clear sentences explaining what this whole electronics board does, using both the detected parts and physical size if provided.")
    var wholeBoardStory: String

    @Guide(description: "One-line step-by-step power or signal flow using '->' arrows between the detected parts.")
    var signalFlow: String
}
#endif

@MainActor
public final class BoardExplainer: ObservableObject {
    @Published public var summary: BoardSummaryResult?
    @Published public var isThinking = false
    @Published public var chatTurns: [ChatTurn] = []

    public init() {}

    public var isAppleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    public func analyze(profile: BoardProfile, level: LearningLevel) async {
        await analyze(
            components: profile.components,
            lidar: profile.lidar,
            photoCount: profile.photos.count,
            level: level
        )
    }

    public func analyze(
        components: [DetectedComponent],
        lidar: LiDARMeasurement? = nil,
        photoCount: Int = 1,
        level: LearningLevel
    ) async {
        isThinking = true
        defer { isThinking = false }

        let hvWarning = DesignatorCatalog.hasHighVoltageClues(components)
            ? "Unplug this device before touching the board. Relays, fuses, varistors, and large cylindrical capacitors near switching power ICs can hold a dangerous shock even after unplugging."
            : nil

        let partsList = components.map { c in
            let extra = [c.partMarking, c.partHint].compactMap { $0 }.joined(separator: " - ")
            return extra.isEmpty
                ? "\(c.designator) (\(c.category.rawValue), zone: \(c.category.functionalZone))"
                : "\(c.designator) (\(c.category.rawValue), zone: \(c.category.functionalZone): \(extra))"
        }.joined(separator: "\n")

        let lidarLine = lidar?.promptDescription ?? "No LiDAR physical measurement yet."
        let photoLine = photoCount > 1 ? "Merged from \(photoCount) photo angles." : "Single photo angle."

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: """
                    You are a friendly family electronics teacher helping kids and parents understand ANY unknown real-world circuit board.
                    \(level.promptGuidance)
                    Use the detected silkscreen designators, chip part markings (even unfamiliar ones), functional zones, and LiDAR board dimensions to infer what the whole board does.
                    Only refer to parts that were actually detected. Never invent part numbers.
                    """)
                let prompt = """
                Board Profile Context:
                - \(lidarLine)
                - \(photoLine)

                Detected PCB components:
                \(partsList.isEmpty ? "No silkscreen labels read yet — explain how to get a clearer close-up." : partsList)

                Explain what this whole circuit board likely does and how power or signals move through these parts.
                """
                let response = try await session.respond(to: prompt, generating: GeneratedBoardSummary.self)
                let gen = response.content
                self.summary = BoardSummaryResult(
                    deviceGuess: gen.deviceGuess,
                    wholeBoardStory: gen.wholeBoardStory,
                    signalFlow: gen.signalFlow,
                    safetyNote: hvWarning,
                    engineUsed: "Apple Intelligence (On-Device)"
                )
                return
            } catch {
                // Fall through cleanly to deterministic offline explainer
            }
        }
        #endif

        self.summary = Self.offlineSummary(
            components: components,
            lidar: lidar,
            level: level,
            safetyNote: hvWarning
        )
    }

    public func ask(question: String, profile: BoardProfile, level: LearningLevel) async {
        await ask(
            question: question,
            components: profile.components,
            lidar: profile.lidar,
            level: level
        )
    }

    public func ask(
        question: String,
        components: [DetectedComponent],
        lidar: LiDARMeasurement? = nil,
        level: LearningLevel
    ) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isThinking = true
        defer { isThinking = false }

        let partsList = components.map { c in
            "\(c.designator): \(c.category.rawValue)\(c.partMarking.map { " (\($0))" } ?? "")\(c.partHint.map { " - \($0)" } ?? "")"
        }.joined(separator: "; ")
        let lidarContext = lidar?.promptDescription ?? "LiDAR dimensions not measured."

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: """
                    You are a patient family electronics teacher answering questions about a scanned PCB.
                    \(level.promptGuidance)
                    Physical measurements: \(lidarContext)
                    Detected parts on this board: \(partsList).
                    Keep answers concise (2-4 sentences) and include safety reminders for mains power parts.
                    """)
                let response = try await session.respond(to: trimmed)
                chatTurns.append(ChatTurn(question: trimmed, answer: response.content))
                return
            } catch {
                // Fall back cleanly
            }
        }
        #endif

        // Deterministic offline fallback so Q&A still works without Apple Intelligence enabled
        let upper = trimmed.uppercased()
        if let hit = components.first(where: { upper.contains($0.designator) || ($0.partMarking != nil && upper.contains($0.partMarking!)) }) {
            let detail = hit.partHint ?? hit.category.kidAnalogy
            chatTurns.append(ChatTurn(
                question: trimmed,
                answer: "\(hit.displayTitle) is a \(hit.category.rawValue.lowercased()) in the \(hit.category.functionalZone) zone. \(detail)"
            ))
        } else if upper.contains("SIZE") || upper.contains("BIG") || upper.contains("LIDAR") || upper.contains("MM") {
            let sizeAnswer = lidar?.promptDescription ?? "Tap the LiDAR button on the camera view to measure this board's width, height, and component height in millimeters."
            chatTurns.append(ChatTurn(question: trimmed, answer: sizeAnswer))
        } else {
            chatTurns.append(ChatTurn(
                question: trimmed,
                answer: "This board profile has \(components.count) mapped parts (\(components.prefix(8).map(\.designator).joined(separator: ", "))). Enable Apple Intelligence on iOS 26+ for free-form Q&A, or tap any part chip above to inspect what it does."
            ))
        }
    }

    private static func offlineSummary(
        components: [DetectedComponent],
        lidar: LiDARMeasurement?,
        level: LearningLevel,
        safetyNote: String?
    ) -> BoardSummaryResult {
        let hasPowerIC = components.contains {
            ($0.partHint ?? "").lowercased().contains("power")
                || ($0.partHint ?? "").lowercased().contains("regulator")
                || ($0.partHint ?? "").lowercased().contains("buck")
                || $0.category == .transformer
        }
        let hasMCU = components.contains {
            let h = ($0.partHint ?? "").lowercased()
            return h.contains("microcontroller") || h.contains("mcu") || h.contains("esp") || h.contains("stm32")
        }
        let hasRelay = components.contains { $0.category == .relay }
        let hasSensor = components.contains { $0.category == .sensor }
        let hasAudio = components.contains { $0.category == .speaker }
        let hasMotor = components.contains { ($0.partHint ?? "").lowercased().contains("motor") || ($0.partHint ?? "").lowercased().contains("driver") }

        let sizeNote = lidar.map { " LiDAR estimates it at ~\($0.estimatedWidthMM) × \($0.estimatedHeightMM) mm (\($0.maxComponentReliefMM) mm tallest part)." } ?? ""

        let guess: String
        let story: String
        if hasPowerIC && hasRelay {
            guess = "Power Supply & Relay Control Board"
            story = "This circuit board converts wall power into steady low-voltage DC using its switching IC, smooths the power with capacitors, and uses a relay to switch a bigger load on and off.\(sizeNote)"
        } else if hasMCU && hasMotor {
            guess = "Smart Motor Controller Board"
            story = "A microcontroller brain sends speed and direction commands to a motor driver stage while regulators and capacitors keep power clean.\(sizeNote)"
        } else if hasMCU && hasSensor {
            guess = "Microcontroller Sensor Board"
            story = "A tiny onboard computer reads signals from sensors and communicates or controls outputs across \(components.count) mapped components.\(sizeNote)"
        } else if hasMCU {
            guess = "Embedded Microcontroller Board"
            story = "This board centers on a programmable microcontroller IC supported by power conditioning, timing, and I/O connectors.\(sizeNote)"
        } else if hasAudio {
            guess = "Audio & Speaker Driver Board"
            story = "This circuit processes sound signals and drives a speaker or buzzer using amplifier and filtering components.\(sizeNote)"
        } else if hasPowerIC {
            guess = "Switching Power Supply Board"
            story = "This board steps voltage down safely using a switching or linear regulator IC and smooths the output with capacitors.\(sizeNote)"
        } else if !components.isEmpty {
            guess = "Custom Electronics Circuit Board"
            story = "Mapped \(components.count) components across this unknown board.\(sizeNote) Add another close-up photo angle to read tiny chip markings for a deeper identification."
        } else {
            guess = "Unmapped Circuit Board"
            story = "Move closer to silkscreen codes (like C3, R12, U1, IC5) or laser-etched chip tops and capture a sharp photo.\(sizeNote)"
        }

        let flow = components.prefix(6).map(\.designator).joined(separator: " -> ")
        return BoardSummaryResult(
            deviceGuess: guess,
            wholeBoardStory: story,
            signalFlow: flow.isEmpty ? "Capture a closer photo to map signal flow" : flow,
            safetyNote: safetyNote,
            engineUsed: "Offline Profile Decoder (\(level.rawValue))"
        )
    }
}
