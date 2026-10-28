import Testing
@testable import HeadphoneProtocol

// Expected frames were computed with a separate Python port of ear-web's send()/crc16()
// (bluetooth_socket.js:31-73) from the payloads in spec §5.1 / §6.14-6.27, operation id 1.
// Parser inputs are hand-built payloads following the same sections.

private func frame(_ request: Request) -> String {
    var encoder = PacketEncoder()
    return hex(encoder.encode(request))
}

private func message(_ command: UInt16, _ payload: [UInt8]) -> SettingsMessage? {
    SettingsMessage(frame: Frame(command: command, operationID: 1, payload: payload, checksumValid: true))
}

private let mac: [UInt8] = [0xA4, 0xC1, 0x38, 0x5B, 0x22, 0x9F]

@Suite struct SettingsWrites {
    @Test func inEarAndEarTip() {
        #expect(frame(.readInEarDetection) == "5560010ec000000170de")
        #expect(frame(.setInEarDetection(true)) == "55600104f003000101010179a4")
        #expect(frame(.setInEarDetection(false)) == "55600104f0030001010100b864")
        #expect(frame(.startEarTipTest) == "55600114f0010001015de6")
    }

    @Test func ring() {
        #expect(frame(.ring(.both, on: true)) == "55600102f0010001015f10")
        #expect(frame(.ring(.both, on: false)) == "55600102f0010001009ed0")
        #expect(frame(.ring(.left, on: true)) == "55600102f00200010201d508")
        #expect(frame(.ring(.right, on: false)) == "55600102f002000103001558")
        #expect(frame(.ring(.single, on: true)) == "55600102f00200010601d7c8")
    }

    @Test func caseLED() {
        var colours = CaseLEDColours(colours: [RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0)])
        colours[.batteryLow] = RGB(0xFF, 0, 0)
        colours[.batteryMid] = RGB(0, 0xFF, 0)
        colours[.batteryHigh] = RGB(0, 0, 0xFF)
        colours[.charging] = RGB(0x12, 0x34, 0x56)
        colours[.fullyCharged] = RGB(0xFF, 0xFF, 0xFF)
        #expect(frame(.readCaseLED) == "55600117c00000016d1c")
        #expect(frame(.setCaseLED(colours)) == "5560010df01500010501ff00000200ff00030000ff0412345605ffffffeadc")
    }

    @Test func personalisedANC() {
        #expect(frame(.readPersonalisedANC) == "55600120c000000198d8")
        #expect(frame(.setPersonalisedANC(true)) == "55600111f0010001015db3")
    }

    @Test func dualConnection() {
        #expect(frame(.readDualConnection) == "55600127c00000012d18")
        #expect(frame(.setDualConnection(true)) == "5560011af0010001015cc8")
        #expect(frame(.readDualConnectionDevices(offset: 0)) == "55600128c001000100d91e")
        #expect(frame(.readDualConnectionDevices(offset: 3)) == "55600128c001000103991f")
        #expect(Request.readDualConnectionDevices(offset: 0x103).payload == [0x03])
        #expect(frame(.dualConnect(mac: mac, connect: true)) == "5560011bf007000101a4c1385b229ff01e")
        #expect(frame(.dualConnect(mac: mac, connect: false)) == "5560011bf007000100a4c1385b229fe0de")
    }

    @Test func codec() {
        #expect(frame(.readCodec) == "55600129c000000144d9")
        #expect(frame(.setCodec(.aac)) == "5560011cf0010001009d6e")
        #expect(frame(.setCodec(.lhdc)) == "5560011cf0010001015cae")
        #expect(frame(.setCodec(.ldac)) == "5560011cf0010001021caf")
    }

    @Test func personalSound() {
        #expect(frame(.readMimi) == "55600122c0000001e118")
        #expect(frame(.setMimi(true)) == "55600115f0010001015c37")
        #expect(frame(.readAudiodo) == "5560015ac00000014112")
        #expect(frame(.setAudiodo(false)) == "5560015cf00100010093ae")
    }

    @Test func microphoneAndCalls() {
        #expect(frame(.readSuperMic) == "5560015ec0000001b0d2")
        #expect(frame(.setSuperMic(true)) == "5560015ff001000101525d")
        #expect(frame(.readMicMode) == "55600164c000000168d7")
        #expect(frame(.setMicMode(.voiceFocus)) == "55600165f0010001015707")
        #expect(frame(.readWalkieTalkie) == "55600160c00000019917")
        #expect(frame(.setWalkieTalkie(true)) == "55600161f0010001015683")
        #expect(frame(.readCallTransparency) == "5560015fc00000018d12")
        #expect(frame(.setCallTransparency(false)) == "55600160f0010001009692")
    }

    @Test func longPowerAndAntiLeakage() {
        #expect(frame(.readLongPowerMode) == "55600167c00000012cd7")
        #expect(frame(.setLongPowerMode(true)) == "55600168f001000101561a")
        #expect(frame(.readAntiLeakage) == "55600171c00000016514")
        #expect(frame(.setAntiLeakage(.audioAndCalls)) == "55600175f0010001021596")
    }
}

