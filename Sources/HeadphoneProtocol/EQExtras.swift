// Advanced (parametric) EQ values, the B192 precision-driver EQ, bass enhance / ultra bass and
// flat EQ. Ported from ear-web's bluetooth_socket.js and advanced_eq.js (spec: gestures-eq.md
// §B.4-B.5, protocol.md §6.7-6.10).

import Foundation

// MARK: - Parametric bands

/// One peaking band of the advanced EQ: gain in dB, centre frequency in Hz, Q factor.
public struct ParametricBand: Equatable, Sendable {
    public var gain: Float
    public var frequency: Float
    public var q: Float
    /// Filter type as reported; writes always send 1 (peak).
    public var filterType: UInt8

    public init(gain: Float = 0, frequency: Float, q: Float = 1, filterType: UInt8 = 1) {
        self.gain = gain
        self.frequency = frequency
        self.q = q
        self.filterType = filterType
    }
}

/// The band packet shared by 0xF050 / 0x404D (main bands) and 0xF06D / 0x406D (precision driver):
/// `[profileIndex][bandCount][totalGain f32]` then 13 bytes per band
/// `[filterType][gain f32][frequency f32][Q f32]`, floats little-endian, no trailing padding.
public struct ParametricEQPacket: Equatable, Sendable {
    public var bands: [ParametricBand]
    public var totalGain: Float

    public init(bands: [ParametricBand], totalGain: Float) {
        self.bands = bands
        self.totalGain = totalGain
    }

    /// Write payload. The profile index is always written as 0 and every band as a peak filter.
    public var payload: [UInt8] {
        var bytes: [UInt8] = [0x00, UInt8(bands.count)] + Float32LE.bytes(totalGain)
        for band in bands {
            bytes.append(0x01)
            bytes += Float32LE.bytes(band.gain) + Float32LE.bytes(band.frequency) + Float32LE.bytes(band.q)
        }
        return bytes
    }

    /// Parses a 0x404D / 0x406D payload. Reads up to `bandCount` bands while 13 bytes remain.
    public init?(payload: [UInt8]) {
        guard payload.count >= 6 else { return nil }
        let count = Int(payload[1])
        var bands: [ParametricBand] = []
        var offset = 6
        while bands.count < count, offset + 13 <= payload.count {
            bands.append(ParametricBand(gain: Float32LE.value(payload, at: offset + 1),
                                        frequency: Float32LE.value(payload, at: offset + 5),
                                        q: Float32LE.value(payload, at: offset + 9),
                                        filterType: payload[offset]))
            offset += 13
        }
        self.init(bands: bands, totalGain: Float32LE.value(payload, at: 2))
    }
}

/// Band layouts, limits and gain rules of the advanced EQ editor.
public enum AdvancedEQLayout {
    public static let gainRange: ClosedRange<Float> = -6...6
    public static let gainStep: Float = 0.5
    public static let qRange: ClosedRange<Float> = 0.1...10

    /// Fixed 8-band layout (every advanced-EQ model except B192): default centre and allowed range.
    public static let fixedBands: [(center: Float, range: ClosedRange<Float>)] = [
        (55, 20...99), (110, 100...199), (220, 200...399), (440, 400...999),
        (1320, 1000...2999), (3300, 3000...5999), (6600, 6000...11999), (13200, 12000...20000),
    ]

    /// Flexible (B192 `supportMiddleEq`) main bands.
    public static let mainRange: ClosedRange<Float> = 20...20000
    public static let mainBandLimit = 1...8
    public static let mainDefaults: [Float] = [50, 250, 4000]
    /// Flexible precision-driver bands.
    public static let driverRange: ClosedRange<Float> = 5000...15000
    public static let driverBandLimit = 1...4
    public static let driverDefaults: [Float] = [8000]

    public static var fixedDefault: [ParametricBand] {
        fixedBands.map { ParametricBand(frequency: $0.center) }
    }

    public static func defaults(_ frequencies: [Float]) -> [ParametricBand] {
        frequencies.map { ParametricBand(frequency: $0) }
    }

    /// totalGain of a plain 0xF050 write: −max(0, gains). With no positive gain this is −0,
    /// encoded `00 00 00 80`, as ear-web sends it.
    public static func fixedTotalGain(_ bands: [ParametricBand]) -> Float {
        -max(0, bands.map(\.gain).max() ?? 0)
    }

    /// totalGain shared by the main and driver writes on B192. Firmware ≥ 1.0.1.46 (or unknown /
    /// unparseable) gets −trunc(peak), or +0 (`00 00 00 00`) when that is 0; older firmware
    /// gets min(0, 6 − peak).
    public static func dualTotalGain(main: [ParametricBand], driver: [ParametricBand], firmware: String?) -> Float {
        let peak = max(0, (main + driver).map(\.gain).max() ?? 0)
        var native = true
        if let firmware, !firmware.isEmpty, let order = FirmwareVersion.compare(firmware, "1.0.1.46") {
            native = order >= 0
        }
        if native {
            let whole = peak.rounded(.towardZero)
            return whole > 0 ? -whole : 0
        }
        return min(0, 6 - peak)
    }

