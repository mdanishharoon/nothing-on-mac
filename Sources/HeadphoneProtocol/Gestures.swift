// Gesture (control) remapping: earbud taps/pinches, headphone button / roller / slider, and the
// case button, smart knob or smart dial.
//
// Read 0xC018 -> reply 0x4018: [count, then `count` records of device, common, type, action].
// Write 0xF003: [0x01 (one record), device, common/button, type, action].
// Ported from ear-web's gestures_common.js and the per-model gesture files.
//
// Deliberate departures from ear-web:
//  - State, including the noise-control cycle, is kept per device (ear-web shares one cycle
//    selector between the buds), and a cycle change writes only the side being edited.
//  - Slots without a common discriminator prefer a record whose common byte equals the slot's
//    write byte, so a call-context record can't overwrite the media value.
//  - Actions the slot doesn't offer show their name (or "Unknown (id)") instead of being ignored.
//  - B192's automatic News -> No action rewrite on read is not done; nothing is written unasked.
//  - Choosing "Noise control" keeps its cycle editable instead of closing the list.

public enum GestureDevice {
    public static let left: UInt8 = 2
    public static let right: UInt8 = 3
    /// Charging case button, smart knob or smart dial.
    public static let `case`: UInt8 = 4
    /// Headphones or neckband.
    public static let single: UInt8 = 6
}

public enum GestureType {
    public static let single: UInt8 = 1
    public static let double: UInt8 = 2
    public static let triple: UInt8 = 3
    public static let hold: UInt8 = 7
    public static let doubleHold: UInt8 = 9
    public static let rotate: UInt8 = 10
    public static let pinchBothBuds: UInt8 = 11
}

/// One record of a 0x4018 reply.
public struct GestureRecord: Equatable, Sendable {
    public let device: UInt8
    public let common: UInt8
    public let type: UInt8
    public let action: UInt8

    public init(device: UInt8, common: UInt8, type: UInt8, action: UInt8) {
        self.device = device
        self.common = common
        self.type = type
        self.action = action
    }

    public static let replyCommand: UInt16 = 0x4018

    /// Records from a 0x4018 payload; a truncated trailing record is dropped.
    public static func parse(_ payload: [UInt8]) -> [GestureRecord] {
        guard let count = payload.first else { return [] }
        var records: [GestureRecord] = []
        for i in 0..<Int(count) {
            let start = 1 + i * 4
            guard start + 3 < payload.count else { break }
            records.append(GestureRecord(device: payload[start], common: payload[start + 1],
                                         type: payload[start + 2], action: payload[start + 3]))
        }
        return records
    }

    /// Records from a gestures reply frame, or nil if the frame is something else.
    public static func records(from frame: Frame) -> [GestureRecord]? {
        frame.command == replyCommand ? parse(frame.payload) : nil
    }
}

extension Request {
    public static let readGestures = Request(0xC018)

    public static func setGesture(device: UInt8, button: UInt8, type: UInt8, action: UInt8) -> Request {
        Request(0xF003, [0x01, device, button, type, action])
    }
}

/// Names for action ids, used when the device reports one the slot doesn't offer.
public enum GestureAction {
    public static func name(_ id: UInt8) -> String? {
        switch id {
        case 1: "No action"
        case 2: "Play/pause"
        case 3: "Answer calls"
        case 8: "Skip back"
        case 9: "Skip forward"
        case 10, 20, 21, 22: "Noise control"
        case 11: "Voice assistant"
        case 17: "Low lag mode"
        case 18: "Volume up"
        case 19: "Volume down"
        case 23: "Volume control"
        case 24: "Camera shutter"
        case 25: "Answer + mute mic"
        case 26: "Hang up / decline"
        case 27: "Spatial audio"
        case 29: "Mic mute"
        case 31: "News"
        case 32: "Channel hop"
        case 33: "Essential space"
        case 34: "EQ preset"
        case 35: "Bass tuning"
        case 36: "Treble tuning"
        case 37: "Voice recording"
        default: nil
        }
    }
}

