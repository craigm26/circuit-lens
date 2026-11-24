import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct BoardMatch: Equatable, Sendable {
    public let name: String
    public let family: String
    public let confidence: String
    public let oneLiner: String
    public let typicalVoltage: String
    public let searchQuery: String
}

public struct PartLookupCard: Equatable, Sendable {
    public let query: String
    public let title: String
    public let roleSummary: String
    public let howItWorks: String
    public let voltageAndSafety: String
    public let datasheetSearchURL: URL?
    public let digiKeySearchURL: URL?
    public let webSearchURL: URL?
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedPartCard {
    @Guide(description: "Clear friendly name of this electronic component or chip.")
    var title: String

    @Guide(description: "One sentence explaining what this part does on a circuit board.")
    var roleSummary: String

    @Guide(description: "2 sentences explaining how it works in simple terms and how to recognize it.")
    var howItWorks: String

    @Guide(description: "One short sentence about typical voltage and safety precautions.")
    var voltageAndSafety: String
}
#endif

public enum BoardLookupService {
    /// Identify known development boards, modules, or real-world PCB archetypes from detected symbols.
    public static func identifyBoard(components: [DetectedComponent]) -> BoardMatch? {
        guard !components.isEmpty else { return nil }
        let allTokens = Set(components.flatMap { c -> [String] in
            var arr = [c.designator.uppercased()]
            if let m = c.partMarking?.uppercased() { arr.append(m) }
            return arr
        })
        let allText = allTokens.joined(separator: " ")

        if allText.contains("ESP32") {
            return BoardMatch(
                name: "ESP32 Wi-Fi / Bluetooth Dev Board",
                family: "Espressif IoT Microcontroller",
                confidence: "High Match",
                oneLiner: "A miniature wireless computer with built-in Wi-Fi and Bluetooth that controls sensors, lights, and smart home gadgets.",
                typicalVoltage: "5V USB in -> 3.3V logic",
                searchQuery: "ESP32 DevKit pinout schematic"
            )
        }
        if allText.contains("RP2040") || allText.contains("RP2350") {
            return BoardMatch(
                name: "Raspberry Pi Pico / RP2xxx Board",
                family: "Raspberry Pi Microcontroller",
                confidence: "High Match",
                oneLiner: "A fast dual-core microcontroller board designed for robotics, LEDs, and hands-on electronics learning.",
                typicalVoltage: "5V USB in -> 3.3V logic",
                searchQuery: "Raspberry Pi Pico RP2040 pinout"
            )
        }
        if allText.contains("ATMEGA") || (allText.contains("CH340") && (allTokens.contains("TX") || allTokens.contains("RX"))) {
            return BoardMatch(
                name: "Arduino-Compatible Microcontroller Board",
                family: "AVR / Arduino Ecosystem",
                confidence: "High Match",
                oneLiner: "A classic beginner-friendly microcontroller board that runs C++ sketches to read buttons/sensors and drive motors or LEDs.",
                typicalVoltage: "5V logic (7–12V VIN)",
                searchQuery: "Arduino Uno ATmega328P pinout schematic"
            )
        }
        if allText.contains("STM32") {
            return BoardMatch(
                name: "STM32 ARM Controller Board",
                family: "STMicroelectronics ARM Cortex-M",
                confidence: "High Match",
                oneLiner: "An industrial-grade 32-bit ARM microcontroller board used in drones, robotics, and precision instruments.",
                typicalVoltage: "3.3V logic",
                searchQuery: "STM32 board pinout schematic"
            )
        }
        if allText.contains("MIP290") || allText.contains("MIP2") || allText.contains("TNY2") || allText.contains("LNK3") || allText.contains("VIPER") {
            let hasRelay = components.contains { $0.category == .relay }
            return BoardMatch(
                name: hasRelay ? "Appliance AC-DC Power & Relay Board" : "Off-Line Switching Power Supply PCB",
                family: "Mains Power Conversion",
                confidence: "High Match",
                oneLiner: hasRelay
                    ? "Converts AC wall electricity into low-voltage DC to run control logic, and uses relays to safely switch heaters, pumps, or motors."
                    : "Steps high AC wall voltage down to clean, regulated low-voltage DC power.",
                typicalVoltage: "120/240V AC Mains -> 5V/12V DC (UNPLUG FIRST)",
                searchQuery: allText.contains("MIP290") ? "MIP290 power supply circuit board datasheet" : "offline switching power supply PCB schematic"
            )
        }
        if allText.contains("TP4056") || allText.contains("BQ24") {
            return BoardMatch(
                name: "Lithium Battery Charger Module",
                family: "Li-Ion Power Management",
                confidence: "High Match",
                oneLiner: "Safely charges rechargeable 3.7V lithium-ion batteries from 5V USB power while protecting against overcharge.",
                typicalVoltage: "5V USB -> 4.2V Li-Ion",
                searchQuery: "TP4056 battery charger module schematic"
            )
        }
        if allText.contains("L298") || allText.contains("DRV88") || allText.contains("TB6612") {
            return BoardMatch(
                name: "DC / Stepper Motor Driver Board",
                family: "H-Bridge Power Stage",
                confidence: "High Match",
                oneLiner: "Takes tiny low-power signals from a microcontroller and amplifies them to spin motors forward, backward, and at variable speed.",
                typicalVoltage: "5V–24V Motor Power",
                searchQuery: "H-bridge motor driver PCB schematic"
            )
        }

        // Generic archetype identification for any unknown board
        let hasRelay = components.contains { $0.category == .relay }
        let hasFuseOrMov = components.contains { $0.category == .fuse || $0.category == .protection }
        let hasIC = components.contains { $0.category == .ic }
        let hasBus = !allTokens.isDisjoint(with: ["SDA", "SCL", "TX", "RX", "MOSI", "MISO", "GPIO", "SWD"])

        if hasRelay && hasFuseOrMov {
            return BoardMatch(
                name: "Mains Power & Relay Control PCB",
                family: "Power / Appliance Control",
                confidence: "Pattern Match",
                oneLiner: "Combines surge/fuse protection with relay switching to control high-power loads.",
                typicalVoltage: "Check markings — may carry mains AC",
                searchQuery: "relay power control PCB circuit"
            )
        }
        if hasBus && hasIC {
            return BoardMatch(
                name: "Digital Controller / Sensor Breakout",
                family: "Low-Voltage Embedded Logic",
                confidence: "Pattern Match",
                oneLiner: "Uses serial/I2C/SPI data lines to exchange sensor readings or commands with a host microcontroller.",
                typicalVoltage: "3.3V or 5V DC",
                searchQuery: (components.first(where: { $0.partMarking != nil })?.partMarking ?? "embedded sensor") + " datasheet"
            )
        }
        return nil
    }

