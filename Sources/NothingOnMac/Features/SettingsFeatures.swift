import Foundation
import HeadphoneProtocol
import Observation

// In-ear detection, ear-tip fit test, find device, case LED, personalised ANC, dual connection,
// codec, personal sound, super mic / mic mode / walkie-talkie, call transparency, long battery
// mode, anti-leakage. Owned by the settings work stream.

extension FeatureRegistry {
    static func settingsFeatures(_ session: DeviceSession) -> [any DeviceFeature] {
        [InEarDetectionFeature(session), EarTipTestFeature(session), FindDeviceFeature(session),
         CaseLEDFeature(session), PersonalisedANCFeature(session), DualConnectionFeature(session),
         AudioCodecFeature(session), PersonalSoundFeature(session), SuperMicFeature(session),
         WalkieTalkieFeature(session), CallTransparencyFeature(session), LongPowerModeFeature(session),
         AntiLeakageFeature(session)]
    }
}

// MARK: - Profile-gated

@MainActor @Observable
final class InEarDetectionFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?

    init(_ session: DeviceSession) { self.session = session }

    /// "In-ear detection", or "Over-ear detection" on headphones.
    var title: String { session.profile.inEarDetectionLabel ?? "In-ear detection" }
    var isAvailable: Bool { session.profile.inEarDetectionLabel != nil }
    var initialReads: [Request] { isAvailable ? [.readInEarDetection] : [] }

    func set(_ value: Bool) {
        enabled = value
        session.send(.setInEarDetection(value))
    }

    func handle(_ frame: Frame) -> Bool {
        guard frame.command == 0x400E else { return false }
        if isAvailable, case .inEarDetection(let value)? = SettingsMessage(frame: frame) { enabled = value }
        return true
    }
}

@MainActor @Observable
final class EarTipTestFeature: DeviceFeature {
    enum State: Equatable {
        case idle
        case testing
        case result(EarTipResult)
        /// No result arrived in time.
        case timedOut
    }

    @ObservationIgnored unowned let session: DeviceSession
    private(set) var state: State = .idle
    @ObservationIgnored private var timeout: Task<Void, Never>?

    /// ear-web waits forever; give up after this long so the row doesn't pulse indefinitely.
    static let timeoutSeconds = 30

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.profile.earTipFitTest && session.profile.formFactor == .earbuds }

    func start() {
        guard isAvailable else { return }
        state = .testing
        session.send(.startEarTipTest)
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeoutSeconds))
            guard !Task.isCancelled, let self, self.state == .testing else { return }
            self.state = .timedOut
        }
    }

    func dismiss() {
        timeout?.cancel()
        state = .idle
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .earTipResult(let result)? = SettingsMessage(frame: frame) else { return false }
        timeout?.cancel()
        state = .result(result)
        return true
    }
}

@MainActor @Observable
final class FindDeviceFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    /// Targets currently ringing. There is no status read; this is our own toggle state.
    private(set) var ringing: Set<Side> = []

    enum Side: Hashable { case left, right, single }

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { true }

    /// Buttons to show: one per bud for most earbuds, one for headphones, neckbands and Ear (1).
    var sides: [Side] {
        session.profile.ring == .perSide ? [.left, .right] : [.single]
    }

    func toggle(_ side: Side) {
        let on = !ringing.contains(side)
        if on { ringing.insert(side) } else { ringing.remove(side) }
        session.send(.ring(target(side), on: on))
    }

    func stopAll() {
        for side in ringing { toggle(side) }
    }

    private func target(_ side: Side) -> RingTarget {
        switch session.profile.ring {
        case .both: .both
        case .single: .single
        case .perSide: side == .right ? .right : .left
        }
    }

    func handle(_ frame: Frame) -> Bool { false }
}

@MainActor @Observable
final class CaseLEDFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var colours: CaseLEDColours?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.profile.caseLED }

    /// ear-web reads the colours only when the editor opens.
    func load() {
        guard isAvailable else { return }
        session.send(.readCaseLED)
    }

    func set(_ slot: CaseLEDColours.Slot, to colour: RGB) {
        guard var updated = colours else { return }
        updated[slot] = colour
        colours = updated
        session.send(.setCaseLED(updated))
    }

    func handle(_ frame: Frame) -> Bool {
        guard frame.command == 0x4017 else { return false }
        if isAvailable, case .caseLED(let value)? = SettingsMessage(frame: frame) { colours = value }
        return true
    }
}