/// The modes a "Noise control" gesture cycles through. At least two of the three stay on, so
/// each value is one of the four action ids 10 (all), 20 (cancelling/off), 21 (transparency/off)
/// and 22 (transparency/cancelling).
public struct NoiseCycle: Hashable, Sendable {
    public enum Mode: CaseIterable, Sendable {
        case transparency, cancelling, off

        public var name: String {
            switch self {
            case .transparency: "Transparency"
            case .cancelling: "Cancelling"
            case .off: "Off"
            }
        }
    }

    public let action: UInt8

    /// ear-web's starting selection, before the device has reported one.
    public static let initial = NoiseCycle(uncheckedAction: 22)

    public init?(action: UInt8) {
        guard [10, 20, 21, 22].contains(action) else { return nil }
        self.action = action
    }

    private init(uncheckedAction: UInt8) {
        action = uncheckedAction
    }

    public func contains(_ mode: Mode) -> Bool {
        switch mode {
        case .transparency: action != 20
        case .cancelling: action != 21
        case .off: action != 22
        }
    }

    public var modes: [Mode] { Mode.allCases.filter(contains) }

    /// The cycle with `mode` switched, or nil if that would leave fewer than two modes.
    public func toggling(_ mode: Mode) -> NoiseCycle? {
        var on = Mode.allCases.map(contains)
        let index = Mode.allCases.firstIndex(of: mode)!
        on[index].toggle()
        switch (on[0], on[1], on[2]) {
        case (true, true, true): return NoiseCycle(uncheckedAction: 10)
        case (false, true, true): return NoiseCycle(uncheckedAction: 20)
        case (true, false, true): return NoiseCycle(uncheckedAction: 21)
        case (true, true, false): return NoiseCycle(uncheckedAction: 22)
        default: return nil
        }
    }
}

public struct GestureOption: Hashable, Sendable {
    public let label: String
    /// Action id written when chosen (for the noise-control cycle, the current cycle is written).
    public let action: UInt8
    /// Further ids the device may report for this option.
    public let aliases: [UInt8]
    public let isNoiseCycle: Bool

    public init(_ label: String, _ action: UInt8, aliases: [UInt8] = []) {
        self.label = label
        self.action = action
        self.aliases = aliases
        isNoiseCycle = false
    }

    private init(cycleLabel: String) {
        label = cycleLabel
        action = NoiseCycle.initial.action
        aliases = []
        isNoiseCycle = true
    }

    /// "Noise control" with a Transparency / Cancelling / Off cycle (ids 10, 20, 21, 22).
    public static let noiseCycle = GestureOption(cycleLabel: "Noise control")

    public func matches(_ id: UInt8) -> Bool {
        isNoiseCycle ? NoiseCycle(action: id) != nil : id == action || aliases.contains(id)
    }
}

public struct GestureSlot: Hashable, Sendable, Identifiable {
    /// Unique among the slots of one device.
    public let id: String
    public let title: String
    public let type: UInt8
    /// When set, a record matches only if its common byte equals this.
    public let common: UInt8?
    /// The common/button byte written.
    public let button: UInt8
    public let options: [GestureOption]
    /// Written to both buds (Ear (3a) "Pinch both buds").
    public let writesBothBuds: Bool

    public init(_ id: String, _ title: String, type: UInt8, common: UInt8? = nil, button: UInt8 = 1,
                options: [GestureOption], writesBothBuds: Bool = false) {
        self.id = id
        self.title = title
        self.type = type
        self.common = common
        self.button = button
        self.options = options
        self.writesBothBuds = writesBothBuds
    }

    public func option(for action: UInt8) -> GestureOption? {
        options.first { $0.matches(action) }
    }

    /// What the slot is set to: the option's label, else the action's name, else "Unknown (id)".
    public func label(for action: UInt8) -> String {
        option(for: action)?.label ?? GestureAction.name(action) ?? "Unknown (\(action))"
    }
}