    public static func buildSearchURLs(query: String) -> (datasheet: URL?, digikey: URL?, web: URL?) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let ds = URL(string: "https://www.alldatasheet.com/view.jsp?Searchword=\(encoded)")
        let dk = URL(string: "https://www.digikey.com/en/products/result?keywords=\(encoded)")
        let web = URL(string: "https://www.google.com/search?q=\(encoded)+datasheet+pinout")
        return (ds, dk, web)
    }

    /// Generate an instant mini-datasheet card for any detected part or chip marking.
    public static func lookupPart(component: DetectedComponent, level: LearningLevel) async -> PartLookupCard {
        let query = component.partMarking ?? "\(component.designator) \(component.category.rawValue)"
        let urls = buildSearchURLs(query: query)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: """
                    You are a friendly electronics reference guide creating a concise mini-datasheet card for a circuit board component.
                    \(level.promptGuidance)
                    Be honest if an unknown chip code isn't in memory — explain its silkscreen category and how to look up its datasheet.
                    """)
                let prompt = """
                Component: \(component.displayTitle)
                Category: \(component.category.rawValue) (\(component.category.functionalZone))
                Known Hint: \(component.partHint ?? "None")
                Create a helpful mini-datasheet card.
                """
                let resp = try await session.respond(to: prompt, generating: GeneratedPartCard.self)
                let g = resp.content
                return PartLookupCard(
                    query: query,
                    title: g.title,
                    roleSummary: g.roleSummary,
                    howItWorks: g.howItWorks,
                    voltageAndSafety: g.voltageAndSafety,
                    datasheetSearchURL: urls.datasheet,
                    digiKeySearchURL: urls.digikey,
                    webSearchURL: urls.web
                )
            } catch {
                // Fall back cleanly
            }
        }
        #endif

        return PartLookupCard(
            query: query,
            title: component.displayTitle,
            roleSummary: component.partHint ?? component.category.kidAnalogy,
            howItWorks: "Located in the \(component.category.functionalZone) zone. \(component.category.kidAnalogy)",
            voltageAndSafety: component.belongs(to: .safety)
                ? "Caution: This part is commonly on the high-voltage / mains side. Always unplug and let capacitors discharge before touching."
                : "Typically low-voltage signal or power conditioning. Tap DigiKey or AllDatasheet below for exact specs.",
            datasheetSearchURL: urls.datasheet,
            digiKeySearchURL: urls.digikey,
            webSearchURL: urls.web
        )
    }
}
