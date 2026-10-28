// Device settings: in-ear detection, ear-tip fit test, find, case LED, personalised ANC, dual
// connection, codec, personal sound, Super Mic / mic mode / walkie-talkie, call transparency,
// long battery life mode and anti-leakage. Wire formats from the spec (§6.14-6.27), which cites
// ear-web's bluetooth_socket.js.
//
// Decisions where ear-web is ambiguous (spec §10):
//  - Ear-tip results are decoded per side; ear-web only checks the left bud for "not detected".
//  - Case LED records are matched by their LED id (1...5); a record with an id outside that
//    range falls back to its position, which is all ear-web uses.
//  - The dual-connection list's first two payload bytes and the top bit of each name length are
//    unknown; they are kept (`unknownHeader`, `nameLengthHighBit`) but have no effect.

// MARK: - Values

/// Which bud(s) a find/ring command addresses.
public enum RingTarget: Equatable, Sendable {
    /// Ear (1): one command rings both buds.
    case both
    case left
    case right
    /// Headphones / neckband (component 0x06).
    case single
}

public enum EarTipFit: Equatable, Sendable {
    case good
    /// Poor seal: adjust the bud or try another tip size.
    case adjust
    /// Bud not detected / not in the ear.
    case notDetected
    case unknown(UInt8)

    public init(wire: UInt8) {
        switch wire {
        case 0: self = .good
        case 1: self = .adjust
        case 2: self = .notDetected
        default: self = .unknown(wire)
        }
    }
}

public struct EarTipResult: Equatable, Sendable {
    public let left: EarTipFit
    public let right: EarTipFit

    public init(left: EarTipFit, right: EarTipFit) {
        self.left = left
        self.right = right
    }
}

public struct RGB: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Ear (1) case light colours, one per state. LED ids on the wire are 1...5 in this order.
public struct CaseLEDColours: Equatable, Sendable {
    public enum Slot: Int, CaseIterable, Sendable {
        case batteryLow = 1, batteryMid, batteryHigh, charging, fullyCharged

        public var name: String {
            switch self {
            case .batteryLow: "Low"
            case .batteryMid: "Mid"
            case .batteryHigh: "High"
            case .charging: "Charging"
            case .fullyCharged: "Full"
            }
        }
    }

    /// Indexed by `Slot.rawValue - 1`.
    public var colours: [RGB]

    public init(colours: [RGB]) {
        precondition(colours.count == Slot.allCases.count)
        self.colours = colours
    }

    public subscript(slot: Slot) -> RGB {
        get { colours[slot.rawValue - 1] }
        set { colours[slot.rawValue - 1] = newValue }
    }

    /// 0xF00D payload: count 5, then `[id, R, G, B]` for ids 1...5.
    public var payload: [UInt8] {
        var bytes: [UInt8] = [UInt8(Slot.allCases.count)]
        for slot in Slot.allCases {
            let colour = self[slot]
            bytes += [UInt8(slot.rawValue), colour.red, colour.green, colour.blue]
        }
        return bytes
    }

    /// Decodes a 0x4017 reply: count, then 4-byte `[ledId, R, G, B]` records.
    public init?(payload p: [UInt8]) {
        guard let count = p.first, count > 0 else { return nil }
        var colours = [RGB](repeating: RGB(0, 0, 0), count: Slot.allCases.count)
        var seen = 0
        for index in 0..<Int(count) {
            let start = 1 + index * 4
            guard start + 4 <= p.count else { break }
            let id = Int(p[start])
            let slot = Slot(rawValue: id)?.rawValue ?? (index + 1)
            guard (1...Slot.allCases.count).contains(slot) else { continue }
            colours[slot - 1] = RGB(p[start + 1], p[start + 2], p[start + 3])
            seen += 1
        }
        guard seen > 0 else { return nil }
        self.colours = colours
    }
}

public struct DualConnectionDevice: Equatable, Sendable {
    /// Six bytes in display order, sent back unchanged in connect/disconnect.
    public let mac: [UInt8]
    public let name: String
    /// The host on this link (flags high nibble).
    public let isSelf: Bool
    public var isConnected: Bool
    /// Top bit of the name-length byte; meaning unknown.
    public let nameLengthHighBit: Bool

    public init(mac: [UInt8], name: String, isSelf: Bool, isConnected: Bool, nameLengthHighBit: Bool = false) {
        self.mac = mac
        self.name = name
        self.isSelf = isSelf
        self.isConnected = isConnected
        self.nameLengthHighBit = nameLengthHighBit
    }