@MainActor @Observable
final class PersonalisedANCFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.profile.personalisedANC }
    var initialReads: [Request] { isAvailable ? [.readPersonalisedANC] : [] }

    func set(_ value: Bool) {
        enabled = value
        session.send(.setPersonalisedANC(value))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .personalisedANC(let value)? = SettingsMessage(frame: frame) else { return false }
        enabled = value
        return true
    }
}

// MARK: - Config-gated

@MainActor @Observable
final class DualConnectionFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?
    private(set) var devices: [DualConnectionDevice] = []
    /// True once a list page has arrived.
    private(set) var listLoaded = false
    /// MACs with a connect/disconnect in flight (cleared by the next list or event).
    private(set) var pending: Set<[UInt8]> = []

    @ObservationIgnored private var pageRequests = 0
    /// The next page starts a fresh list (ear-web clears its list on every full fetch).
    @ObservationIgnored private var startFresh = true
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    static let maxPageRequests = 20
    static let maxConnected = 2
    static let refreshDelay = Duration.milliseconds(300)

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.config?.flag("dualConnection") == true }
    var restartsOnToggle: Bool { session.config?.flag("dualConnectionReboot") == true }
    var connectedCount: Int { devices.filter(\.isConnected).count }

    func configDidLoad() -> [Request] {
        guard isAvailable else { return [] }
        return [.readDualConnection, firstPageRequest()]
    }

    /// Writes the toggle. Callers confirm first when `restartsOnToggle`.
    func setEnabled(_ value: Bool) {
        if restartsOnToggle { session.expectReboot() }
        enabled = value
        session.send(.setDualConnection(value))
        if value { scheduleRefresh() }
    }

    func setConnected(_ device: DualConnectionDevice, _ connect: Bool) {
        if connect, !device.isConnected, connectedCount >= Self.maxConnected {
            session.show("Disconnect a device first: up to \(Self.maxConnected) can be connected at once.")
            return
        }
        pending.insert(device.mac)
        session.send(.dualConnect(mac: device.mac, connect: connect))
        scheduleRefresh()
    }

    /// Re-reads the whole list from offset 0.
    func refresh() {
        guard isAvailable else { return }
        session.send(firstPageRequest())
    }

    private func firstPageRequest() -> Request {
        startFresh = true
        pageRequests = 1
        return .readDualConnectionDevices(offset: 0)
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDelay)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func handle(_ frame: Frame) -> Bool {
        guard let message = SettingsMessage(frame: frame) else { return false }
        switch message {
        case .dualConnectionEnabled(let value):
            enabled = value
        case .dualConnectionPage(let page):
            merge(page)
        case .dualConnectionEvent(let mac, let connected):
            pending.remove(mac)
            if let index = devices.firstIndex(where: { $0.mac == mac }) {
                devices[index].isConnected = connected
            } else {
                refresh()
            }
        default:
            return false
        }
        return true
    }

    private func merge(_ page: DualConnectionPage) {
        var list = startFresh ? [] : devices
        if startFresh { pending.removeAll() }
        startFresh = false
        var added = false
        for device in page.devices {
            if let index = list.firstIndex(where: { $0.mac == device.mac }) {
                list[index] = device
            } else {
                list.append(device)
                added = true
            }
        }
        devices = list
        listLoaded = true
        // Keep paging while pages add new devices.
        if added, pageRequests < Self.maxPageRequests {
            pageRequests += 1
            session.send(.readDualConnectionDevices(offset: list.count))
        }
    }
}

@MainActor @Observable
final class AudioCodecFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var codec: AudioCodec?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { (session.config?.int("highQualityAudio") ?? 0) != 0 }
    var codecs: [AudioCodec] { AudioCodec.available(highQualityAudio: session.config?.int("highQualityAudio") ?? 0) }

    func configDidLoad() -> [Request] { isAvailable ? [.readCodec] : [] }

    /// Whether switching to `codec` may go ahead (to the restart confirmation). Shows why not.
    func canSelect(_ codec: AudioCodec) -> Bool {
        codec != self.codec && session.permits(.changeCodec)
    }

    /// Writes the codec; the device restarts. Call only after the user confirmed.
    func select(_ codec: AudioCodec) {
        guard canSelect(codec) else { return }
        session.expectReboot()
        self.codec = codec
        session.send(.setCodec(codec))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .codec(let value)? = SettingsMessage(frame: frame) else { return false }
        codec = value
        return true
    }

    func blockReason(for action: GuardedAction) -> String? {
        guard codec == .ldac else { return nil }
        switch action {
        case .selectDiracOpteo where session.config?.int("diracOpteoSupport") == 1:
            return "Dirac Opteo isn't available while LDAC is on."
        case .enablePersonalSound where session.config?.flag("mimi") == true:
            return "Personal sound profile isn't available while LDAC is on."
        default:
            return nil
        }
    }
}

