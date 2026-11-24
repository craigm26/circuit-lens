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

public enum ComponentCategory: String, Codable, Sendable, CaseIterable {
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
    case sensor = "Sensor / Transducer"
    case battery = "Battery / Power Cell"
    case speaker = "Speaker / Buzzer"
    case unknown = "Component"

    public var functionalZone: String {
        switch self {
        case .fuse, .transformer, .protection, .battery: return "Power & Protection"
        case .ic, .crystal: return "Brains & Timing"
        case .relay, .transistor, .switchPart: return "Switching & Control"
        case .connector, .testPoint, .led, .speaker, .sensor: return "I/O, Ports & Sensors"
        case .resistor, .capacitor, .inductor, .diode, .unknown: return "Passives & Filtering"
        }
    }

    public var color: Color {
        switch self {
        case .ic: return Color(red: 0.22, green: 0.74, blue: 0.97)
        case .capacitor: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .resistor: return Color(red: 0.64, green: 0.89, blue: 0.36)
        case .relay, .fuse, .transformer, .protection: return Color(red: 0.94, green: 0.33, blue: 0.25)
        case .diode, .led: return Color(red: 0.75, green: 0.52, blue: 0.99)
        case .transistor: return Color(red: 0.18, green: 0.83, blue: 0.75)
        case .sensor, .speaker: return Color(red: 0.98, green: 0.45, blue: 0.68)
        case .battery: return Color(red: 0.16, green: 0.78, blue: 0.45)
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
        case .sensor: return "An electronic eye, ear, or thermometer that senses the outside world."
        case .battery: return "A stored-energy cell that keeps clocks or circuits alive without wall power."
        case .speaker: return "A tiny vibrating disc that turns electrical pulses into beeps or sound."
        case .unknown: return "An electronic component labeled on the circuit board."
        }
    }

    public var sfSymbol: String {
        switch self {
        case .resistor: return "waveform.path"
        case .capacitor: return "battery.75percent"
        case .ic: return "cpu"
        case .relay: return "arrow.triangle.swap"
        case .diode: return "arrowtriangle.right.fill"
        case .transistor: return "switch.2"
        case .inductor: return "wave.3.right"
        case .fuse: return "bolt.shield.fill"
        case .connector: return "cable.connector"
        case .crystal: return "metronome.fill"
        case .led: return "lightbulb.fill"
        case .transformer: return "bolt.horizontal.circle.fill"
        case .switchPart: return "button.programmable"
        case .testPoint: return "scope"
        case .protection: return "shield.lefthalf.filled.badge.checkmark"
        case .sensor: return "sensor.tag.radiowaves.forward.fill"
        case .battery: return "battery.100.bolt"
        case .speaker: return "speaker.wave.2.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    public var shortRole: String {
        switch self {
        case .resistor: return "Flow limiter"
        case .capacitor: return "Power tank"
        case .ic: return "Chip brain"
        case .relay: return "Heavy switch"
        case .diode: return "One-way valve"
        case .transistor: return "Fast switch"
        case .inductor: return "Magnetic coil"
        case .fuse: return "Safety fuse"
        case .connector: return "Wire port"
        case .crystal: return "Clock beat"
        case .led: return "Status light"
        case .transformer: return "Voltage step"
        case .switchPart: return "Button/switch"
        case .testPoint: return "Test pad"
        case .protection: return "Surge guard"
        case .sensor: return "Sensor"
        case .battery: return "Battery"
        case .speaker: return "Audio/buzzer"
        case .unknown: return "Board part"
        }
    }
}

public struct DetectedComponent: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(designator)-\(partMarking ?? "none")" }
    public let designator: String
    public let category: ComponentCategory
    public let partMarking: String?
    public let partHint: String?
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
    /// Comprehensive IEEE/IPC-2612 reference designator prefixes (longest first).
    private static let prefixMap: [(String, ComponentCategory)] = [
        ("MOV", .protection), ("TVS", .protection), ("ESD", .protection), ("VAR", .protection),
        ("LED", .led), ("PTC", .fuse), ("NTC", .sensor), ("BZR", .speaker),
        ("CON", .connector), ("USB", .connector), ("HDR", .connector), ("ANT", .connector),
        ("BAT", .battery), ("MIC", .sensor), ("SPK", .speaker), ("OPT", .ic),
        ("IC", .ic), ("RY", .relay), ("RL", .relay), ("CR", .diode), ("ZD", .diode),
        ("CN", .connector), ("JP", .connector), ("TP", .testPoint), ("SW", .switchPart),
        ("FB", .inductor), ("FL", .inductor), ("VR", .resistor), ("RV", .resistor),
        ("RN", .resistor), ("RT", .sensor), ("TH", .sensor), ("DS", .led),
        ("BT", .battery), ("BZ", .speaker), ("LS", .speaker), ("MK", .sensor),
        ("TR", .transformer), ("PS", .ic), ("AR", .ic),
        ("U", .ic), ("C", .capacitor), ("R", .resistor), ("D", .diode),
        ("Q", .transistor), ("L", .inductor), ("F", .fuse), ("J", .connector),
        ("K", .relay), ("T", .transformer), ("X", .crystal), ("Y", .crystal),
        ("P", .connector), ("S", .switchPart), ("B", .battery), ("Z", .diode),
    ]

