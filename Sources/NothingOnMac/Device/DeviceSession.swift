import Foundation
import HeadphoneProtocol
import Observation
import os

/// The connected device: which model it is, its firmware-matched config, and its features.
@MainActor @Observable
final class DeviceSession {
    let sku: DeviceSKU
    let profile: ModelProfile
    private(set) var firmware: String?
    /// Firmware-matched config; nil until the firmware arrives, or if no config matches it.
    private(set) var config: ModelConfig?
    private(set) var configLoaded = false
    /// Short message shown in the UI, e.g. why an action was refused.
    private(set) var notice: String?

    @ObservationIgnored private(set) var features: [any DeviceFeature] = []
    @ObservationIgnored private let configTable: ModelConfigTable?
    @ObservationIgnored private let transport: ([Request]) -> Void
    @ObservationIgnored private let rebootHandler: () -> Void
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.mdanishharoon.NothingOnMac", category: "session")

    init(sku: DeviceSKU, profile: ModelProfile, configTable: ModelConfigTable?,
         transport: @escaping ([Request]) -> Void, onReboot: @escaping () -> Void = {}) {
        self.sku = sku
        self.profile = profile
        self.configTable = configTable
        self.transport = transport
        self.rebootHandler = onReboot
        features = FeatureRegistry.make(self)
    }

    /// Sends the connect-time reads (ear-web's initDevice).
    func start() {
        var requests: [Request] = [.readFirmware]
        if profile.sendsUTCTime {
            requests.append(.setTime(epochSeconds: UInt32(Date().timeIntervalSince1970)))
        }
        for feature in features where feature.isAvailable {
            requests += feature.initialReads
        }
        transport(requests)
    }

    func send(_ requests: Request...) {
        send(requests)
    }

    func send(_ requests: [Request]) {
        // A view can still hold a feature of an ended session; it must not reach a new device.
        guard !isClosed else { return }
        transport(requests)
    }

    @ObservationIgnored private var isClosed = false

    /// Ends the session: stops sending and releases the features (which hold the session
    /// strongly, so they stay valid for any view still showing them).
    func close() {
        isClosed = true
        features = []
    }

    func feature<T: DeviceFeature>(_ type: T.Type) -> T? {
        features.lazy.compactMap { $0 as? T }.first
    }

    /// True if no feature vetoes `action`; otherwise shows the reason and returns false.
    func permits(_ action: GuardedAction) -> Bool {
        guard let reason = features.lazy.compactMap({ $0.blockReason(for: action) }).first else { return true }
        show(reason)
        return false
    }

    func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    /// Call before a write that makes the device restart (codec, some dual-connection toggles,
    /// long battery mode): the controller then waits for it and reconnects.
    func expectReboot() {
        rebootHandler()
    }

    func receive(_ frame: Frame) {
        // 0x7xxx frames acknowledge our 0xFxxx writes; nothing needs them.
        if frame.command & 0xF000 == 0x7000 { return }
        if frame.command == 0x4042, case .firmware(let version)? = DeviceMessage(frame: frame) {
            loadConfig(firmware: version)
            return
        }
        for feature in features where feature.handle(frame) {
            return
        }
        log.debug("unhandled 0x\(String(frame.command, radix: 16), privacy: .public)")
    }

    /// Runs on every firmware reply, so a refresh (which re-reads the firmware) also re-reads
    /// the config-gated settings.
    private func loadConfig(firmware version: String) {
        firmware = version
        config = configTable?.config(base: profile.base, firmware: version)
        configLoaded = true
        if config == nil {
            log.info("no config for \(self.profile.base, privacy: .public) firmware \(version, privacy: .public)")
        }
        var requests: [Request] = []
        for feature in features {
            requests += feature.configDidLoad()
        }
        transport(requests)
    }
}
