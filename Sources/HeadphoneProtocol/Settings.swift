// Setting values shared across Nothing / CMF models. Wire values come from ear-web
// (bluetooth_socket.js, device_common.js, spatial_audio.js) via the spec in its port notes.

public struct BatteryReading: Equatable, Sendable {
    /// 0x02 left, 0x03 right, 0x04 case, 0x06 single-unit device.
    public let component: UInt8
    public let level: Int
    public let isCharging: Bool

    public init(component: UInt8, level: Int, isCharging: Bool) {
        self.component = component
        self.level = level
        self.isCharging = isCharging
    }

    public static let left: UInt8 = 0x02
    public static let right: UInt8 = 0x03
    public static let `case`: UInt8 = 0x04
    public static let headphones: UInt8 = 0x06
}

public enum ANCStrength: CaseIterable, Sendable {
    case high, mid, low, adaptive

    public var name: String {
        switch self {
        case .high: "High"
        case .mid: "Mid"
        case .low: "Low"
        case .adaptive: "Adaptive"
        }
    }

    /// Strengths enabled by a config `ancLevel` bitmask: 0x04 High + Low, 0x02 Mid, 0x08 Adaptive.
    public static func available(ancLevel: Int) -> [ANCStrength] {
        guard ancLevel & 0x04 != 0 else { return [] }
        return allCases.filter {
            switch $0 {
            case .high, .low: true
            case .mid: ancLevel & 0x02 != 0
            case .adaptive: ancLevel & 0x08 != 0
            }
        }
    }
}

public enum NoiseControl: Equatable, Sendable {
    case noiseCancelling(ANCStrength)
    case transparency
    case off

    public var wireValue: UInt8 {
        switch self {
        case .noiseCancelling(.high): 0x01
        case .noiseCancelling(.mid): 0x02
        case .noiseCancelling(.low): 0x03
        case .noiseCancelling(.adaptive): 0x04
        case .off: 0x05
        case .transparency: 0x07
        }
    }

    public init?(wireValue: UInt8) {
        switch wireValue {
        case 0x01: self = .noiseCancelling(.high)
        case 0x02: self = .noiseCancelling(.mid)
        case 0x03: self = .noiseCancelling(.low)
        case 0x04: self = .noiseCancelling(.adaptive)
        case 0x05: self = .off
        case 0x07: self = .transparency
        default: return nil
        }
    }
}

/// Frequency and Q of the three custom-EQ bands, from the model config's `customEQ`.
public struct CustomEQBands: Sendable {
    public let low: (frequency: Float, q: Float)
    public let peak: (frequency: Float, q: Float)
    public let high: (frequency: Float, q: Float)

    public init(low: (Float, Float), peak: (Float, Float), high: (Float, Float)) {
        self.low = low
        self.peak = peak
        self.high = high
    }
}

/// Three-band custom EQ, each band an integer gain in dB.
public struct CustomEQ: Equatable, Sendable {
    public var bass: Int
    public var mid: Int
    public var treble: Int

    public static let range = -6...6
    public static let flat = CustomEQ(bass: 0, mid: 0, treble: 0)

    public init(bass: Int, mid: Int, treble: Int) {
        self.bass = bass
        self.mid = mid
        self.treble = treble
    }

    private enum Filter: UInt8 {
        case lowShelf = 0, peak = 1, highShelf = 2
    }

    /// Payload for 0xF041: band count, total gain, then per band (filter, gain, frequency, Q) as
    /// little-endian Float32, then 3 zero bytes per band. Bands go mid, treble, bass on the wire.
    public func payload(bands: CustomEQBands) -> [UInt8] {
        let wire: [(Filter, Int, Float, Float)] = [
            (.peak, mid, bands.peak.frequency, bands.peak.q),
            (.highShelf, treble, bands.high.frequency, bands.high.q),
            (.lowShelf, bass, bands.low.frequency, bands.low.q),
        ]
        let maxGain = max(0, wire.map(\.1).max() ?? 0)
        var bytes: [UInt8] = [UInt8(wire.count)] + Float32LE.bytes(-Float(maxGain))
        for (filter, gain, frequency, q) in wire {
            bytes.append(filter.rawValue)
            bytes += Float32LE.bytes(Float(gain)) + Float32LE.bytes(frequency) + Float32LE.bytes(q)
        }
        bytes += [UInt8](repeating: 0, count: 3 * wire.count)
        return bytes
    }

    /// Reads band gains from a 0x4044 payload (same layout as `payload`), matching bands by filter type.
    public init?(payload: [UInt8]) {
        guard let count = payload.first, count >= 1 else { return nil }
        var gains: [Filter: Int] = [:]
        for index in 0..<Int(count) {
            let start = 5 + index * 13
            guard start + 5 <= payload.count, let filter = Filter(rawValue: payload[start]) else { continue }
            let value = Float32LE.value(payload, at: start + 1)
            guard value.isFinite else { continue }
            gains[filter] = Swift.min(Swift.max(Int(value.rounded()), Self.range.lowerBound), Self.range.upperBound)
        }
        guard !gains.isEmpty else { return nil }
        self.init(bass: gains[.lowShelf] ?? 0, mid: gains[.peak] ?? 0, treble: gains[.highShelf] ?? 0)
    }
}

public enum Float32LE {
    public static func bytes(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)]
    }

    public static func value(_ bytes: [UInt8], at offset: Int) -> Float {
        guard offset + 4 <= bytes.count else { return .nan }
        let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        return Float(bitPattern: bits)
    }
}

public enum SpatialAudioMode: CaseIterable, Sendable {
    case off, headTracked, fixed, concert, cinema, game

    public var name: String {
        switch self {
        case .off: "Off"
        case .headTracked: "Head tracked"
        case .fixed: "Fixed"
        case .concert: "Concert"
        case .cinema: "Cinema"
        case .game: "Game"
        }
    }

    /// Bit in the config's `spatialAudio` mask (0x04 is unused).
    var bit: Int {
        switch self {
        case .off: 0
        case .headTracked: 0x01
        case .fixed: 0x02
        case .concert: 0x08
        case .cinema: 0x10
        case .game: 0x20
        }
    }

    /// (mode, head tracking) bytes sent on the wire.
    public var wire: (mode: UInt8, head: UInt8) {
        switch self {
        case .off: (0, 0)
        case .headTracked: (1, 1)
        case .fixed: (1, 0)
        case .concert: (2, 0)
        case .cinema: (3, 0)
        case .game: (4, 0)
        }
    }

    /// Off plus every mode in the bitmask, in a stable order.
    public static func available(mask: Int) -> [SpatialAudioMode] {
        allCases.filter { $0 == .off || mask & $0.bit != 0 }
    }

    /// Decodes a 0x404F reply. The head byte only matters for mode 1 (some models send junk there).
    public init(wireMode: UInt8, head: UInt8) {
        switch wireMode {
        case 0: self = .off
        case 1: self = head == 1 ? .headTracked : .fixed
        case 2: self = .concert
        case 3: self = .cinema
        case 4: self = .game
        default: self = .off
        }
    }
}
