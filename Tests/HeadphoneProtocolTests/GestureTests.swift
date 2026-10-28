import Testing
@testable import HeadphoneProtocol

// Expected bytes follow ear-web's sendGestures(): 0xF003 [0x01, device, button, type, action].

private func layout(_ base: String, smartKnob: Bool = false) -> GestureLayout {
    GestureLayout.forModel(base: base, smartKnob: smartKnob)!
}

private func group(_ layout: GestureLayout, _ id: String) -> GestureGroup {
    layout.groups.first { $0.id == id }!
}

private func slot(_ group: GestureGroup, _ id: String) -> GestureSlot {
    group.slots.first { $0.id == id }!
}

private func option(_ slot: GestureSlot, _ label: String) -> GestureOption {
    slot.options.first { $0.label == label }!
}

private func reply(_ records: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
    [UInt8(records.count)] + records.flatMap { [$0.0, $0.1, $0.2, $0.3] }
}

@Suite struct GestureWire {
    @Test func fullPackets() {
        var reader = PacketEncoder()
        #expect(hex(reader.encode(.readGestures)) == "55600118c0000001391d")
        var encoder = PacketEncoder()
        #expect(hex(encoder.encode(.setGesture(device: 2, button: 1, type: 2, action: 9))) == "55600103f00500010102010209d2f9")
        var second = PacketEncoder()
        #expect(hex(second.encode(.setGesture(device: 6, button: 10, type: 1, action: 11))) == "55600103f005000101060a010b233a")
    }

