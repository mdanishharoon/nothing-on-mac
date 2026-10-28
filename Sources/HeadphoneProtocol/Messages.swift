// Core commands and messages. Reads use 0xC0xx, their replies 0x40xx; writes use 0xF0xx;
// unsolicited pushes use 0xE0xx / 0x60xx. Feature-specific protocol lives beside each feature.

public struct Request: Equatable, Sendable {
    public let command: UInt16
    public let payload: [UInt8]

    public init(_ command: UInt16, _ payload: [UInt8] = []) {
        self.command = command
        self.payload = payload
    }

    public static let readBattery = Request(0xC007)
    public static let readNoiseControl = Request(0xC01E)
    public static let readPresetEQ = Request(0xC01F)
    public static let readListeningMode = Request(0xC050)
    public static let readAdvancedEQStatus = Request(0xC04C)
    public static let readLowLatency = Request(0xC041)
    public static let readFirmware = Request(0xC042)
    public static let readCustomEQ = Request(0xC044)
    public static let readSpatialAudio = Request(0xC04F)

    public static func readEQ(_ family: EQFamily) -> Request {
        family == .preset ? readPresetEQ : readListeningMode
    }

    public static func setEQ(level: UInt8, family: EQFamily) -> Request {
        Request(family == .preset ? 0xF010 : 0xF01D, [level, 0x00])
    }

    public static func setAdvancedEQ(_ enabled: Bool) -> Request {
        Request(0xF04F, [enabled ? 0x01 : 0x00, 0x00])
    }

    public static func setNoiseControl(_ mode: NoiseControl) -> Request {
        Request(0xF00F, [0x01, mode.wireValue, 0x00])
    }

    public static func setLowLatency(_ enabled: Bool) -> Request {
        Request(0xF040, [enabled ? 0x01 : 0x02, 0x00])
    }

    public static func setCustomEQ(_ eq: CustomEQ, bands: CustomEQBands) -> Request {
        Request(0xF041, eq.payload(bands: bands))
    }

    public static func setSpatialAudio(_ mode: SpatialAudioMode) -> Request {
        Request(0xF052, [mode.wire.mode, mode.wire.head])
    }

    /// Device clock: seconds since 1970, big-endian.
    public static func setTime(epochSeconds: UInt32) -> Request {
        Request(0xF00A, [UInt8(epochSeconds >> 24), UInt8(epochSeconds >> 16 & 0xFF),
                         UInt8(epochSeconds >> 8 & 0xFF), UInt8(epochSeconds & 0xFF)])
    }
}

public enum DeviceMessage: Equatable, Sendable {
    case battery([BatteryReading])
    case noiseControl(NoiseControl)
    /// Reply to either EQ family (0x401F preset, 0x4050 listening mode).
    case eqLevel(UInt8)
    case advancedEQEnabled(Bool)
    case customEQ(CustomEQ)
    case spatialAudio(SpatialAudioMode)
    case lowLatency(Bool)
    case firmware(String)

    public init?(frame: Frame) {
        let p = frame.payload
        switch frame.command {
        case 0x4007, 0xE001:
            guard let count = p.first else { return nil }
            var readings: [BatteryReading] = []
            for i in 0..<Int(count) where 2 + i * 2 < p.count {
                let value = p[2 + i * 2]
                readings.append(BatteryReading(component: p[1 + i * 2], level: Int(value & 0x7F), isCharging: value & 0x80 != 0))
            }
            self = .battery(readings)
        case 0x401E, 0xE003, 0x6003:
            guard p.count >= 2, let mode = NoiseControl(wireValue: p[1]) else { return nil }
            self = .noiseControl(mode)
        case 0x401F, 0x4050:
            guard let level = p.first else { return nil }
            self = .eqLevel(level)
        case 0x404C:
            guard let value = p.first else { return nil }
            self = .advancedEQEnabled(value == 1)
        case 0x4044:
            guard let eq = CustomEQ(payload: p) else { return nil }
            self = .customEQ(eq)
        case 0x404F:
            guard p.count >= 2 else { return nil }
            self = .spatialAudio(SpatialAudioMode(wireMode: p[0], head: p[1]))
        case 0x4041:
            guard let value = p.first, value == 1 || value == 2 else { return nil }
            self = .lowLatency(value == 1)
        case 0x4042:
            self = .firmware(String(decoding: p.filter { $0 != 0 }, as: UTF8.self))
        default:
            return nil
        }
    }
}
