import Foundation
import SwiftUI

public enum LearningLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case kid = "Kid (10)"
    case teen = "Teen"
    case engineer = "Engineer"

    public var id: String { rawValue }

    public var promptGuidance: String {
        switch self {
        case .kid:
            return "Explain like I am 10 years old using everyday analogies (water pipes, switches, tiny brains). Keep sentences short and fun."
        case .teen:
            return "Explain for a curious high-schooler learning electronics. Use clear terms like voltage, current, and switching, and explain why each part is there."
        case .engineer:
            return "Explain concisely at an electronics engineering level: topology, power rails, signal paths, and likely failure modes."
        }
    }
}

public enum ComponentCategory: String, Codable, Sendable {
    case resistor = "Resistor"
    case capacitor = "Capacitor"
    case ic = "Integrated Circuit"
    case relay = "Relay"
    case diode = "Diode"
    case transistor = "Transistor"
    case inductor = "Inductor"
    case fuse = "Fuse"
    case connector = "Connector"
    case crystal = "Crystal / Clock"
    case led = "LED"
    case transformer = "Transformer"
    case switchPart = "Switch / Button"
    case testPoint = "Test Point"
    case protection = "Surge Protection"
    case unknown = "Component"

    public var color: Color {
        switch self {
        case .ic: return Color(red: 0.22, green: 0.74, blue: 0.97)
        case .capacitor: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .resistor: return Color(red: 0.64, green: 0.89, blue: 0.36)
        case .relay, .fuse, .transformer, .protection: return Color(red: 0.94, green: 0.33, blue: 0.25)
        case .diode, .led: return Color(red: 0.75, green: 0.52, blue: 0.99)
        case .transistor: return Color(red: 0.18, green: 0.83, blue: 0.75)
        case .connector, .testPoint: return Color(red: 0.82, green: 0.86, blue: 0.91)
        default: return Color(red: 0.58, green: 0.64, blue: 0.72)
        }
    }

    public var kidAnalogy: String {
        switch self {
        case .resistor: return "A narrow pipe that slows down electricity so delicate parts don't burn out."
        case .capacitor: return "A tiny rechargeable water tank that smooths out bumps in power."
        case .ic: return "A miniature brain or specialist chip with thousands of microscopic circuits inside."
        case .relay: return "An electrically controlled light switch that lets a tiny signal turn big power on or off."
        case .diode: return "A one-way valve that only lets electricity flow in a single direction."
        case .transistor: return "A super-fast electronic valve that switches or boosts signals millions of times a second."
        case .inductor: return "A coil of wire that stores energy in a magnetic field to filter or step voltage."
        case .fuse: return "A sacrificial safety wire that melts first if too much power rushes in."
        case .connector: return "A plug or socket where wires bring power or signals onto the board."
        case .crystal: return "A tiny vibrating quartz heartbeat that keeps every chip ticking in sync."
        case .led: return "A tiny light bulb that glows when current flows through it the right way."
        case .transformer: return "Two magnetic coils that safely step high wall voltage down to low voltage."
        case .switchPart: return "A button or toggle that opens or closes a circuit when pressed."
        case .testPoint: return "A metal pad engineers touch with a meter to check if the board is healthy."
        case .protection: return "A lightning guard that absorbs sudden voltage spikes from the wall."
        case .unknown: return "An electronic component labeled on the circuit board."
        }
    }
}

public struct DetectedComponent: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(designator)-\(Int(boxX * 1000))-\(Int(boxY * 1000))" }
    public let designator: String
    public let category: ComponentCategory
    public let partMarking: String?
    public let partHint: String?
    /// Normalized Vision coordinates (0..1, origin bottom-left).
    public let boxX: Double
    public let boxY: Double
    public let boxW: Double
    public let boxH: Double

    public var displayTitle: String {
        if let marking = partMarking, !marking.isEmpty {
            return "\(designator) · \(marking)"
        }
        return "\(designator) · \(category.rawValue)"
    }
}

public enum DesignatorCatalog {
    /// Longest prefix first so "IC" beats "I", "RY" beats "R", "LED" beats "L", "TP" beats "T".
    private static let prefixMap: [(String, ComponentCategory)] = [
        ("MOV", .protection), ("TVS", .protection), ("ESD", .protection),
        ("LED", .led), ("PTC", .fuse), ("NTC", .resistor),
        ("IC", .ic), ("RY", .relay), ("RL", .relay), ("CR", .diode),
        ("CN", .connector), ("CON", .connector), ("TP", .testPoint),
        ("SW", .switchPart), ("FB", .inductor), ("VR", .resistor),
        ("RV", .resistor), ("DS", .led), ("BT", .connector), ("TR", .transformer),
        ("U", .ic), ("C", .capacitor), ("R", .resistor), ("D", .diode),
        ("Q", .transistor), ("L", .inductor), ("F", .fuse), ("J", .connector),
        ("K", .relay), ("T", .transformer), ("X", .crystal), ("Y", .crystal),
        ("P", .connector), ("S", .switchPart),
    ]