    private static let knownChips: [(pattern: String, hint: String, mainsRelated: Bool)] = [
        // Mains & AC-DC Switching Power
        ("MIP290", "Panasonic MIP290 off-line AC-DC switching power supply IC", true),
        ("MIP2", "Panasonic MIP-series AC-DC switching regulator IC", true),
        ("TNY2", "Power Integrations TinySwitch AC-DC switching power IC", true),
        ("LNK3", "Power Integrations LinkSwitch AC-DC power regulator IC", true),
        ("TOP2", "Power Integrations TOPSwitch AC-DC power IC", true),
        ("VIPER", "STMicro VIPer off-line AC-DC converter IC", true),
        ("PC817", "Optocoupler isolating high-voltage mains from low-voltage logic", true),
        ("EL817", "Optocoupler isolating high-voltage mains from low-voltage logic", true),
        ("MOC30", "Triac driver optocoupler for AC load switching", true),
        ("BT13", "TRIAC for AC mains load switching", true),
        // DC-DC & Linear Regulators
        ("LM7805", "5V linear voltage regulator", false),
        ("LM7812", "12V linear voltage regulator", false),
        ("LM317", "Adjustable linear voltage regulator", false),
        ("AMS1117", "Low-dropout (LDO) linear voltage regulator (often 3.3V or 5V)", false),
        ("TLV1117", "TI low-dropout (LDO) linear voltage regulator", false),
        ("LM2596", "Step-down (buck) switching DC-DC regulator", false),
        ("MP1584", "High-frequency step-down (buck) DC-DC converter", false),
        ("XL4015", "High-current step-down (buck) DC-DC converter", false),
        ("TPS54", "TI SWIFT step-down DC-DC buck converter", false),
        ("BQ24", "TI Li-Ion battery charger management IC", false),
        ("TP4056", "Single-cell Li-Ion battery charger IC", false),
        // Microcontrollers & SoCs
        ("ATMEGA", "Microchip AVR microcontroller (Arduino-family MCU)", false),
        ("ATTINY", "Microchip compact AVR microcontroller", false),
        ("ESP32", "Espressif Wi-Fi + Bluetooth microcontroller", false),
        ("ESP8266", "Espressif Wi-Fi microcontroller", false),
        ("RP2040", "Raspberry Pi dual-core ARM Cortex-M0+ microcontroller", false),
        ("RP2350", "Raspberry Pi RP2350 microcontroller", false),
        ("STM32", "STMicroelectronics ARM Cortex-M microcontroller", false),
        ("NRF52", "Nordic Semiconductor Bluetooth LE SoC", false),
        ("NRF53", "Nordic Semiconductor dual-core Bluetooth LE Audio SoC", false),
        ("PIC16", "Microchip PIC 8-bit microcontroller", false),
        ("PIC18", "Microchip PIC 8-bit microcontroller", false),
        ("SAMD21", "Microchip ARM Cortex-M0+ microcontroller", false),
        // USB, Serial, CAN, Memory & Drivers
        ("CH340", "WCH USB-to-UART serial bridge chip", false),
        ("CP210", "Silicon Labs USB-to-UART serial bridge chip", false),
        ("FT232", "FTDI USB-to-UART serial interface IC", false),
        ("MAX232", "RS-232 serial level shifter IC", false),
        ("MAX485", "RS-485 differential bus transceiver", false),
        ("MCP2515", "CAN bus controller IC", false),
        ("TJA1050", "High-speed CAN bus transceiver", false),
        ("W25Q", "Winbond SPI NOR Flash memory chip", false),
        ("AT24C", "I2C EEPROM non-volatile memory chip", false),
        ("ULN2003", "7-channel Darlington transistor array (drives relays or steppers)", false),
        ("L298", "Dual H-bridge DC/stepper motor driver", false),
        ("DRV88", "TI motor driver IC", false),
        ("TB6612", "Toshiba dual DC motor driver IC", false),
        ("PCA9685", "16-channel I2C PWM/servo controller IC", false),
        // Analog, Timers, Logic & Sensors
        ("LM358", "Dual operational amplifier (op-amp)", false),
        ("LM324", "Quad operational amplifier (op-amp)", false),
        ("NE555", "Classic 555 timer IC", false),
        ("74HC", "74-series high-speed CMOS digital logic IC", false),
        ("74LS", "74-series TTL digital logic IC", false),
        ("CD40", "4000-series CMOS digital logic IC", false),
        ("ADS1115", "16-bit I2C analog-to-digital converter (ADC)", false),
        ("BME280", "Bosch temperature, humidity & pressure sensor", false),
        ("MPU6050", "6-axis gyroscope + accelerometer IMU", false),
    ]