/// A page of the controls UI: one bud, the case or dial, or one control of a headphone.
public struct GestureGroup: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let device: UInt8
    public let slots: [GestureSlot]

    public init(_ name: String, device: UInt8, slots: [GestureSlot]) {
        id = name.lowercased()
        self.name = name
        self.device = device
        self.slots = slots
    }

    public func key(_ slot: GestureSlot) -> GestureSlotKey {
        GestureSlotKey(device: device, slot: slot.id)
    }
}

public struct GestureSlotKey: Hashable, Sendable {
    public let device: UInt8
    public let slot: String

    public init(device: UInt8, slot: String) {
        self.device = device
        self.slot = slot
    }
}

/// What each slot is set to, per device.
public struct GestureState: Equatable, Sendable {
    public private(set) var actions: [GestureSlotKey: UInt8] = [:]
    private var cycles: [GestureSlotKey: NoiseCycle] = [:]

    public init() {}

    public func action(_ key: GestureSlotKey) -> UInt8? { actions[key] }

    /// The cycle a "Noise control" choice writes for this slot.
    public func cycle(_ key: GestureSlotKey) -> NoiseCycle { cycles[key] ?? .initial }

    mutating func set(_ action: UInt8, for key: GestureSlotKey) {
        actions[key] = action
        if let cycle = NoiseCycle(action: action) { cycles[key] = cycle }
    }

    mutating func setCycle(_ cycle: NoiseCycle, for key: GestureSlotKey) {
        cycles[key] = cycle
    }
}

/// Every gesture slot of a model.
public struct GestureLayout: Sendable {
    public let groups: [GestureGroup]

    public init(groups: [GestureGroup]) {
        self.groups = groups
    }

    /// The slot a record belongs to; `exact` when its common byte is the slot's own.
    func resolve(_ record: GestureRecord) -> (key: GestureSlotKey, exact: Bool)? {
        for group in groups where group.device == record.device {
            for slot in group.slots where slot.type == record.type {
                if let common = slot.common, common != record.common { continue }
                return (group.key(slot), record.common == slot.button)
            }
        }
        return nil
    }

    /// Applies a gestures reply. Records the layout has no slot for are skipped.
    public func apply(_ records: [GestureRecord], to state: inout GestureState) {
        var exactKeys: Set<GestureSlotKey> = []
        for record in records {
            guard let (key, exact) = resolve(record) else { continue }
            if !exact, exactKeys.contains(key) { continue }
            if exact { exactKeys.insert(key) }
            state.set(record.action, for: key)
        }
    }

    /// Chooses `option` for `slot` and returns the writes.
    public func select(_ option: GestureOption, slot: GestureSlot, in group: GestureGroup,
                       state: inout GestureState) -> [Request] {
        let action = option.isNoiseCycle ? state.cycle(group.key(slot)).action : option.action
        let devices = slot.writesBothBuds ? [GestureDevice.left, GestureDevice.right] : [group.device]
        return devices.map { device in
            state.set(action, for: GestureSlotKey(device: device, slot: slot.id))
            return .setGesture(device: device, button: slot.button, type: slot.type, action: action)
        }
    }

    /// Switches one mode of the slot's noise-control cycle. Returns nil (and changes nothing) if
    /// fewer than two modes would remain; otherwise the writes, which are empty unless the slot is
    /// currently set to the cycle.
    public func toggle(_ mode: NoiseCycle.Mode, slot: GestureSlot, in group: GestureGroup,
                       state: inout GestureState) -> [Request]? {
        let key = group.key(slot)
        guard let next = state.cycle(key).toggling(mode) else { return nil }
        state.setCycle(next, for: key)
        guard let current = state.action(key), slot.option(for: current)?.isNoiseCycle == true else { return [] }
        state.set(next.action, for: key)
        return [.setGesture(device: group.device, button: slot.button, type: slot.type, action: next.action)]
    }
}

// MARK: - Per-model definitions