@Suite struct SettingsParsing {
    @Test func inEarUsesThirdByte() {
        #expect(message(0x400E, [0x01, 0x01, 0x01]) == .inEarDetection(true))
        #expect(message(0x400E, [0x01, 0x01, 0x00]) == .inEarDetection(false))
        #expect(message(0x400E, [0x01, 0x00, 0x02]) == .inEarDetection(false))
        #expect(message(0x400E, [0x01]) == nil)
    }

    @Test func earTipResult() {
        #expect(message(0xE00D, [0x00, 0x01]) == .earTipResult(EarTipResult(left: .good, right: .adjust)))
        #expect(message(0xE00D, [0x02, 0x00]) == .earTipResult(EarTipResult(left: .notDetected, right: .good)))
        #expect(message(0xE00D, [0x01, 0x07]) == .earTipResult(EarTipResult(left: .adjust, right: .unknown(7))))
        #expect(message(0xE00D, [0x00]) == nil)
    }

    @Test func caseLEDByID() {
        let reply: [UInt8] = [0x05,
                              0x01, 0x10, 0x11, 0x12, 0x02, 0x20, 0x21, 0x22, 0x03, 0x30, 0x31, 0x32,
                              0x04, 0x40, 0x41, 0x42, 0x05, 0x50, 0x51, 0x52]
        guard case .caseLED(let colours)? = message(0x4017, reply) else { Issue.record("no parse"); return }
        #expect(colours[.batteryLow] == RGB(0x10, 0x11, 0x12))
        #expect(colours[.batteryHigh] == RGB(0x30, 0x31, 0x32))
        #expect(colours[.fullyCharged] == RGB(0x50, 0x51, 0x52))
        #expect(colours.payload == reply)

        // Records out of id order land on their id; an unknown id falls back to its position.
        let shuffled: [UInt8] = [0x02, 0x03, 0xAA, 0xBB, 0xCC, 0x00, 0x01, 0x02, 0x03]
        guard case .caseLED(let mixed)? = message(0x4017, shuffled) else { Issue.record("no parse"); return }
        #expect(mixed[.batteryHigh] == RGB(0xAA, 0xBB, 0xCC))
        #expect(mixed[.batteryMid] == RGB(0x01, 0x02, 0x03))
        #expect(message(0x4017, [0x00]) == nil)
    }

    @Test func toggles() {
        #expect(message(0x4020, [0x01]) == .personalisedANC(true))
        #expect(message(0x4027, [0x00]) == .dualConnectionEnabled(false))
        #expect(message(0x4022, [0x01]) == .mimi(true))
        #expect(message(0x405A, [0x01]) == .audiodo(true))
        #expect(message(0xE019, [0x00]) == .audiodoPush(false))
        #expect(message(0x6019, [0x01]) == .audiodoPush(true))
        #expect(message(0x405E, [0x01]) == .superMic(true))
        #expect(message(0x4060, [0x02]) == .walkieTalkie(false))
        #expect(message(0x405F, [0x01]) == .callTransparency(true))
        #expect(message(0x4067, [0x01]) == .longPowerMode(true))
        #expect(message(0x4067, []) == nil)
    }

