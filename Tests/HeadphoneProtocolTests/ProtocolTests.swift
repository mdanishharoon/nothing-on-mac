import Foundation
import Testing
@testable import HeadphoneProtocol

// Expected bytes were generated from ear-web's send()/crc16()/createEQPacket() logic.

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }.joined()
}

func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        out.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return out
}

/// Repo Resources folder, for tests that use the bundled data files.
let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources")

let headphoneProBands = CustomEQBands(low: (140, 0.8), peak: (980, 0.7), high: (3500, 1.0))

@Suite struct Encoding {
    @Test func matchesEarWebPackets() {
        var encoder = PacketEncoder()
        #expect(hex(encoder.encode(.readBattery)) == "55600107c0000001acdf")
        #expect(hex(encoder.encode(.setNoiseControl(.noiseCancelling(.high)))) == "5560010ff0030002010100f993")
        #expect(hex(encoder.encode(.setEQ(level: 3, family: .listeningMode))) == "5560011df002000303005a59")
        #expect(hex(encoder.encode(.setSpatialAudio(.concert))) == "55600152f0020004020054cc")
        #expect(hex(encoder.encode(.setLowLatency(true))) == "55600140f0020005010037fd")
        #expect(hex(encoder.encode(.setCustomEQ(CustomEQ(bass: 4, mid: 2, treble: -3), bands: headphoneProBands))) ==
            "55600141f035000603000080c00100000040000075443333333f02000040c000c05a450000803f000000804000000c43cdcc4c3f000000000000000000db2b")
    }

    @Test func flatCustomEQEncodesNegativeZeroTotalGain() {
        #expect(Array(CustomEQ.flat.payload(bands: headphoneProBands)[1...4]) == [0x00, 0x00, 0x00, 0x80])
    }

    @Test func operationIDWrapsAfter250() {
        var encoder = PacketEncoder()
        for _ in 0..<250 { _ = encoder.encode(.readBattery) }
        #expect(encoder.operationID == 250)
        _ = encoder.encode(.readBattery)
        #expect(encoder.operationID == 1)
    }

    @Test func timeIsBigEndian() {
        #expect(Request.setTime(epochSeconds: 0x6543_2100).payload == [0x65, 0x43, 0x21, 0x00])
    }
}

@Suite struct Parsing {
    @Test func splitsCoalescedFramesAndSkipsNoise() {
        var encoder = PacketEncoder()
        let a = encoder.encode(Request(0x4050, [0x03, 0x00]))
        let b = encoder.encode(Request(0x401E, [0x01, 0x07, 0x00]))
        var parser = FrameParser()
        let frames = parser.append([0x00, 0x12] + a + b)
        #expect(frames.count == 2)
        #expect(frames.allSatisfy { $0.checksumValid })
        #expect(DeviceMessage(frame: frames[0]) == .eqLevel(3))
        #expect(DeviceMessage(frame: frames[1]) == .noiseControl(.transparency))
    }

    @Test func reassemblesSplitFrame() {
        var encoder = PacketEncoder()
        let packet = encoder.encode(Request(0x4041, [0x01]))
        var parser = FrameParser()
        #expect(parser.append(Array(packet.prefix(5))).isEmpty)
        let frames = parser.append(Array(packet.dropFirst(5)))
        #expect(frames.count == 1)
        #expect(DeviceMessage(frame: frames[0]) == .lowLatency(true))
    }

    @Test func acceptsFrameWithoutChecksum() {
        var parser = FrameParser()
        let frames = parser.append([0x55, 0x60, 0x01, 0x50, 0x40, 0x02, 0x00, 0x01, 0x06, 0x00])
        #expect(frames.count == 1)
        #expect(frames[0].checksumValid == false)
        #expect(DeviceMessage(frame: frames[0]) == .eqLevel(6))
    }
}

@Suite struct Decoding {
    private func message(_ command: UInt16, _ payload: [UInt8]) -> DeviceMessage? {
        DeviceMessage(frame: Frame(command: command, operationID: 1, payload: payload, checksumValid: true))
    }

