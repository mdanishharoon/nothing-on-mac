import HeadphoneProtocol
import Observation

// Gestures (earbud / single-unit / case-dial topologies). Owned by the gestures work stream.

extension FeatureRegistry {
    static func gestureFeatures(_ session: DeviceSession) -> [any DeviceFeature] {
        [GestureFeature(session)]
    }
}

/// Button, pinch, tap, slider, roller and case knob / dial remapping (0xC018 / 0x4018 / 0xF003).
@MainActor @Observable
final class GestureFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var state = GestureState()

    init(_ session: DeviceSession) { self.session = session }

    /// The smart knob only exists when the firmware-matched config says so (B172 / B195).
    private var hasSmartKnob: Bool { session.config?.flag("smartKnob") == true }

    var layout: GestureLayout? {
        GestureLayout.forModel(base: session.profile.base, smartKnob: hasSmartKnob)
    }

    var isAvailable: Bool { layout != nil }
    var initialReads: [Request] { [.readGestures] }

    /// Knob records that arrived before the config was known were skipped, so read again.
    func configDidLoad() -> [Request] {
        hasSmartKnob ? [.readGestures] : []
    }

    func refresh() {
        guard isAvailable else { return }
        session.send(.readGestures)
    }

    func select(_ option: GestureOption, slot: GestureSlot, in group: GestureGroup) {
        guard let layout else { return }
        session.send(layout.select(option, slot: slot, in: group, state: &state))
    }

    func toggle(_ mode: NoiseCycle.Mode, slot: GestureSlot, in group: GestureGroup) {
        guard let layout else { return }
        let key = group.key(slot)
        if mode == .transparency, !state.cycle(key).contains(.transparency), !session.permits(.selectTransparency) {
            return
        }
        guard let writes = layout.toggle(mode, slot: slot, in: group, state: &state) else {
            session.show("Keep at least two modes in the cycle.")
            return
        }
        session.send(writes)
    }

    func handle(_ frame: Frame) -> Bool {
        guard let records = GestureRecord.records(from: frame) else { return false }
        layout?.apply(records, to: &state)
        return true
    }
}