    @Test func earbudSlotWrite() {
        let buds = layout("B172")
        let left = group(buds, "left"), right = group(buds, "right")
        var state = GestureState()
        let double = slot(left, "double")
        #expect(buds.select(option(double, "Skip forward"), slot: double, in: left, state: &state)
            == [Request(0xF003, [0x01, 0x02, 0x01, 0x02, 0x09])])
        let hold = slot(right, "doubleHold")
        #expect(buds.select(option(hold, "Volume down"), slot: hold, in: right, state: &state)
            == [Request(0xF003, [0x01, 0x03, 0x01, 0x09, 0x13])])
        #expect(state.action(left.key(double)) == 9)
        #expect(state.action(right.key(double)) == nil)
    }

    @Test func singleUnitSlotWritesUseTheControlDiscriminator() {
        let pro = layout("B175")
        var state = GestureState()
        let button = group(pro, "button"), slider = group(pro, "slider"), roller = group(pro, "roller")
        let single = slot(button, "button.single")
        #expect(pro.select(option(single, "Voice AI"), slot: single, in: button, state: &state)
            == [Request(0xF003, [0x01, 0x06, 0x0A, 0x01, 0x0B])])
        let energy = slot(slider, "slider")
        #expect(pro.select(option(energy, "Treble tuning"), slot: energy, in: slider, state: &state)
            == [Request(0xF003, [0x01, 0x06, 0x05, 0x01, 0x24])])
        let rollerHold = slot(roller, "roller.hold")
        #expect(pro.select(.noiseCycle, slot: rollerHold, in: roller, state: &state)
            == [Request(0xF003, [0x01, 0x06, 0x01, 0x07, 0x16])])

        // ear-web's documented example: Headphone (1) single press -> Voice AI.
        let one = layout("B170")
        let oneButton = group(one, "button")
        #expect(one.select(option(slot(oneButton, "button.single"), "Voice AI"), slot: slot(oneButton, "button.single"),
                           in: oneButton, state: &state) == [Request(0xF003, [0x01, 0x06, 0x0A, 0x01, 0x0B])])
    }

    @Test func noiseControlCycleWrites() {
        let ear = layout("B155")
        let left = group(ear, "left")
        let hold = slot(left, "hold")
        let key = left.key(hold)
        var state = GestureState()

        // Before any read the cycle is Transparency + Cancelling (22).
        #expect(ear.select(.noiseCycle, slot: hold, in: left, state: &state)
            == [Request(0xF003, [0x01, 0x02, 0x01, 0x07, 22])])
        #expect(ear.toggle(.off, slot: hold, in: left, state: &state)
            == [Request(0xF003, [0x01, 0x02, 0x01, 0x07, 10])])
        #expect(ear.toggle(.transparency, slot: hold, in: left, state: &state)
            == [Request(0xF003, [0x01, 0x02, 0x01, 0x07, 20])])
        // Only Cancelling + Off remain: neither may be switched off.
        #expect(ear.toggle(.cancelling, slot: hold, in: left, state: &state) == nil)
        #expect(ear.toggle(.off, slot: hold, in: left, state: &state) == nil)
        #expect(state.action(key) == 20)
        #expect(ear.toggle(.transparency, slot: hold, in: left, state: &state)
            == [Request(0xF003, [0x01, 0x02, 0x01, 0x07, 10])])
        #expect(ear.toggle(.cancelling, slot: hold, in: left, state: &state)
            == [Request(0xF003, [0x01, 0x02, 0x01, 0x07, 21])])
    }

    @Test func cycleEditsWithoutTheCycleSelectedDontWrite() {
        let ear = layout("B155")
        let left = group(ear, "left")
        let hold = slot(left, "hold")
        var state = GestureState()
        _ = ear.select(option(hold, "Volume up"), slot: hold, in: left, state: &state)
        #expect(ear.toggle(.off, slot: hold, in: left, state: &state) == [])
        // The edited cycle is what "Noise control" then writes.
        #expect(ear.select(.noiseCycle, slot: hold, in: left, state: &state)
            == [Request(0xF003, [0x01, 0x02, 0x01, 0x07, 10])])
    }

    @Test func smartKnobAndDialWrites() {
        let buds = layout("B172", smartKnob: true)
        let dial = group(buds, "dial")
        #expect(dial.device == 4)
        var state = GestureState()
        let doubleCall = slot(dial, "double.call")
        #expect(buds.select(option(doubleCall, "Answer + mute mic"), slot: doubleCall, in: dial, state: &state)
            == [Request(0xF003, [0x01, 0x04, 0x09, 0x02, 0x19])])
        let rotate = slot(dial, "rotate")
        #expect(buds.select(option(rotate, "Volume control"), slot: rotate, in: dial, state: &state)
            == [Request(0xF003, [0x01, 0x04, 0x01, 0x0A, 0x17])])
        let hold = slot(dial, "hold")
        #expect(buds.select(.noiseCycle, slot: hold, in: dial, state: &state)
            == [Request(0xF003, [0x01, 0x04, 0x01, 0x07, 22])])

        let clip = layout("B189")
        let clipDial = group(clip, "dial")
        let tripleCall = slot(clipDial, "triple.call")
        #expect(clip.select(option(tripleCall, "Hang up / decline"), slot: tripleCall, in: clipDial, state: &state)
            == [Request(0xF003, [0x01, 0x04, 0x09, 0x03, 0x1A])])
        #expect(!slot(clipDial, "hold").options.contains { $0.isNoiseCycle })
    }

    @Test func pinchBothBudsWritesBothBuds() {
        let ear = layout("B190")
        let right = group(ear, "right")
        let both = slot(right, "both")
        var state = GestureState()
        #expect(ear.select(option(both, "Voice recording"), slot: both, in: right, state: &state) == [
            Request(0xF003, [0x01, 0x02, 0x01, 0x0B, 0x25]),
            Request(0xF003, [0x01, 0x03, 0x01, 0x0B, 0x25]),
        ])
        #expect(state.action(GestureSlotKey(device: 2, slot: "both")) == 37)
        #expect(state.action(GestureSlotKey(device: 3, slot: "both")) == 37)
    }

    @Test func caseButtonOnlyOnEar3() {
        let ear3 = layout("B173")
        let caseGroup = group(ear3, "case")
        var state = GestureState()
        let hold = slot(caseGroup, "hold")
        #expect(ear3.select(option(hold, "Essential space"), slot: hold, in: caseGroup, state: &state)
            == [Request(0xF003, [0x01, 0x04, 0x01, 0x07, 0x21])])
        #expect(layout("B172").groups.map(\.id) == ["left", "right"])
        #expect(layout("B179", smartKnob: true).groups.map(\.id) == ["left", "right"])
    }
}