    @Test func battery() {
        #expect(message(0x4007, [0x01, 0x06, 0x80 | 72]) ==
            .battery([BatteryReading(component: 0x06, level: 72, isCharging: true)]))
        #expect(message(0xE001, [0x03, 0x02, 40, 0x03, 41, 0x04, 0x80 | 90]) == .battery([
            BatteryReading(component: 0x02, level: 40, isCharging: false),
            BatteryReading(component: 0x03, level: 41, isCharging: false),
            BatteryReading(component: 0x04, level: 90, isCharging: true),
        ]))
    }

    @Test func noiseControlRoundTrips() {
        let modes: [NoiseControl] = [.off, .transparency] + ANCStrength.allCases.map { .noiseCancelling($0) }
        for mode in modes {
            #expect(message(0x401E, [0x01, mode.wireValue]) == .noiseControl(mode))
        }
    }

    @Test func ancStrengthsFromLevelBits() {
        #expect(ANCStrength.available(ancLevel: 63) == [.high, .mid, .low, .adaptive])
        #expect(ANCStrength.available(ancLevel: 55) == [.high, .mid, .low])
        #expect(ANCStrength.available(ancLevel: 53) == [.high, .low])
        #expect(ANCStrength.available(ancLevel: 49) == [])
    }

    @Test func customEQRoundTrips() {
        let eq = CustomEQ(bass: 4, mid: 2, treble: -3)
        #expect(message(0x4044, eq.payload(bands: headphoneProBands)) == .customEQ(eq))
        #expect(CustomEQ(payload: bytes("03000080c00100000040000075443333333f02000040c000c05a450000803f000000804000000c43cdcc4c3f000000000000000000")) == eq)
    }

    @Test func spatialAudio() {
        #expect(message(0x404F, [0x02, 0x00]) == .spatialAudio(.concert))
        #expect(message(0x404F, [0x03, 0x00]) == .spatialAudio(.cinema))
        #expect(message(0x404F, [0x01, 0x01]) == .spatialAudio(.headTracked))
        #expect(message(0x404F, [0x01, 0x07]) == .spatialAudio(.fixed))
        #expect(message(0x404F, [0x00, 0x00]) == .spatialAudio(.off))
        #expect(SpatialAudioMode.available(mask: 28) == [.off, .concert, .cinema])
        #expect(SpatialAudioMode.available(mask: 7) == [.off, .headTracked, .fixed])
    }

    @Test func firmwareAndLatency() {
        #expect(message(0x4042, Array("1.0.2.31".utf8)) == .firmware("1.0.2.31"))
        #expect(message(0x4041, [0x02]) == .lowLatency(false))
        #expect(message(0x9999, [0x00]) == nil)
    }
}

@Suite struct ModelData {
    @Test func firmwareRanges() {
        #expect(FirmwareVersion.isIn("1.0.1.74", min: nil, max: "*.*.1.74"))
        #expect(!FirmwareVersion.isIn("1.0.1.75", min: nil, max: "*.*.1.74"))
        #expect(FirmwareVersion.isIn("2.0.1.80-beta", min: "*.*.1.75", max: "*.*.1.85"))
        #expect(FirmwareVersion.isIn("1.0.2", min: "*.*.2.0", max: nil))
        #expect(!FirmwareVersion.isIn("1.0.x.1", min: "*.*.1.0", max: nil))
    }

    @Test func configSelection() throws {
        let table = try ModelConfigTable(json: Data(contentsOf: resources.appending(path: "Data/ear_config.json")))
        let headphonePro = try #require(table.config(base: "B175", firmware: "anything"))
        #expect(headphonePro.int("ancLevel") == 63)
        #expect(headphonePro.int("spatialAudio") == 28)
        #expect(headphonePro.customEQBands?.high.frequency == 3500)
        // Ear (2): two configs split at firmware *.*.1.95 on advancedEq.
        #expect(table.config(base: "B155", firmware: "1.0.1.94")?.flag("advancedEq") == false)
        #expect(table.config(base: "B155", firmware: "1.0.1.95")?.flag("advancedEq") == true)
        #expect(table.config(base: "B999", firmware: "1.0") == nil)
    }

    @Test func catalogAndProfiles() throws {
        let catalog = try DeviceCatalog(json: Data(contentsOf: resources.appending(path: "Data/catalog.json")))
        #expect(catalog.skus.count == 74)
        let mine = try #require(catalog.model(sku: FastPair.sku(fromMessage: bytes("0301000373c9eb03"))!))
        #expect(mine.name == "CMF Headphone Pro")
        #expect(mine.images.duo == "b175_white_duo")
        #expect(catalog.model(bluetoothName: "CMF Headphone Pro")?.base == "B175")
        // Every catalogued model has a profile and every image exists.
        for sku in catalog.skus {
            #expect(ModelProfile.profile(base: sku.base) != nil, "no profile for \(sku.base)")
            for image in [sku.images.left, sku.images.right, sku.images.case, sku.images.duo] {
                #expect(FileManager.default.fileExists(atPath: resources.appending(path: "Images/Devices/\(image).png").path),
                        "missing \(image)")
            }
        }
    }
}
