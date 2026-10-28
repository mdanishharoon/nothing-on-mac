import Testing
@testable import HeadphoneProtocol

// Expected bytes were worked out by hand from ear-web's buildAdvancedEQBandsPacket(),
// setAdvancedAndThirdDriverEQ_BT() and set_enhanced_bass() (spec gestures-eq.md §B.4-B.5).
// Float32 LE: 1.0 = 0000803f, 3.0 = 00004040, -1.5 = 0000c0bf, 0.7 = 3333333f, -2 = 000000c0,
// 55 Hz = 00005c42, 1320 Hz = 0000a544, 15000 Hz = 00606a46.

private func frame(_ command: UInt16, _ payload: [UInt8]) -> Frame {
    Frame(command: command, operationID: 1, payload: payload, checksumValid: true)
}

@Suite struct AdvancedEQEncoding {
    @Test func fixedEightBandWrite() {
        var bands = AdvancedEQLayout.fixedDefault
        bands[0].gain = 3
        bands[4].gain = -1.5
        let request = Request.setAdvancedEQValues(bands)
        #expect(request.command == 0xF050)
        #expect(hex(request.payload) ==
            "0008" + "000040c0"
            + "01" + "00004040" + "00005c42" + "0000803f"
            + "01" + "00000000" + "0000dc42" + "0000803f"
            + "01" + "00000000" + "00005c43" + "0000803f"
            + "01" + "00000000" + "0000dc43" + "0000803f"
            + "01" + "0000c0bf" + "0000a544" + "0000803f"
            + "01" + "00000000" + "00404e45" + "0000803f"
            + "01" + "00000000" + "0040ce45" + "0000803f"
            + "01" + "00000000" + "00404e46" + "0000803f")
    }

    @Test func fixedWriteWithoutBoostSendsNegativeZeroTotalGain() {
        var bands = AdvancedEQLayout.fixedDefault
        bands[2].gain = -4
        #expect(Array(Request.setAdvancedEQValues(bands).payload[2...5]) == [0x00, 0x00, 0x00, 0x80])
    }

    @Test func precisionDriverWriteSendsBothSetsWithSharedTotalGain() {
        let main = [ParametricBand(gain: 2, frequency: 50), ParametricBand(gain: -1, frequency: 250, q: 0.7)]
        let driver = [ParametricBand(gain: 1.5, frequency: 16000)]
        let requests = Request.setAdvancedAndPrecisionEQ(main: main, driver: driver, firmware: "1.0.1.50")
        #expect(requests.map(\.command) == [0xF050, 0xF06D])
        #expect(hex(requests[0].payload) ==
            "0002" + "000000c0"
            + "01" + "00000040" + "00004842" + "0000803f"
            + "01" + "000080bf" + "00007a43" + "3333333f")
        // Driver frequency clamped to 15 kHz.
        #expect(hex(requests[1].payload) ==
            "0001" + "000000c0"
            + "01" + "0000c03f" + "00606a46" + "0000803f")
    }

    @Test func dualTotalGainSignQuirk() {
        let cut = [ParametricBand(gain: -3, frequency: 100)]
        let boost = [ParametricBand(gain: 1.5, frequency: 8000)]
        // No boost: +0, encoded 00000000 (unlike the fixed layout's -0).
        let flat = Request.setAdvancedAndPrecisionEQ(main: cut, driver: cut, firmware: "1.0.1.50")
        #expect(Array(flat[0].payload[2...5]) == [0, 0, 0, 0])
        #expect(Array(flat[1].payload[2...5]) == [0, 0, 0, 0])
        // Peak is truncated: 1.5 -> -1.
        #expect(AdvancedEQLayout.dualTotalGain(main: cut, driver: boost, firmware: "1.0.1.46") == -1)
        // Unknown or unparseable firmware uses the native rule.
        #expect(AdvancedEQLayout.dualTotalGain(main: boost, driver: [], firmware: nil) == -1)
        #expect(AdvancedEQLayout.dualTotalGain(main: boost, driver: [], firmware: "abc") == -1)
        // Older firmware: min(0, 6 - peak), which is +0 for any gain within ±6.
        let old = AdvancedEQLayout.dualTotalGain(main: boost, driver: [], firmware: "1.0.1.40")
        #expect(old == 0 && old.sign == .plus)
    }

    @Test func reads() {
        #expect(Request.readAdvancedEQValues == Request(0xC04D, [0xFF]))
        #expect(Request.readPrecisionDriverMode == Request(0xC06C))
        #expect(Request.readPrecisionDriverValues == Request(0xC06D, [0xFF]))
        #expect(Request.enablePrecisionDriverMode == Request(0xF06C, [0x01]))
        #expect(Request.readBass == Request(0xC04E))
        #expect(Request.readFlatEQ == Request(0xC068))
        var encoder = PacketEncoder()
        #expect(hex(encoder.encode(.readAdvancedEQValues)) == "5560014dc0010001ff90ab")
    }
}