extension GestureLayout {
    /// The layout for a model base. `smartKnob` comes from the firmware-matched config.
    public static func forModel(base: String, smartKnob: Bool = false) -> GestureLayout? {
        typealias O = GestureOption
        typealias T = GestureType
        let noAction = O("No action", 1), playPause = O("Play/pause", 2)
        let skipBack = O("Skip back", 8), skipForward = O("Skip forward", 9)
        let assistant = O("Voice assistant", 11), voiceAI = O("Voice AI", 11)
        let volumeUp = O("Volume up", 18), volumeDown = O("Volume down", 19)
        let lowLag = O("Low lag mode", 17), nc = O.noiseCycle
        let channelHop = O("Channel hop", 32), news = O("News reporter", 31), spatial = O("Spatial audio", 27)
        let micMute = O("Mic mute", 29), eqPreset = O("EQ preset", 34), essentialSpace = O("Essential space", 33)
        let camera = O("Camera shutter", 24), voiceRecording = O("Voice recording", 37)

        // Earbud slot families, by the wording each page uses.
        func four(_ verb: String, _ double: [O], _ triple: [O], _ hold: [O], _ doubleHold: [O]) -> [GestureSlot] {
            [
                GestureSlot("double", "Double \(verb)", type: T.double, options: double),
                GestureSlot("triple", "Triple \(verb)", type: T.triple, options: triple),
                GestureSlot("hold", "\(verb.capitalized) & hold", type: T.hold, options: hold),
                GestureSlot("doubleHold", "Double \(verb) & hold", type: T.doubleHold, options: doubleHold),
            ]
        }
        func buds(_ slots: [GestureSlot], case extra: GestureGroup? = nil) -> GestureLayout {
            GestureLayout(groups: [GestureGroup("Left", device: GestureDevice.left, slots: slots),
                                   GestureGroup("Right", device: GestureDevice.right, slots: slots)]
                          + (extra.map { [$0] } ?? []))
        }
        func headphone(_ buttonSingle: [O], _ buttonHold: [O], slider: [O]? = nil, roller: [O] = [nc, noAction]) -> GestureLayout {
            var groups = [GestureGroup("Button", device: GestureDevice.single, slots: [
                GestureSlot("button.single", "Single press", type: T.single, common: 10, button: 10, options: buttonSingle),
                GestureSlot("button.hold", "Press & hold", type: T.hold, common: 10, button: 10, options: buttonHold),
            ])]
            if let slider {
                groups.append(GestureGroup("Slider", device: GestureDevice.single, slots: [
                    GestureSlot("slider", "Energy slider", type: T.single, common: 5, button: 5, options: slider),
                ]))
            }
            groups.append(GestureGroup("Roller", device: GestureDevice.single, slots: [
                GestureSlot("roller.hold", "Press & hold", type: T.hold, common: 1, button: 1, options: roller),
            ]))
            return GestureLayout(groups: groups)
        }
        // Smart knob (CMF Buds Pro 2) and smart dial (CMF Clip Pro) on the case.
        func dial(hold: [O]) -> GestureGroup {
            let media = [playPause, skipForward, skipBack, assistant, lowLag, noAction]
            return GestureGroup("Dial", device: GestureDevice.case, slots: [
                GestureSlot("single", "Single press", type: T.single, common: 1, options: media),
                GestureSlot("double", "Double press", type: T.double, common: 1, options: media),
                GestureSlot("double.call", "Double press in call", type: T.double, common: 9, button: 9,
                            options: [O("Answer calls", 3), O("Answer + mute mic", 25), noAction]),
                GestureSlot("triple", "Triple press", type: T.triple, common: 1, options: media),
                GestureSlot("triple.call", "Triple press in call", type: T.triple, common: 9, button: 9,
                            options: [O("Hang up / decline", 26), noAction]),
                GestureSlot("hold", "Press & hold", type: T.hold, common: 1, options: hold),
                GestureSlot("rotate", "Rotate", type: T.rotate, common: 1, options: [O("Volume control", 23), noAction]),
            ])
        }

        let skips = [skipBack, skipForward, assistant]
        switch base {
        case "B181":
            return buds([
                GestureSlot("triple", "Triple tap", type: T.triple, options: skips + [noAction]),
                GestureSlot("hold", "Tap & hold", type: T.hold, options: [O("Change ANC type", 10), noAction]),
            ])
        case "B157":
            let noise = O("Noise control", 10)
            return buds(four("pinch", skips, skips, [volumeUp, volumeDown, assistant, noise],
                             [noAction, volumeUp, volumeDown, assistant, noise]))
        case "B155", "B171", "B162":
            return buds(four("pinch", skips, skips, [nc, volumeUp, volumeDown, assistant],
                             [nc, volumeUp, volumeDown, assistant, noAction]))
        case "B163":
            return buds(four("tap", [playPause] + skips, skips, [nc, assistant],
                             [volumeUp, volumeDown, assistant, noAction]))
        case "B172", "B195", "B179", "B197", "B184", "B168", "B185":
            let slots = four("tap", [playPause] + skips + [noAction], skips + [noAction], [nc, assistant, noAction],
                             [volumeUp, volumeDown, assistant, noAction])
            let knob = smartKnob && (base == "B172" || base == "B195")
            return buds(slots, case: knob ? dial(hold: [nc, assistant, lowLag, noAction]) : nil)
        case "B174":
            return buds(four("pinch", skips, skips, [volumeUp, volumeDown, assistant],
                             [volumeUp, volumeDown, assistant, noAction]))
        case "B173":
            let caseButton = GestureGroup("Case", device: GestureDevice.case, slots: [
                GestureSlot("hold", "Press & hold", type: T.hold, options: [essentialSpace, assistant, noAction]),
            ])
            return buds(four("pinch", skips, skips + [noAction],
                             [nc, volumeUp, volumeDown, assistant, O("Mic on/off", 29), noAction],
                             [nc, volumeUp, volumeDown, assistant, noAction]), case: caseButton)
        case "B190":
            let n = O("News", 31)
            let forwardFirst = [skipForward, skipBack, assistant, n]
            return buds(four("pinch", forwardFirst, forwardFirst + [noAction],
                             [nc, volumeUp, volumeDown, voiceRecording, assistant, n, micMute, noAction],
                             [nc, volumeUp, volumeDown, voiceRecording, assistant, n, noAction])
                        + [GestureSlot("both", "Pinch both buds", type: T.pinchBothBuds,
                                       options: [voiceRecording, noAction], writesBothBuds: true)])
        case "B189":
            let all = skips + [noAction], volume = [volumeUp, volumeDown, assistant, noAction]
            return buds(four("press", all, all, volume, volume), case: dial(hold: [assistant, lowLag, noAction]))
        case "B164":
            return GestureLayout(groups: [GestureGroup("Neckband", device: GestureDevice.single, slots: [
                GestureSlot("double", "Double press", type: T.double, options: skips),
                GestureSlot("triple", "Triple press", type: T.triple, options: skips),
                GestureSlot("hold", "Press & hold", type: T.hold, options: [nc]),
            ])])
        case "B170":
            return headphone([channelHop, voiceAI, news, nc, spatial, micMute, eqPreset, noAction],
                             [channelHop, voiceAI, news, nc, spatial, essentialSpace, micMute, eqPreset, noAction])
        case "B186":
            return headphone([channelHop, voiceAI, news, nc, camera, micMute, eqPreset, noAction],
                             [channelHop, voiceAI, news, nc, essentialSpace, micMute, eqPreset, noAction])
        case "B192":
            // ear-web shows News (31) on long press as No action; it isn't offered there.
            return headphone([voiceAI, news, nc, camera, micMute, noAction],
                             [voiceAI, nc, micMute, O("No action", 1, aliases: [31])])
        case "B175":
            let essentialNews = O("Essential news", 31), micOnOff = O("Mic on/off", 29)
            return headphone([essentialNews, voiceAI, nc, spatial, micOnOff, noAction],
                             [essentialNews, voiceAI, nc, spatial, essentialSpace, micOnOff, noAction],
                             slider: [O("Bass tuning", 35), O("Treble tuning", 36)], roller: [nc])
        default:
            return nil
        }
    }
}
