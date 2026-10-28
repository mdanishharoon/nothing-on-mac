import IOBluetooth
import os

/// Finds the connected headphones and holds the RFCOMM channel to their control service.
///
/// Connecting is two steps, as in ear-web: a short-lived channel to the Fast Pair service, which
/// sends a 7-byte message carrying the model ID (and so the colourway), then the control channel.
@MainActor
final class RFCOMMLink: NSObject {
    enum Event {
        case connecting(String)
        case identified(modelMessage: [UInt8])
        case opened(String)
        case closed
        case failed(String)
    }

    var onEvent: ((Event) -> Void)?
    var onBytes: (([UInt8]) -> Void)?

    /// Control service the Nothing X app talks to (ear-web's SPP_UUID).
    private static let controlServiceUUID = uuid([0xAE, 0xAC, 0x4A, 0x03, 0xDF, 0xF5, 0x49, 0x8F,
                                                  0x84, 0x3A, 0x34, 0x48, 0x7C, 0xF1, 0x33, 0xEB])
    /// Fast Pair service that announces the model ID (ear-web's FASTPAIR_UUID).
    private static let fastPairServiceUUID = uuid([0xDF, 0x21, 0xFE, 0x2C, 0x25, 0x15, 0x4F, 0xDB,
                                                   0x88, 0x86, 0xF1, 0x2C, 0x4D, 0x67, 0x92, 0x7C])

    private let log = Logger(subsystem: "io.github.mdanishharoon.NothingOnMac", category: "rfcomm")
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var probeChannel: IOBluetoothRFCOMMChannel?
    private var probeBuffer: [UInt8] = []
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        connect(reportMissing: false)
    }

    /// Looks for connected headphones among paired devices and opens the control channel.
    func connect(reportMissing: Bool = true) {
        guard device == nil else { return }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard let match = paired.first(where: { $0.isConnected() && Self.isHeadphones($0) }) else {
            if reportMissing {
                onEvent?(.failed("Connect your CMF Headphone Pro to this Mac first."))
            }
            return
        }
        open(match)
    }

    func disconnect() {
        probeChannel?.close()
        channel?.close()
        reset()
    }

    func write(_ bytes: [UInt8]) {
        guard let channel, channel.isOpen() else { return }
        log.debug("tx \(Self.hex(bytes), privacy: .public)")
        var buffer = bytes
        let result = buffer.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        if result != kIOReturnSuccess {
            log.error("write failed: \(Self.describe(result), privacy: .public)")
        }
    }

    private static func isHeadphones(_ device: IOBluetoothDevice) -> Bool {
        if let name = device.name, name.localizedCaseInsensitiveContains("CMF Headphone") {
            return true
        }
        return device.getServiceRecord(for: controlServiceUUID) != nil
    }

    // MARK: - Connecting

    private func open(_ device: IOBluetoothDevice) {
        self.device = device
        let name = device.name ?? "Headphones"
        log.info("connecting to \(name, privacy: .public) [\(device.addressString ?? "?", privacy: .public)]")
        onEvent?(.connecting(name))
        disconnectNotification = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))

        if Self.channelID(of: Self.controlServiceUUID, on: device) != nil {
            identify(device)
        } else {
            // The service records aren't cached yet; ask the headphones for them.
            let result = device.performSDPQuery(self, uuids: [Self.controlServiceUUID, Self.fastPairServiceUUID])
            if result != kIOReturnSuccess {
                fail("Service lookup failed (\(Self.describe(result))).")
            }
        }
    }

    private func identify(_ device: IOBluetoothDevice) {
        guard let channelID = Self.channelID(of: Self.fastPairServiceUUID, on: device) else {
            openControl(on: device)
            return
        }
        log.info("opening Fast Pair channel \(channelID)")
        var probe: IOBluetoothRFCOMMChannel?
        guard device.openRFCOMMChannelAsync(&probe, withChannelID: channelID, delegate: self) == kIOReturnSuccess,
              let probe else {
            openControl(on: device)
            return
        }
        probeChannel = probe
        probeBuffer = []
        let id = ObjectIdentifier(probe)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, let current = self.probeChannel, ObjectIdentifier(current) == id else { return }
            self.log.info("Fast Pair channel sent nothing, skipping model detection")
            self.finishIdentify()
        }
    }

    private func finishIdentify(with message: [UInt8]? = nil) {
        guard let probe = probeChannel else { return }
        probeChannel = nil
        probe.close()
        if let message {
            onEvent?(.identified(modelMessage: message))
        }
        guard let device else { return }
        // Give the headphones a moment to tear down the Fast Pair channel.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.device === device, self.channel == nil else { return }
            self.openControl(on: device)
        }
    }

    private func openControl(on device: IOBluetoothDevice) {
        guard let channelID = Self.channelID(of: Self.controlServiceUUID, on: device) else {
            fail("These headphones don't expose the control service.")
            return
        }
        log.info("opening control channel \(channelID)")
        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess else {
            fail("Couldn't open the control channel (\(Self.describe(result))).")
            return
        }
        self.channel = channel
    }

    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        probeChannel?.close()
        channel?.close()
        reset()
        onEvent?(.failed(message))
    }

    private func reset() {
        disconnectNotification?.unregister()
        disconnectNotification = nil
        probeChannel = nil
        channel = nil
        device = nil
    }

    // MARK: - Callbacks
    //
    // IOBluetooth delivers notifications and delegate callbacks on its own queues, so every
    // callback is nonisolated and hops to the main actor. Devices and channels aren't Sendable;
    // they cross over as an address string or an ObjectIdentifier.

    nonisolated private func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(work) }
    }

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        onMain {
            guard self.device == nil, let device = IOBluetoothDevice(addressString: address),
                  Self.isHeadphones(device) else { return }
            self.open(device)
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString
        onMain {
            guard address != nil, address == self.device?.addressString else { return }
            self.log.info("headphones disconnected")
            self.reset()
            self.onEvent?(.closed)
        }
    }

    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        let address = device.addressString
        onMain {
            guard let device = self.device, address != nil, address == device.addressString,
                  self.channel == nil, self.probeChannel == nil else { return }
            guard status == kIOReturnSuccess else {
                self.fail("Service lookup failed (\(Self.describe(status))).")
                return
            }
            self.identify(device)
        }
    }

    private func isProbe(_ id: ObjectIdentifier) -> Bool {
        probeChannel.map { ObjectIdentifier($0) == id } ?? false
    }

    private func isControl(_ id: ObjectIdentifier) -> Bool {
        channel.map { ObjectIdentifier($0) == id } ?? false
    }

    // MARK: - Helpers

    private static func uuid(_ bytes: [UInt8]) -> IOBluetoothSDPUUID {
        var bytes = bytes
        return IOBluetoothSDPUUID(bytes: &bytes, length: bytes.count)
    }

    private static func channelID(of service: IOBluetoothSDPUUID, on device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        guard let record = device.getServiceRecord(for: service) else { return nil }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { return nil }
        return channelID
    }

    private static func describe(_ result: IOReturn) -> String {
        "0x" + String(UInt32(bitPattern: result), radix: 16)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }.joined()
    }
}