@Suite struct GestureReading {
    @Test func parsesRecordsAndDropsTruncatedOne() {
        let frame = Frame(command: 0x4018, operationID: 1,
                          payload: [0x03, 0x02, 0x01, 0x02, 0x09, 0x06, 0x0A, 0x07, 0x14, 0x03, 0x01], checksumValid: true)
        #expect(GestureRecord.records(from: frame) == [
            GestureRecord(device: 2, common: 1, type: 2, action: 9),
            GestureRecord(device: 6, common: 10, type: 7, action: 20),
        ])
        #expect(GestureRecord.parse([]) == [])
        #expect(GestureRecord.records(from: Frame(command: 0x4007, operationID: 1, payload: [0], checksumValid: true)) == nil)
    }

    @Test func statesArePerSideIncludingTheCycle() {
        let ear = layout("B155")
        var state = GestureState()
        ear.apply(GestureRecord.parse(reply([(2, 1, 7, 20), (3, 1, 7, 21), (2, 1, 2, 9), (3, 1, 2, 8), (5, 1, 2, 9)])),
                  to: &state)
        let left = group(ear, "left"), right = group(ear, "right")
        let hold = slot(left, "hold")
        #expect(state.cycle(left.key(hold)).modes == [.cancelling, .off])
        #expect(state.cycle(right.key(hold)).modes == [.transparency, .off])
        #expect(hold.label(for: state.action(left.key(hold))!) == "Noise control")
        #expect(state.action(left.key(slot(left, "double"))) == 9)
        #expect(state.action(right.key(slot(right, "double"))) == 8)
    }

    @Test func commonByteSeparatesHeadphoneControls() {
        let one = layout("B170")
        var state = GestureState()
        one.apply(GestureRecord.parse(reply([(6, 10, 7, 33), (6, 1, 7, 1), (6, 10, 1, 32)])), to: &state)
        #expect(state.action(GestureSlotKey(device: 6, slot: "button.hold")) == 33)
        #expect(state.action(GestureSlotKey(device: 6, slot: "roller.hold")) == 1)
        #expect(state.action(GestureSlotKey(device: 6, slot: "button.single")) == 32)

        let pro = layout("B175")
        pro.apply(GestureRecord.parse(reply([(6, 5, 1, 36), (6, 10, 1, 31)])), to: &state)
        #expect(state.action(GestureSlotKey(device: 6, slot: "slider")) == 36)
        #expect(state.action(GestureSlotKey(device: 6, slot: "button.single")) == 31)
    }

    @Test func dialRecordsMatchOnCommon() {
        let buds = layout("B172", smartKnob: true)
        var state = GestureState()
        buds.apply(GestureRecord.parse(reply([(4, 1, 2, 9), (4, 9, 2, 3), (4, 9, 3, 26)])), to: &state)
        #expect(state.action(GestureSlotKey(device: 4, slot: "double")) == 9)
        #expect(state.action(GestureSlotKey(device: 4, slot: "double.call")) == 3)
        #expect(state.action(GestureSlotKey(device: 4, slot: "triple.call")) == 26)
    }

    @Test func budSlotsPreferTheirOwnCommonByte() {
        let buds = layout("B172")
        for records in [[(UInt8(2), UInt8(1), UInt8(2), UInt8(9)), (2, 9, 2, 3)], [(2, 9, 2, 3), (2, 1, 2, 9)]] {
            var state = GestureState()
            buds.apply(GestureRecord.parse(reply(records)), to: &state)
            #expect(state.action(GestureSlotKey(device: 2, slot: "double")) == 9)
        }
        // With no media record, another common still counts.
        var state = GestureState()
        buds.apply(GestureRecord.parse(reply([(2, 0, 3, 8)])), to: &state)
        #expect(state.action(GestureSlotKey(device: 2, slot: "triple")) == 8)
    }

    @Test func unknownActionsAreShownNotHidden() {
        let buds = layout("B172")
        let left = group(buds, "left")
        let doubleHold = slot(left, "doubleHold")
        #expect(doubleHold.label(for: 42) == "Unknown (42)")
        #expect(doubleHold.option(for: 42) == nil)
        // A known action this slot doesn't offer shows its name.
        #expect(doubleHold.label(for: 2) == "Play/pause")
        // Ear (stick) has no cycle, so 20 isn't its "Noise control" option.
        let stick = slot(group(layout("B157"), "left"), "hold")
        #expect(stick.option(for: 20) == nil)
        #expect(stick.option(for: 10)?.label == "Noise control")
    }

    @Test func headphoneOneProNewsOnHoldReadsAsNoActionWithoutAWrite() {
        let pro = layout("B192")
        var state = GestureState()
        pro.apply(GestureRecord.parse(reply([(6, 10, 7, 31)])), to: &state)
        let hold = slot(group(pro, "button"), "button.hold")
        #expect(hold.label(for: state.action(GestureSlotKey(device: 6, slot: "button.hold"))!) == "No action")
        var writes = GestureState()
        #expect(pro.select(option(hold, "No action"), slot: hold, in: group(pro, "button"), state: &writes)
            == [Request(0xF003, [0x01, 0x06, 0x0A, 0x07, 0x01])])
    }
}