@MainActor @Observable
final class PersonalSoundFeature: DeviceFeature {
    enum Backend { case mimi, audiodo }

    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?

    init(_ session: DeviceSession) { self.session = session }

    /// Mimi wins over Audiodo (ear-web's personalSoundProfileBackend).
    var backend: Backend? {
        guard let config = session.config else { return nil }
        if config.flag("mimi") { return .mimi }
        if config.flag("audiodo") { return .audiodo }
        return nil
    }

    var isAvailable: Bool { backend != nil }

    func configDidLoad() -> [Request] {
        switch backend {
        case .mimi: [.readMimi]
        case .audiodo: [.readAudiodo]
        case nil: []
        }
    }

    func set(_ value: Bool) {
        guard let backend else { return }
        if value, !session.permits(.enablePersonalSound) { return }
        enabled = value
        session.send(backend == .mimi ? .setMimi(value) : .setAudiodo(value))
    }

    func handle(_ frame: Frame) -> Bool {
        switch SettingsMessage(frame: frame) {
        case .mimi(let value)?:
            if backend == .mimi { enabled = value }
        case .audiodo(let value)?, .audiodoPush(let value)?:
            if backend == .audiodo { enabled = value }
        default:
            return false
        }
        return true
    }
}

@MainActor @Observable
final class SuperMicFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?
    private(set) var micMode: MicMode?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.config?.flag("superMic") == true }

    func configDidLoad() -> [Request] { isAvailable ? [.readSuperMic, .readMicMode] : [] }

    func set(_ value: Bool) {
        enabled = value
        session.send(.setSuperMic(value))
    }

    func setMicMode(_ mode: MicMode) {
        micMode = mode
        session.send(.setMicMode(mode))
    }

    func handle(_ frame: Frame) -> Bool {
        switch SettingsMessage(frame: frame) {
        case .superMic(let value)?: enabled = value
        case .micMode(let value)?: micMode = value
        default: return false
        }
        return true
    }
}

@MainActor @Observable
final class WalkieTalkieFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.config?.flag("walkieTalkieMode") == true }

    func configDidLoad() -> [Request] { isAvailable ? [.readWalkieTalkie] : [] }

    func set(_ value: Bool) {
        enabled = value
        session.send(.setWalkieTalkie(value))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .walkieTalkie(let value)? = SettingsMessage(frame: frame) else { return false }
        enabled = value
        return true
    }
}

@MainActor @Observable
final class CallTransparencyFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.config?.flag("callTransparency") == true }

    func configDidLoad() -> [Request] { isAvailable ? [.readCallTransparency] : [] }

    func set(_ value: Bool) {
        enabled = value
        session.send(.setCallTransparency(value))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .callTransparency(let value)? = SettingsMessage(frame: frame) else { return false }
        enabled = value
        return true
    }
}

@MainActor @Observable
final class LongPowerModeFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.config?.flag("longPowerMode") == true }

    func configDidLoad() -> [Request] { isAvailable ? [.readLongPowerMode] : [] }

    /// Writes the mode; the device restarts. Call only after the user confirmed.
    func set(_ value: Bool) {
        session.expectReboot()
        enabled = value
        session.send(.setLongPowerMode(value))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .longPowerMode(let value)? = SettingsMessage(frame: frame) else { return false }
        enabled = value
        return true
    }

    func blockReason(for action: GuardedAction) -> String? {
        guard enabled == true else { return nil }
        switch action {
        case .changeCodec: return "The codec can't change while Long battery life mode is on."
        case .enableSpatialAudio: return "Spatial audio isn't available in Long battery life mode."
        case .selectEQPreset: return "The equaliser is locked in Long battery life mode."
        case .enableBass: return "Bass enhancement isn't available in Long battery life mode."
        default: return nil
        }
    }
}

@MainActor @Observable
final class AntiLeakageFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var mode: AntiLeakageMode?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.config?.flag("supportLeakageProtection") == true }

    func configDidLoad() -> [Request] { isAvailable ? [.readAntiLeakage] : [] }

    func set(_ value: AntiLeakageMode) {
        mode = value
        session.send(.setAntiLeakage(value))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .antiLeakage(let value)? = SettingsMessage(frame: frame) else { return false }
        mode = value
        return true
    }

    func blockReason(for action: GuardedAction) -> String? {
        guard mode == .audioAndCalls, case .selectEQPreset = action else { return nil }
        return "The equaliser is locked while anti-leakage covers audio and calls."
    }
}