    /// `AA-BB-CC-DD-EE-FF`, uppercase, as ear-web shows it.
    public var macString: String {
        mac.map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16, uppercase: true) }.joined(separator: "-")
    }
}

/// One page of the 0x4028 remembered-device list.
public struct DualConnectionPage: Equatable, Sendable {
    /// `p[0]`, `p[1]`: meaning unknown.
    public let unknownHeader: [UInt8]
    public let devices: [DualConnectionDevice]

    /// Payload: 2 unknown bytes, count, then per device `flags, mac[6], nameLen, name`.
    public init?(payload p: [UInt8]) {
        guard p.count >= 3 else { return nil }
        unknownHeader = Array(p[0..<2])
        var devices: [DualConnectionDevice] = []
        var offset = 3
        for _ in 0..<Int(p[2]) {
            guard offset + 8 <= p.count else { break }
            let flags = p[offset]
            let lengthByte = p[offset + 7]
            let nameLength = Int(lengthByte & 0x7F)
            let nameEnd = min(offset + 8 + nameLength, p.count)
            devices.append(DualConnectionDevice(
                mac: Array(p[(offset + 1)..<(offset + 7)]),
                name: String(decoding: p[(offset + 8)..<nameEnd], as: UTF8.self),
                isSelf: flags & 0xF0 != 0,
                isConnected: flags & 0x0F != 0,
                nameLengthHighBit: lengthByte & 0x80 != 0))
            offset += 8 + nameLength
        }
        self.devices = devices
    }
}

public enum AudioCodec: UInt8, CaseIterable, Sendable {
    case aac = 0, lhdc = 1, ldac = 2

    public var name: String {
        switch self {
        case .aac: "AAC"
        case .lhdc: "LHDC"
        case .ldac: "LDAC"
        }
    }

    /// AAC always; LHDC with `highQualityAudio & 0x2`, LDAC with `& 0x4`.
    public static func available(highQualityAudio mask: Int) -> [AudioCodec] {
        allCases.filter {
            switch $0 {
            case .aac: true
            case .lhdc: mask & 0x2 != 0
            case .ldac: mask & 0x4 != 0
            }
        }
    }
}

public enum MicMode: UInt8, CaseIterable, Sendable {
    case natural = 0, voiceFocus = 1

    public var name: String {
        switch self {
        case .natural: "Natural"
        case .voiceFocus: "Voice focus"
        }
    }
}

public enum AntiLeakageMode: UInt8, CaseIterable, Sendable {
    case off = 0, callsOnly = 1, audioAndCalls = 2

    public var name: String {
        switch self {
        case .off: "Off"
        case .callsOnly: "Calls only"
        case .audioAndCalls: "Audio + calls"
        }
    }
}

// MARK: - Requests

extension Request {
    private static func flag(_ on: Bool) -> UInt8 { on ? 0x01 : 0x00 }

    public static let readInEarDetection = Request(0xC00E)
    public static func setInEarDetection(_ on: Bool) -> Request { Request(0xF004, [0x01, 0x01, flag(on)]) }

    public static let startEarTipTest = Request(0xF014, [0x01])

    public static func ring(_ target: RingTarget, on: Bool) -> Request {
        switch target {
        case .both: Request(0xF002, [flag(on)])
        case .left: Request(0xF002, [0x02, flag(on)])
        case .right: Request(0xF002, [0x03, flag(on)])
        case .single: Request(0xF002, [0x06, flag(on)])
        }
    }

    public static let readCaseLED = Request(0xC017)
    public static func setCaseLED(_ colours: CaseLEDColours) -> Request { Request(0xF00D, colours.payload) }

    public static let readPersonalisedANC = Request(0xC020)
    public static func setPersonalisedANC(_ on: Bool) -> Request { Request(0xF011, [flag(on)]) }

    public static let readDualConnection = Request(0xC027)
    public static func setDualConnection(_ on: Bool) -> Request { Request(0xF01A, [flag(on)]) }
    /// `offset` is the number of devices already known.
    public static func readDualConnectionDevices(offset: Int) -> Request { Request(0xC028, [UInt8(offset & 0xFF)]) }
    public static func dualConnect(mac: [UInt8], connect: Bool) -> Request { Request(0xF01B, [flag(connect)] + mac) }

    public static let readCodec = Request(0xC029)
    /// The device restarts after this write.
    public static func setCodec(_ codec: AudioCodec) -> Request { Request(0xF01C, [codec.rawValue]) }