@Suite struct GestureDefinitions {
    @Test func everyModelHasAWellFormedLayout() {
        for base in ModelProfile.all.keys {
            guard let layout = GestureLayout.forModel(base: base, smartKnob: true) else {
                Issue.record("no gesture layout for \(base)")
                continue
            }
            #expect(!layout.groups.isEmpty)
            #expect(Set(layout.groups.map(\.id)).count == layout.groups.count, "\(base)")
            for device in Set(layout.groups.map(\.device)) {
                let slots = layout.groups.filter { $0.device == device }.flatMap(\.slots)
                #expect(Set(slots.map(\.id)).count == slots.count, "\(base) device \(device)")
                // No two slots on a device may claim the same records.
                let claims = slots.map { "\($0.type)/\($0.common.map(String.init) ?? "*")" }
                #expect(Set(claims).count == claims.count, "\(base) device \(device)")
            }
            for slot in layout.groups.flatMap(\.slots) {
                #expect(!slot.options.isEmpty, "\(base) \(slot.id)")
                #expect(Set(slot.options.map(\.label)).count == slot.options.count, "\(base) \(slot.id)")
                #expect(Set(slot.options.map(\.action)).count == slot.options.count, "\(base) \(slot.id)")
                if slot.common != nil { #expect(slot.common == slot.button, "\(base) \(slot.id)") }
            }
        }
    }

    @Test func topologies() {
        #expect(layout("B164").groups.map(\.device) == [6])
        #expect(layout("B175").groups.map(\.id) == ["button", "slider", "roller"])
        #expect(layout("B170").groups.map(\.id) == ["button", "roller"])
        #expect(layout("B189").groups.map(\.id) == ["left", "right", "dial"])
        #expect(layout("B195", smartKnob: true).groups.map(\.id) == ["left", "right", "dial"])
        #expect(group(layout("B190"), "left").slots.last?.title == "Pinch both buds")
        #expect(group(layout("B190"), "left").slots.first?.options.first?.label == "Skip forward")
        #expect(GestureLayout.forModel(base: "B999") == nil)
    }

    @Test func noiseCycleIds() {
        #expect(NoiseCycle.initial.action == 22)
        #expect(NoiseCycle(action: 10)?.modes == [.transparency, .cancelling, .off])
        #expect(NoiseCycle(action: 20)?.modes == [.cancelling, .off])
        #expect(NoiseCycle(action: 21)?.modes == [.transparency, .off])
        #expect(NoiseCycle(action: 22)?.modes == [.transparency, .cancelling])
        #expect(NoiseCycle(action: 11) == nil)
    }
}