    /// Frequency for an added band: the rounded geometric mean of the widest gap (by ratio)
    /// between the range edges and the existing band frequencies.
    public static func insertionFrequency(existing: [Float], in range: ClosedRange<Float>) -> Float {
        let edges = [range.lowerBound] + existing.sorted() + [range.upperBound]
        var best = (ratio: Float(0), frequency: (range.lowerBound * range.upperBound).squareRoot())
        for index in 0..<(edges.count - 1) where edges[index] > 0 {
            let ratio = edges[index + 1] / edges[index]
            if ratio > best.ratio {
                best = (ratio, (edges[index] * edges[index + 1]).squareRoot().rounded())
            }
        }
        return best.frequency
    }

    /// Position 0…1 of `frequency` on a logarithmic slider over `range`.
    public static func logPosition(of frequency: Float, in range: ClosedRange<Float>) -> Double {
        let value = log(Double(frequency) / Double(range.lowerBound)) / log(Double(range.upperBound) / Double(range.lowerBound))
        return min(max(value, 0), 1)
    }

    /// Inverse of `logPosition`, in 1000 steps and rounded to whole Hz as ear-web does.
    public static func frequency(atLogPosition position: Double, in range: ClosedRange<Float>) -> Float {
        let step = (min(max(position, 0), 1) * 1000).rounded() / 1000
        let lower = Double(range.lowerBound), upper = Double(range.upperBound)
        return Float((lower * pow(upper / lower, step)).rounded())
    }
}

// MARK: - Bass

/// How bass enhance / ultra bass levels map to the wire byte.
public enum BassScheme: Sendable {
    /// UI levels 1…5, wire = level × 2.
    case fiveStage
    /// UI levels 0…2, wire 0 / 5 / 10; picking 0 also turns bass off.
    case threeStage

    public init(threeStage: Bool) {
        self = threeStage ? .threeStage : .fiveStage
    }

    public var levels: ClosedRange<Int> {
        self == .fiveStage ? 1...5 : 0...2
    }

    private static let threeStageWire: [UInt8] = [0, 5, 10]

    public func wire(level: Int) -> UInt8 {
        switch self {
        case .fiveStage: UInt8(min(max(level, 1), 5) * 2)
        case .threeStage: Self.threeStageWire.indices.contains(level) ? Self.threeStageWire[level] : 0
        }
    }

    /// UI level for a reported wire byte, or nil if it maps to none (ear-web leaves the UI as is).
    public func level(wire: UInt8) -> Int? {
        switch self {
        case .fiveStage: wire % 2 == 0 && (2...10).contains(wire) ? Int(wire / 2) : nil
        case .threeStage: Self.threeStageWire.firstIndex(of: wire)
        }
    }
}

// MARK: - Requests and replies

extension Request {
    /// 0xC04D with profile index 0xFF (current).
    public static let readAdvancedEQValues = Request(0xC04D, [0xFF])
    public static let readPrecisionDriverMode = Request(0xC06C)
    public static let enablePrecisionDriverMode = Request(0xF06C, [0x01])
    public static let readPrecisionDriverValues = Request(0xC06D, [0xFF])
    public static let readBass = Request(0xC04E)
    public static let readFlatEQ = Request(0xC068)

    /// Fixed-layout write: main bands only, totalGain = −max(0, gains).
    public static func setAdvancedEQValues(_ bands: [ParametricBand]) -> Request {
        Request(0xF050, ParametricEQPacket(bands: bands, totalGain: AdvancedEQLayout.fixedTotalGain(bands)).payload)
    }

    /// B192 write: main bands (0xF050) then precision-driver bands (0xF06D) with a shared totalGain.
    /// Driver frequencies are clamped to 5–15 kHz.
    public static func setAdvancedAndPrecisionEQ(main: [ParametricBand], driver: [ParametricBand],
                                                 firmware: String?) -> [Request] {
        let range = AdvancedEQLayout.driverRange
        let clamped = driver.map { band in
            var band = band
            band.frequency = min(max(band.frequency, range.lowerBound), range.upperBound)
            return band
        }
        let total = AdvancedEQLayout.dualTotalGain(main: main, driver: clamped, firmware: firmware)
        return [
            Request(0xF050, ParametricEQPacket(bands: main, totalGain: total).payload),
            Request(0xF06D, ParametricEQPacket(bands: clamped, totalGain: total).payload),
        ]
    }

    /// 0xF051 `[enabled, wireLevel]`. The level byte is sent even when disabled.
    public static func setBass(enabled: Bool, wireLevel: UInt8) -> Request {
        Request(0xF051, [enabled ? 0x01 : 0x00, wireLevel])
    }
}

public enum EQExtraMessage: Equatable, Sendable {
    case advancedEQValues(ParametricEQPacket)
    case precisionDriverMode(Bool)
    case precisionDriverValues(ParametricEQPacket)
    case bass(enabled: Bool, wireLevel: UInt8)
    case flatEQ(Bool)

    public init?(frame: Frame) {
        let p = frame.payload
        switch frame.command {
        case 0x404D:
            guard let packet = ParametricEQPacket(payload: p) else { return nil }
            self = .advancedEQValues(packet)
        case 0x406D:
            guard let packet = ParametricEQPacket(payload: p) else { return nil }
            self = .precisionDriverValues(packet)
        case 0x406C:
            self = .precisionDriverMode(p.first == 1)
        case 0x404E:
            guard p.count >= 2 else { return nil }
            self = .bass(enabled: p[0] == 1, wireLevel: p[1])
        case 0x4068, 0xE01C, 0x601C:
            self = .flatEQ(p.first == 1)
        default:
            return nil
        }
    }
}