    public static func classifyDesignator(_ raw: String) -> (designator: String, category: ComponentCategory)? {
        let cleaned = raw
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count >= 2, cleaned.count <= 8 else { return nil }

        // Common silkscreen power rails, bus pins & board markings
        if let special = classifyRailOrBus(cleaned) {
            return special
        }

        // Standard IEEE/IPC-2612 reference designators (e.g. C3, IC5, RY2, R14A, U1B)
        for (prefix, category) in prefixMap {
            if cleaned.hasPrefix(prefix) {
                let rest = cleaned.dropFirst(prefix.count)
                guard !rest.isEmpty else { continue }
                // Allow digits optionally followed by a single unit suffix letter (e.g. U1A, C3B)
                let digits = rest.prefix(while: \.isNumber)
                let suffix = rest.dropFirst(digits.count)
                if !digits.isEmpty,
                   suffix.count <= 1,
                   (suffix.isEmpty || suffix.allSatisfy(\.isLetter)),
                   let num = Int(digits), num >= 0, num <= 9999 {
                    return (cleaned, category)
                }
            }
        }
        return nil
    }

    /// Recognize common PCB silkscreen power rails, buses, and component value markings.
    private static func classifyRailOrBus(_ token: String) -> (designator: String, category: ComponentCategory)? {
        let powerRails: Set<String> = [
            "GND", "AGND", "DGND", "PGND", "VCC", "VDD", "VSS", "VEE", "VIN", "VOUT",
            "VBUS", "VBAT", "3V3", "5V", "12V", "24V", "1V8", "3.3V", "PWR", "AC", "DC"
        ]
        if powerRails.contains(token) {
            return (token, .connector)
        }
        let busPins: Set<String> = [
            "TX", "RX", "TXD", "RXD", "SDA", "SCL", "MOSI", "MISO", "SCK", "SCLK",
            "CLK", "RST", "RESET", "BOOT", "PWM", "ADC", "DAC", "GPIO", "SWD", "SWDIO",
            "SWCLK", "CANH", "CANL", "USB", "HDMI", "ETH", "WIFI", "ANT", "LED", "BTN"
        ]
        if busPins.contains(token) {
            return (token, .connector)
        }
        // Component value silkscreen (e.g. 10UF, 100NF, 470UF, 10K, 16MHZ)
        if token.hasSuffix("UF") || token.hasSuffix("NF") || token.hasSuffix("PF") {
            let num = token.dropLast(2)
            if !num.isEmpty, num.allSatisfy({ $0.isNumber || $0 == "." }) {
                return (token, .capacitor)
            }
        }
        if token.hasSuffix("MHZ") || token.hasSuffix("KHZ") {
            let num = token.dropLast(3)
            if !num.isEmpty, num.allSatisfy({ $0.isNumber || $0 == "." }) {
                return (token, .crystal)
            }
        }
        return nil
    }

    /// Match either a known IC part number OR a plausible unknown laser-etched IC code (e.g. SN74HC595, BQ25895).
    public static func matchChipMarking(_ raw: String) -> (marking: String, hint: String?, mainsRelated: Bool)? {
        let cleaned = raw
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count >= 4, cleaned.count <= 14 else { return nil }

        for entry in knownChips {
            if cleaned.contains(entry.pattern) {
                return (cleaned, entry.hint, entry.mainsRelated)
            }
        }

        // Generic unknown chip part-number heuristic:
        // Starts with 1-4 letters, followed by 2+ digits, optionally trailing letters/digits
        // (ignores pure words like "JAPAN", "ROHS", "REV1", "2024").
        let ignoredPrefixes = ["REV", "VER", "PCB", "GND", "VCC", "VDD", "VSS", "ROHS", "MADE", "DATE", "PART", "MODEL"]
        if ignoredPrefixes.contains(where: { cleaned.hasPrefix($0) }) { return nil }
        if classifyDesignator(cleaned) != nil { return nil }

        let letters = cleaned.prefix(while: \.isLetter)
        let afterLetters = cleaned.dropFirst(letters.count)
        let digits = afterLetters.prefix(while: \.isNumber)
        if (2...4).contains(letters.count), digits.count >= 3 {
            return (cleaned, nil, false)
        }
        return nil
    }

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
