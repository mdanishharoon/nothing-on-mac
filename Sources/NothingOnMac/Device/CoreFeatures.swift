import HeadphoneProtocol
import Observation

extension FeatureRegistry {
    static func coreFeatures(_ session: DeviceSession) -> [any DeviceFeature] {
        [BatteryFeature(session), NoiseControlFeature(session), EQFeature(session),
         SpatialAudioFeature(session), LowLatencyFeature(session)]
    }
}

@MainActor @Observable
final class BatteryFeature: DeviceFeature {
    @ObservationIgnored let session: DeviceSession
    private(set) var readings: [UInt8: BatteryReading] = [:]

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { true }
    var initialReads: [Request] { [.readBattery] }

    /// Single-unit battery, or the lower of the two buds, for the menu bar figure.
    var summary: BatteryReading? {
        if let single = readings[BatteryReading.headphones] { return single }
        let buds = [readings[BatteryReading.left], readings[BatteryReading.right]].compactMap { $0 }
        return buds.min { $0.level < $1.level }
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .battery(let values)? = DeviceMessage(frame: frame) else { return false }
        // A report lists only the components present; anything missing has disconnected.
        readings = Dictionary(values.map { ($0.component, $0) }, uniquingKeysWith: { _, last in last })
        return true
    }
}

@MainActor @Observable
final class NoiseControlFeature: DeviceFeature {
    @ObservationIgnored let session: DeviceSession
    private(set) var mode: NoiseControl?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool {
        switch session.profile.anc {
        case .none: return false
        case .cancellingOff:
            // Ear (stick) only has ANC on firmware x.x.2.x.
            guard let firmware = session.firmware else { return false }
            let parts = firmware.split(separator: ".")
            return parts.count > 2 && parts[2] == "2"
        default: return true
        }
    }

    var hasTransparency: Bool {
        switch session.profile.anc {
        case .none, .cancellingOff: false
        case .full: (session.config?.int("ancLevel") ?? 0x10) & 0x10 != 0
        default: true
        }
    }

    var strengths: [ANCStrength] {
        switch session.profile.anc {
        case .full: ANCStrength.available(ancLevel: session.config?.int("ancLevel") ?? 0)
        case .lowHigh: [.high, .low]
        case .highMidLow: [.high, .mid, .low]
        default: []
        }
    }

    var initialReads: [Request] {
        session.profile.anc == .cancellingOff ? [] : [.readNoiseControl]
    }

    func configDidLoad() -> [Request] {
        session.profile.anc == .cancellingOff && isAvailable ? [.readNoiseControl] : []
    }

    func set(_ newMode: NoiseControl) {
        if newMode == .transparency, !session.permits(.selectTransparency) { return }
        mode = newMode
        session.send(.setNoiseControl(newMode))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .noiseControl(let value)? = DeviceMessage(frame: frame) else { return false }
        mode = value
        return true
    }
}

@MainActor @Observable
final class EQFeature: DeviceFeature {
    @ObservationIgnored let session: DeviceSession
    /// Last EQ level the device reported or we set.
    private(set) var level: UInt8?
    /// Advanced (parametric) EQ is on; it overrides `level`.
    private(set) var advancedActive = false
    /// Bound to the custom sliders; sent with `commitCustomEQ()`.
    var customEQ = CustomEQ.flat

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { true }
    private var profile: ModelProfile { session.profile }

    var initialReads: [Request] {
        [.readEQ(profile.eqFamily)] + (profile.hasAdvancedEQ ? [.readAdvancedEQStatus] : [])
    }

    var isCustom: Bool { !advancedActive && level != nil && level == profile.customLevel }

    func isSelected(_ option: EQPresetOption) -> Bool {
        !advancedActive && level == option.level
    }

    /// A level the device reported that has no button (e.g. a hidden Dirac Opteo).
    var unlistedLevelName: String? {
        guard !advancedActive, let level, level != profile.customLevel,
              !profile.presets.contains(where: { $0.level == level }) else { return nil }
        return level == profile.hiddenDiracLevel ? "Dirac Opteo" : nil
    }