    public static let readMimi = Request(0xC022)
    public static func setMimi(_ on: Bool) -> Request { Request(0xF015, [flag(on)]) }
    public static let readAudiodo = Request(0xC05A)
    public static func setAudiodo(_ on: Bool) -> Request { Request(0xF05C, [flag(on)]) }

    public static let readSuperMic = Request(0xC05E)
    public static func setSuperMic(_ on: Bool) -> Request { Request(0xF05F, [flag(on)]) }
    public static let readMicMode = Request(0xC064)
    public static func setMicMode(_ mode: MicMode) -> Request { Request(0xF065, [mode.rawValue]) }
    public static let readWalkieTalkie = Request(0xC060)
    public static func setWalkieTalkie(_ on: Bool) -> Request { Request(0xF061, [flag(on)]) }
    public static let readCallTransparency = Request(0xC05F)
    public static func setCallTransparency(_ on: Bool) -> Request { Request(0xF060, [flag(on)]) }

    public static let readLongPowerMode = Request(0xC067)
    /// The device restarts after this write. Note the set id is not the read id + 0x3001.
    public static func setLongPowerMode(_ on: Bool) -> Request { Request(0xF068, [flag(on)]) }

    public static let readAntiLeakage = Request(0xC071)
    public static func setAntiLeakage(_ mode: AntiLeakageMode) -> Request { Request(0xF075, [mode.rawValue]) }
}

// MARK: - Messages

public enum SettingsMessage: Equatable, Sendable {
    case inEarDetection(Bool)
    case earTipResult(EarTipResult)
    case caseLED(CaseLEDColours)
    case personalisedANC(Bool)
    case dualConnectionEnabled(Bool)
    case dualConnectionPage(DualConnectionPage)
    /// 0xE00E: a remembered device connected or disconnected.
    case dualConnectionEvent(mac: [UInt8], connected: Bool)
    case codec(AudioCodec)
    case mimi(Bool)
    /// 0x405A reply.
    case audiodo(Bool)
    /// 0xE019 / 0x6019 push; only meaningful when the backend is Audiodo.
    case audiodoPush(Bool)
    case superMic(Bool)
    case micMode(MicMode)
    case walkieTalkie(Bool)
    case callTransparency(Bool)
    case longPowerMode(Bool)
    case antiLeakage(AntiLeakageMode)

    public init?(frame: Frame) {
        let p = frame.payload
        func bool(at index: Int = 0) -> Bool? { index < p.count ? p[index] == 1 : nil }

        switch frame.command {
        case 0x400E:
            guard let on = bool(at: 2) else { return nil }
            self = .inEarDetection(on)
        case 0xE00D:
            guard p.count >= 2 else { return nil }
            self = .earTipResult(EarTipResult(left: EarTipFit(wire: p[0]), right: EarTipFit(wire: p[1])))
        case 0x4017:
            guard let colours = CaseLEDColours(payload: p) else { return nil }
            self = .caseLED(colours)
        case 0x4020:
            guard let on = bool() else { return nil }
            self = .personalisedANC(on)
        case 0x4027:
            guard let on = bool() else { return nil }
            self = .dualConnectionEnabled(on)
        case 0x4028:
            guard let page = DualConnectionPage(payload: p) else { return nil }
            self = .dualConnectionPage(page)
        case 0xE00E:
            guard p.count >= 7 else { return nil }
            self = .dualConnectionEvent(mac: Array(p[1...6]), connected: p[0] == 1)
        case 0x4029:
            // ear-web treats a missing or out-of-range index as AAC.
            self = .codec(p.first.flatMap(AudioCodec.init(rawValue:)) ?? .aac)
        case 0x4022:
            guard let on = bool() else { return nil }
            self = .mimi(on)
        case 0x405A:
            guard let on = bool() else { return nil }
            self = .audiodo(on)
        case 0xE019, 0x6019:
            guard let on = bool() else { return nil }
            self = .audiodoPush(on)
        case 0x405E:
            guard let on = bool() else { return nil }
            self = .superMic(on)
        case 0x4064:
            guard let mode = p.first.flatMap(MicMode.init(rawValue:)) else { return nil }
            self = .micMode(mode)
        case 0x4060:
            guard let on = bool() else { return nil }
            self = .walkieTalkie(on)
        case 0x405F:
            guard let on = bool() else { return nil }
            self = .callTransparency(on)
        case 0x4067:
            guard let on = bool() else { return nil }
            self = .longPowerMode(on)
        case 0x4071:
            guard let mode = p.first.flatMap(AntiLeakageMode.init(rawValue:)) else { return nil }
            self = .antiLeakage(mode)
        default:
            return nil
        }
    }
}