    private static let knownChips: [(pattern: String, hint: String, mainsRelated: Bool)] = [
        ("MIP290", "Panasonic MIP290 off-line AC-DC switching power supply IC", true),
        ("MIP2", "Panasonic MIP-series AC-DC switching regulator IC", true),
        ("TNY2", "Power Integrations TinySwitch AC-DC switching power IC", true),
        ("LNK3", "Power Integrations LinkSwitch AC-DC power regulator IC", true),
        ("PC817", "Optocoupler isolating high-voltage mains from low-voltage logic", true),
        ("EL817", "Optocoupler isolating high-voltage mains from low-voltage logic", true),
        ("LM7805", "5V linear voltage regulator", false),
        ("LM7812", "12V linear voltage regulator", false),
        ("AMS1117", "Low-dropout (LDO) linear voltage regulator (often 3.3V or 5V)", false),
        ("LM358", "Dual operational amplifier (op-amp)", false),
        ("NE555", "Classic 555 timer IC", false),
        ("ULN2003", "7-channel Darlington transistor array (drives relays or motors)", false),
        ("ATMEGA", "Microchip AVR microcontroller (Arduino-family MCU)", false),
        ("ESP32", "Espressif Wi-Fi + Bluetooth microcontroller", false),
        ("RP2040", "Raspberry Pi dual-core ARM Cortex-M0+ microcontroller", false),
        ("RP2350", "Raspberry Pi RP2350 microcontroller", false),
        ("STM32", "STMicroelectronics ARM Cortex-M microcontroller", false),
    ]

    /// Parse a silkscreen token like "C3", "IC5", "RY2", "R104", "TP1".
    public static func classifyDesignator(_ raw: String) -> (designator: String, category: ComponentCategory)? {
        let cleaned = raw
            .uppercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count >= 2, cleaned.count <= 6 else { return nil }

        for (prefix, category) in prefixMap {
            if cleaned.hasPrefix(prefix) {
                let rest = cleaned.dropFirst(prefix.count)
                if !rest.isEmpty, rest.allSatisfy(\.isNumber), let num = Int(rest), num >= 0, num <= 9999 {
                    return (cleaned, category)
                }
            }
        }
        return nil
    }

    /// Match common laser-etched IC markings like "MIP290", "LM7805", "ESP32".
    public static func matchChipMarking(_ raw: String) -> (marking: String, hint: String, mainsRelated: Bool)? {
        let cleaned = raw
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count >= 4 else { return nil }
        for entry in knownChips {
            if cleaned.contains(entry.pattern) {
                return (entry.pattern, entry.hint, entry.mainsRelated)
            }
        }
        return nil
    }

    /// Returns true if the board shows signs of AC mains / high-voltage power circuitry.
    public static func hasHighVoltageClues(_ components: [DetectedComponent]) -> Bool {
        for c in components {
            if c.category == .relay || c.category == .fuse || c.category == .transformer || c.category == .protection {
                return true
            }
            if let m = c.partMarking, let hit = matchChipMarking(m), hit.mainsRelated {
                return true
            }
        }
        return false
    }

    /// Built-in demo board matching IMG_5248.PNG so the family can explore immediately.
    public static let demoBoard: [DetectedComponent] = [
        DetectedComponent(designator: "IC5", category: .ic, partMarking: "MIP290",
                          partHint: "Panasonic MIP290 off-line AC-DC switching power supply IC",
                          boxX: 0.48, boxY: 0.48, boxW: 0.22, boxH: 0.16),
        DetectedComponent(designator: "C3", category: .capacitor, partMarking: nil,
                          partHint: "Bulk electrolytic smoothing capacitor near the power stage",
                          boxX: 0.08, boxY: 0.42, boxW: 0.14, boxH: 0.10),
        DetectedComponent(designator: "C5", category: .capacitor, partMarking: nil,
                          partHint: "Secondary decoupling / filter capacitor",
                          boxX: 0.84, boxY: 0.56, boxW: 0.12, boxH: 0.10),
        DetectedComponent(designator: "RY2", category: .relay, partMarking: nil,
                          partHint: "Electromechanical relay footprint for switching a load",
                          boxX: 0.30, boxY: 0.36, boxW: 0.18, boxH: 0.10),
    ]
}