    func select(_ option: EQPresetOption) { select(level: option.level) }

    func selectCustom() {
        guard let custom = profile.customLevel else { return }
        select(level: custom)
    }

    private func select(level newLevel: UInt8) {
        guard session.permits(.selectEQPreset(level: newLevel)) else { return }
        if isDirac(newLevel), !session.permits(.selectDiracOpteo) { return }
        var requests: [Request] = []
        if profile.hasAdvancedEQ { requests.append(.setAdvancedEQ(false)) }
        requests.append(.setEQ(level: newLevel, family: profile.eqFamily))
        if newLevel == profile.customLevel { requests.append(.readCustomEQ) }
        advancedActive = false
        level = newLevel
        session.send(requests)
    }

    func selectAdvanced() {
        guard profile.hasAdvancedEQ, session.permits(.enableAdvancedEQ) else { return }
        advancedActive = true
        session.send(.setAdvancedEQ(true))
    }

    func commitCustomEQ() {
        if let custom = profile.customLevel, !session.permits(.selectEQPreset(level: custom)) { return }
        guard let bands = session.config?.customEQBands else {
            session.show("Custom EQ isn't available on this firmware.")
            return
        }
        session.send(.setCustomEQ(customEQ, bands: bands))
    }

    private func isDirac(_ level: UInt8) -> Bool {
        profile.eqFamily == .listeningMode && (level == 0 || (level == 7 && profile.base == "B185"))
    }

    func handle(_ frame: Frame) -> Bool {
        switch DeviceMessage(frame: frame) {
        case .eqLevel(let value):
            level = value
            if value == profile.customLevel { session.send(.readCustomEQ) }
        case .advancedEQEnabled(let enabled):
            advancedActive = enabled && profile.hasAdvancedEQ
        case .customEQ(let eq):
            customEQ = eq
        default:
            return false
        }
        return true
    }

    func blockReason(for action: GuardedAction) -> String? {
        guard action == .enableSpatialAudio, advancedActive, session.config?.flag("mutuallyExclusive") == true else { return nil }
        return "Spatial audio isn't available while Advanced EQ is on."
    }
}

@MainActor @Observable
final class SpatialAudioFeature: DeviceFeature {
    @ObservationIgnored let session: DeviceSession
    private(set) var mode: SpatialAudioMode?

    init(_ session: DeviceSession) { self.session = session }

    var modes: [SpatialAudioMode] {
        SpatialAudioMode.available(mask: session.config?.int("spatialAudio") ?? 0)
    }

    var isAvailable: Bool {
        guard let config = session.config else { return false }
        return (config.int("spatialAudio") ?? 0) != 0 && !config.flag("useAudiodoSpatial")
    }

    func configDidLoad() -> [Request] {
        isAvailable ? [.readSpatialAudio] : []
    }

    func set(_ newMode: SpatialAudioMode) {
        if newMode != .off, !session.permits(.enableSpatialAudio) { return }
        mode = newMode
        session.send(.setSpatialAudio(newMode))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .spatialAudio(let value)? = DeviceMessage(frame: frame) else { return false }
        // Collapse modes this model doesn't offer (e.g. a junk head byte) onto Fixed / Off.
        mode = modes.contains(value) ? value : (value == .headTracked && modes.contains(.fixed) ? .fixed : value)
        return true
    }

    func blockReason(for action: GuardedAction) -> String? {
        guard let mode, mode != .off, session.config?.flag("mutuallyExclusive") == true else { return nil }
        switch action {
        case .enableBass: return "Bass enhance isn't available while spatial audio is on."
        case .enableAdvancedEQ: return "Advanced EQ isn't available while spatial audio is on."
        default: return nil
        }
    }
}

@MainActor @Observable
final class LowLatencyFeature: DeviceFeature {
    @ObservationIgnored let session: DeviceSession
    private(set) var enabled: Bool?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { true }
    var initialReads: [Request] { [.readLowLatency] }

    func set(_ value: Bool) {
        enabled = value
        session.send(.setLowLatency(value))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .lowLatency(let value)? = DeviceMessage(frame: frame) else { return false }
        enabled = value
        return true
    }
}
