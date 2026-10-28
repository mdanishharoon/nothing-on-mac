import AppKit
import HeadphoneProtocol
import Observation
import os

/// Owns the Bluetooth link, identifies the connected model and runs a `DeviceSession` for it.
@MainActor @Observable
final class HeadphoneController {
    enum Status: Equatable {
        case searching
        case connecting(String)
        case restarting
        case connected
        case unavailable(String)
    }

    private(set) var status: Status = .searching
    private(set) var session: DeviceSession?
    /// Model to picture while disconnected: the current one, else the last one seen.
    private(set) var displayModel: DeviceSKU?
    /// Bluetooth off or access denied; checked whenever the menu opens and on status changes.
    private(set) var bluetoothIssue: BluetoothIssue?

    @ObservationIgnored let catalog: DeviceCatalog?
    @ObservationIgnored private let configs: ModelConfigTable?
    @ObservationIgnored private let link = RFCOMMLink()
    @ObservationIgnored private var encoder = PacketEncoder()
    @ObservationIgnored private var parser = FrameParser()
    @ObservationIgnored private var outbox: [Request] = []
    @ObservationIgnored private var draining = false
    @ObservationIgnored private var identifiedSKU: String?
    @ObservationIgnored private var batteryRefresh: Task<Void, Never>?
    @ObservationIgnored private var rebootExpected = false
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.mdanishharoon.NothingOnMac", category: "device")
    @ObservationIgnored private static let lastSKUKey = "lastSKU"

    init() {
        catalog = AppResources.data("catalog").flatMap { try? DeviceCatalog(json: $0) }
        configs = AppResources.data("ear_config").flatMap { try? ModelConfigTable(json: $0) }
        displayModel = UserDefaults.standard.string(forKey: Self.lastSKUKey).flatMap { catalog?.model(sku: $0) }
        link.onEvent = { [weak self] in self?.handle($0) }
        link.onBytes = { [weak self] in self?.receive($0) }
        link.start()
        checkBluetooth()
        // Bluetooth links drop while the Mac sleeps; pick the device up again on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnectAfterWake() }
        }
    }

    func checkBluetooth() {
        bluetoothIssue = BluetoothIssue.current()
    }

    private func reconnectAfterWake() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.session == nil else { return }
            self.checkBluetooth()
            self.link.connect(reportMissing: false)
        }
    }

    /// Offline controller for preview rendering: no Bluetooth, replies fed in by hand.
    init(preview model: DeviceSKU?, status: Status, catalog: DeviceCatalog?, configs: ModelConfigTable?) {
        self.catalog = catalog
        self.configs = configs
        self.status = status
        displayModel = model
        if status == .connected, let model, let profile = ModelProfile.profile(base: model.base) {
            session = DeviceSession(sku: model, profile: profile, configTable: configs, transport: { _ in })
        }
    }

    func reconnect() {
        status = .searching
        link.disconnect()
        link.connect()
    }

    func refresh() {
        session?.start()
    }

    // MARK: - Link events

    private func handle(_ event: RFCOMMLink.Event) {
        switch event {
        case .connecting(let name):
            reconnectTask?.cancel()
            status = rebootExpected ? .restarting : .connecting(name)
        case .identified(let message):
            identifiedSKU = FastPair.sku(fromMessage: message)
            log.info("Fast Pair model \(self.identifiedSKU ?? "?", privacy: .public)")
        case .opened(let name):
            rebootExpected = false
            startSession(bluetoothName: name)
        case .closed:
            endSession()
            if rebootExpected {
                status = .restarting
                scheduleReconnect()
            } else {
                status = .searching
            }
        case .failed(let message):
            endSession()
            status = rebootExpected ? .restarting : .unavailable(message)
        }
    }

    private func startSession(bluetoothName: String) {
        let model = identifiedSKU.flatMap { catalog?.model(sku: $0) }
            ?? displayModel.flatMap { bluetoothName.localizedCaseInsensitiveContains($0.name) ? $0 : nil }
            ?? catalog?.model(bluetoothName: bluetoothName)
        guard let model, let profile = ModelProfile.profile(base: model.base) else {
            status = .unavailable("\(bluetoothName) isn't a supported Nothing or CMF device.")
            link.disconnect()
            return
        }
        displayModel = model
        UserDefaults.standard.set(model.sku, forKey: Self.lastSKUKey)
        parser = FrameParser()
        let session = DeviceSession(
            sku: model, profile: profile, configTable: configs,
            transport: { [weak self] in self?.enqueue($0) },
            onReboot: { [weak self] in self?.rebootExpected = true })
        self.session = session
        status = .connected
        session.start()
        startBatteryRefresh()
    }

    private func endSession() {
        batteryRefresh?.cancel()
        batteryRefresh = nil
        outbox.removeAll()
        session?.close()
        session = nil
        identifiedSKU = nil
    }

    /// After a deliberate restart, give the device 10 s, then retry every 5 s (ear-web's timing).
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            for _ in 0..<6 {
                guard let self, !Task.isCancelled, self.session == nil else { return }
                self.link.connect(reportMissing: false)
                try? await Task.sleep(for: .seconds(5))
            }
            guard let self, !Task.isCancelled, self.session == nil else { return }
            self.rebootExpected = false
            self.status = .searching
        }
    }

    private func receive(_ bytes: [UInt8]) {
        for frame in parser.append(bytes) {
            session?.receive(frame)
        }
    }

    // MARK: - Sending

    /// Queues requests and writes them 100 ms apart, the pacing ear-web uses.
    private func enqueue(_ requests: [Request]) {
        outbox += requests
        guard !draining else { return }
        draining = true
        Task {
            while !outbox.isEmpty {
                link.write(encoder.encode(outbox.removeFirst()))
                try? await Task.sleep(for: .milliseconds(100))
            }
            draining = false
        }
    }

    private func startBatteryRefresh() {
        batteryRefresh?.cancel()
        batteryRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                self?.enqueue([.readBattery])
            }
        }
    }
}