    @Test func enums() {
        #expect(message(0x4029, [0x02]) == .codec(.ldac))
        #expect(message(0x4029, [0x01]) == .codec(.lhdc))
        #expect(message(0x4029, [0x09]) == .codec(.aac))
        #expect(message(0x4029, []) == .codec(.aac))
        #expect(message(0x4064, [0x00]) == .micMode(.natural))
        #expect(message(0x4064, [0x01]) == .micMode(.voiceFocus))
        #expect(message(0x4064, [0x05]) == nil)
        #expect(message(0x4071, [0x00]) == .antiLeakage(.off))
        #expect(message(0x4071, [0x02]) == .antiLeakage(.audioAndCalls))
        #expect(message(0x4071, [0x03]) == nil)
    }

    @Test func codecAvailability() {
        #expect(AudioCodec.available(highQualityAudio: 2) == [.aac, .lhdc])
        #expect(AudioCodec.available(highQualityAudio: 4) == [.aac, .ldac])
        #expect(AudioCodec.available(highQualityAudio: 7) == [.aac, .lhdc, .ldac])
        #expect(AudioCodec.available(highQualityAudio: 0) == [.aac])
    }

    @Test func dualConnectionList() {
        // p[0..1] unknown, count 2, then:
        //   flags 0x11 (self + connected), A4-C1-38-5B-22-9F, len 7 "MacBook"
        //   flags 0x00, 01-02-03-0A-0B-0C, len 0x86 (top bit + 6) "Café!" (é is two bytes)
        let payload: [UInt8] = [0x00, 0x05, 0x02,
                                0x11, 0xA4, 0xC1, 0x38, 0x5B, 0x22, 0x9F, 0x07,
                                0x4D, 0x61, 0x63, 0x42, 0x6F, 0x6F, 0x6B,
                                0x00, 0x01, 0x02, 0x03, 0x0A, 0x0B, 0x0C, 0x86,
                                0x43, 0x61, 0x66, 0xC3, 0xA9, 0x21]
        guard case .dualConnectionPage(let page)? = message(0x4028, payload) else { Issue.record("no parse"); return }
        #expect(page.unknownHeader == [0x00, 0x05])
        #expect(page.devices.count == 2)
        let mine = page.devices[0], other = page.devices[1]
        #expect(mine.mac == mac)
        #expect(mine.macString == "A4-C1-38-5B-22-9F")
        #expect(mine.name == "MacBook")
        #expect(mine.isSelf && mine.isConnected && !mine.nameLengthHighBit)
        #expect(other.macString == "01-02-03-0A-0B-0C")
        #expect(other.name == "Café!")
        #expect(!other.isSelf && !other.isConnected && other.nameLengthHighBit)
    }

    @Test func dualConnectionFlagsAndTruncation() {
        // Connected-only flags (low nibble), self-only flags (high nibble).
        let flags: [UInt8] = [0x00, 0x00, 0x02,
                              0x01, 1, 2, 3, 4, 5, 6, 0x00,
                              0x20, 7, 8, 9, 10, 11, 12, 0x00]
        guard case .dualConnectionPage(let page)? = message(0x4028, flags) else { Issue.record("no parse"); return }
        #expect(page.devices.map(\.isConnected) == [true, false])
        #expect(page.devices.map(\.isSelf) == [false, true])
        #expect(page.devices.map(\.name) == ["", ""])

        // Count claims 3 but only one full record header follows; the name is clipped to the payload.
        let short: [UInt8] = [0x00, 0x00, 0x03, 0x01, 1, 2, 3, 4, 5, 6, 0x05, 0x41, 0x42, 0x09, 0x09]
        guard case .dualConnectionPage(let clipped)? = message(0x4028, short) else { Issue.record("no parse"); return }
        #expect(clipped.devices.count == 1)
        #expect(clipped.devices[0].name == "AB\u{9}\u{9}")

        #expect(message(0x4028, [0x00, 0x00, 0x00]).map { _ in true } == true)
        #expect(message(0x4028, [0x00, 0x00]) == nil)
    }

    @Test func dualConnectionEvent() {
        #expect(message(0xE00E, [0x01] + mac) == .dualConnectionEvent(mac: mac, connected: true))
        #expect(message(0xE00E, [0x00] + mac) == .dualConnectionEvent(mac: mac, connected: false))
        #expect(message(0xE00E, [0x01] + mac.dropLast()) == nil)
    }

    @Test func ignoresOtherCommands() {
        #expect(message(0x4007, [0x01, 0x06, 0x40]) == nil)
        #expect(message(0x401E, [0x01, 0x01]) == nil)
    }
}