@Suite struct AdvancedEQParsing {
    private let reply = bytes("ff" + "02" + "000000c0"
        + "01" + "00004040" + "00005c42" + "0000803f"
        + "01" + "0000c0bf" + "0000a544" + "3333333f")

    @Test func valuesReply() {
        let expected = ParametricEQPacket(bands: [
            ParametricBand(gain: 3, frequency: 55, q: 1),
            ParametricBand(gain: -1.5, frequency: 1320, q: 0.7),
        ], totalGain: -2)
        #expect(EQExtraMessage(frame: frame(0x404D, reply)) == .advancedEQValues(expected))
        #expect(EQExtraMessage(frame: frame(0x406D, reply)) == .precisionDriverValues(expected))
    }

    @Test func stopsWhenBandBytesRunOut() {
        var short = reply
        short[1] = 3
        guard case .advancedEQValues(let packet)? = EQExtraMessage(frame: frame(0x404D, short)) else {
            Issue.record("not parsed")
            return
        }
        #expect(packet.bands.count == 2)
        #expect(EQExtraMessage(frame: frame(0x404D, Array(reply.prefix(5)))) == nil)
    }

    @Test func precisionDriverMode() {
        #expect(EQExtraMessage(frame: frame(0x406C, [0x01])) == .precisionDriverMode(true))
        #expect(EQExtraMessage(frame: frame(0x406C, [0x00])) == .precisionDriverMode(false))
    }
}

@Suite struct AdvancedEQLayoutRules {
    @Test func addedBandGoesInWidestGap() {
        #expect(AdvancedEQLayout.insertionFrequency(existing: [50, 250, 4000], in: AdvancedEQLayout.mainRange) == 1000)
        #expect(AdvancedEQLayout.insertionFrequency(existing: [8000], in: AdvancedEQLayout.driverRange) == 10954)
    }

    @Test func logFrequencySlider() {
        #expect(AdvancedEQLayout.frequency(atLogPosition: 0.5, in: AdvancedEQLayout.mainRange) == 632)
        #expect(AdvancedEQLayout.frequency(atLogPosition: 0, in: AdvancedEQLayout.mainRange) == 20)
        #expect(AdvancedEQLayout.frequency(atLogPosition: 1, in: AdvancedEQLayout.mainRange) == 20000)
        #expect(abs(AdvancedEQLayout.logPosition(of: 632, in: AdvancedEQLayout.mainRange) - 0.5) < 0.001)
    }
}

@Suite struct BassAndFlatEQ {
    @Test func fiveStageWrite() {
        let scheme = BassScheme(threeStage: false)
        #expect(Request.setBass(enabled: true, wireLevel: scheme.wire(level: 3)) == Request(0xF051, [0x01, 0x06]))
        #expect(Request.setBass(enabled: false, wireLevel: scheme.wire(level: 5)) == Request(0xF051, [0x00, 0x0A]))
        #expect(Request.setBass(enabled: true, wireLevel: scheme.wire(level: 1)).payload == [0x01, 0x02])
        var encoder = PacketEncoder()
        #expect(hex(encoder.encode(.setBass(enabled: true, wireLevel: scheme.wire(level: 3)))) == "55600151f00200010106f73f")
    }

    @Test func threeStageWrite() {
        let scheme = BassScheme(threeStage: true)
        #expect(Request.setBass(enabled: false, wireLevel: scheme.wire(level: 0)).payload == [0x00, 0x00])
        #expect(Request.setBass(enabled: true, wireLevel: scheme.wire(level: 1)).payload == [0x01, 0x05])
        #expect(Request.setBass(enabled: true, wireLevel: scheme.wire(level: 2)).payload == [0x01, 0x0A])
    }

    @Test func bassReply() {
        #expect(EQExtraMessage(frame: frame(0x404E, [0x01, 0x08])) == .bass(enabled: true, wireLevel: 8))
        #expect(EQExtraMessage(frame: frame(0x404E, [0x00, 0x05])) == .bass(enabled: false, wireLevel: 5))
        #expect(EQExtraMessage(frame: frame(0x404E, [0x01])) == nil)
        let five = BassScheme.fiveStage, three = BassScheme.threeStage
        #expect(five.level(wire: 8) == 4)
        #expect(five.level(wire: 0) == nil)
        #expect(five.level(wire: 7) == nil)
        #expect(three.level(wire: 5) == 1)
        #expect(three.level(wire: 10) == 2)
        #expect(three.level(wire: 0) == 0)
        #expect(three.level(wire: 6) == nil)
    }

    @Test func flatEQReplyAndPushes() {
        #expect(EQExtraMessage(frame: frame(0x4068, [0x01])) == .flatEQ(true))
        #expect(EQExtraMessage(frame: frame(0x4068, [0x00])) == .flatEQ(false))
        #expect(EQExtraMessage(frame: frame(0xE01C, [0x01])) == .flatEQ(true))
        #expect(EQExtraMessage(frame: frame(0x601C, [0x00])) == .flatEQ(false))
    }
}
