import AppKit
import CoreBluetooth
import IOBluetooth
import os
import ServiceManagement

/// Launch at login via the system's login items.
@MainActor
enum LoginItem {
    private static let log = Logger(subsystem: "io.github.mdanishharoon.NothingOnMac", category: "app")
    private static let setUpKey = "loginItemSetUp"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A menu bar utility should come back after a restart, so turn this on once at first launch.
    /// After that the user's choice stands.
    static func enableOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: setUpKey) else { return }
        UserDefaults.standard.set(true, forKey: setUpKey)
        setEnabled(true)
    }
}

/// Problems outside the app that stop it reaching any device.
enum BluetoothIssue: Equatable {
    case permissionDenied
    case poweredOff

    var message: String {
        switch self {
        case .permissionDenied: "Nothing on Mac needs Bluetooth access to talk to your device."
        case .poweredOff: "Bluetooth is off."
        }
    }

    var actionTitle: String {
        switch self {
        case .permissionDenied: "Open Privacy settings"
        case .poweredOff: "Open Bluetooth settings"
        }
    }

    var settingsURL: URL {
        switch self {
        case .permissionDenied: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
        case .poweredOff: URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!
        }
    }

    static func current() -> BluetoothIssue? {
        switch CBManager.authorization {
        case .denied, .restricted: return .permissionDenied
        default: break
        }
        if let host = IOBluetoothHostController.default(), host.powerState != kBluetoothHCIPowerStateON {
            return .poweredOff
        }
        return nil
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static let repository = URL(string: "https://github.com/mdanishharoon/nothing-on-mac")!
}