extension RFCOMMLink: IOBluetoothRFCOMMChannelDelegate {
    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        let id = ObjectIdentifier(rfcommChannel)
        onMain {
            if self.isProbe(id) {
                if error != kIOReturnSuccess {
                    self.log.info("Fast Pair channel refused (\(Self.describe(error), privacy: .public))")
                    self.finishIdentify()
                }
                return
            }
            guard self.isControl(id), let channel = self.channel else { return }
            guard error == kIOReturnSuccess else {
                // Usually means another app (Chrome / ear-web, or Nothing X on a phone) holds the channel.
                self.fail("The headphones refused the control channel (\(Self.describe(error))). Close ear-web or Nothing X and try again.")
                return
            }
            self.log.info("channel open, MTU \(channel.getMTU())")
            self.onEvent?(.opened(self.device?.name ?? "Headphones"))
        }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        // Copy before hopping: the buffer is only valid during this call.
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        let id = ObjectIdentifier(rfcommChannel)
        onMain {
            if self.isProbe(id) {
                self.log.info("Fast Pair rx \(Self.hex(bytes), privacy: .public)")
                self.probeBuffer += bytes
                if self.probeBuffer.count >= 7 {
                    self.finishIdentify(with: self.probeBuffer)
                }
                return
            }
            guard self.isControl(id) else { return }
            self.log.debug("rx \(Self.hex(bytes), privacy: .public)")
            self.onBytes?(bytes)
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        let id = ObjectIdentifier(rfcommChannel)
        onMain {
            if self.isProbe(id) {
                self.finishIdentify()
                return
            }
            guard self.isControl(id) else { return }
            self.log.info("channel closed")
            self.reset()
            self.onEvent?(.closed)
        }
    }
}
