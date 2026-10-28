#if DEBUG
import HeadphoneProtocol
import SwiftUI

extension PreviewRenderer {
    /// Named previews of the settings UI (rendered alongside the main ones).
    static func settingsPreviews() -> [(String, AnyView)] {
        // CMF Headphone Pro: dual connection on, LDAC, Audiodo on.
        let headphonePro = controller("73C9EB", replies: [
            (0x4042, Array("1.0.2.31".utf8)),
            (0x4007, [0x01, 0x06, 72]),
            (0x4027, [0x01]),
            (0x4028, devicePage),
            (0x4029, [0x02]),
            (0x405A, [0x01]),
            (0x4041, [0x02]),
        ])
        // Nothing Ear (3): in-ear, codec, Audiodo, Super Mic, mic mode, walkie-talkie, call transparency.
        let ear3 = controller("7D46E5", replies: [
            (0x4042, Array("1.0.1.50".utf8)),
            (0x4007, [0x03, 0x02, 64, 0x03, 81, 0x04, 0xAD]), // case 45%, charging (0x80)
            (0x400E, [0x01, 0x01, 0x01]),
            (0x4027, [0x00]),
            (0x4029, [0x00]),
            (0x405A, [0x00]),
            (0x405E, [0x01]),
            (0x4064, [0x01]),
            (0x4060, [0x00]),
            (0x405F, [0x01]),
            (0x4041, [0x02]),
        ])
        // CMF Clip Pro: long battery mode on, anti-leakage covering audio + calls.
        let clipPro = controller("8F28ED", replies: [
            (0x4042, Array("1.0.1.20".utf8)),
            (0x4067, [0x01]),
            (0x4027, [0x01]),
            (0x4029, [0x00]),
            (0x4071, [0x02]),
            (0x4041, [0x02]),
        ])
        let ear1 = controller("31D53D", replies: [
            (0x4042, Array("1.0.1.90".utf8)),
            (0x4007, [0x03, 0x02, 90, 0x03, 88, 0x04, 60]),
            (0x400E, [0x01, 0x01, 0x00]),
            (0x4017, [0x05, 0x01, 0xFF, 0x00, 0x00, 0x02, 0xFF, 0xE0, 0x00, 0x03, 0x00, 0xFF, 0x00,
                      0x04, 0x00, 0x60, 0xFF, 0x05, 0xFF, 0xFF, 0xFF]),
        ])
        let ear2 = controller("ACC520", replies: [
            (0x4042, Array("1.0.1.100".utf8)),
            (0x401E, [0x01, 0x01, 0x00]),
            (0x4020, [0x01]),
        ])

        var views: [(String, AnyView)] = []
        if let session = headphonePro.session {
            views.append(("settings-quick-headphone-pro", quick(session)))
            views.append(("settings-devices", card(page("Devices", DevicesPage(session: session)))))
            if let codec = session.feature(AudioCodecFeature.self) {
                views.append(("settings-codec-confirm", card(AudioCodecRow(feature: codec, pending: .aac))))
            }
        }
        if let session = ear3.session {
            views.append(("settings-quick-ear3", quick(session)))
            session.feature(EarTipTestFeature.self)?.start()
            views.append(("settings-eartip-testing", card(page("Ear tip", QuickSettingsExtras(session: session)))))
        }
        // A fresh session for the result, so the testing state above stays as rendered.
        let ear3Result = controller("7D46E5", replies: [(0x4042, Array("1.0.1.50".utf8))])
        if let session = ear3Result.session, let test = session.feature(EarTipTestFeature.self) {
            test.start()
            session.receive(Frame(command: 0xE00D, operationID: 1, payload: [0x00, 0x01], checksumValid: true))
            views.append(("settings-eartip-result", card(page("Quick settings", QuickSettingsExtras(session: session)))))
            session.feature(FindDeviceFeature.self)?.toggle(.left)
            views.append(("settings-find-earbuds", AnyView(MenuView(controller: ear3Result))))
        }
        if let session = clipPro.session {
            views.append(("settings-quick-clip-pro", quick(session)))
            if let mode = session.feature(LongPowerModeFeature.self) {
                views.append(("settings-long-battery-confirm", card(LongPowerModeRow(feature: mode, pending: false))))
            }
        }
        if let session = ear1.session, let led = session.feature(CaseLEDFeature.self) {
            views.append(("settings-case-led", card(CaseLEDRow(feature: led, expanded: true))))
            views.append(("settings-find-ear1", card(FindDeviceButtons(session: session).frame(maxWidth: .infinity))))
        }
        if let session = ear2.session {
            views.append(("settings-noise-ear2", card(page("Noise control", NoiseControlExtras(session: session)))))
            if let dual = session.feature(DualConnectionFeature.self) {
                views.append(("settings-dual-reboot-confirm", card(DualConnectionRow(feature: dual, pending: true))))
            }
        }
        // Headphones: one ring button, ringing.
        if let session = headphonePro.session {
            session.feature(FindDeviceFeature.self)?.toggle(.single)
            views.append(("settings-find-headphones", AnyView(MenuView(controller: headphonePro))))
        }
        return views
    }

    /// Two remembered devices plus this Mac, the second phone disconnected.
    private static let devicePage: [UInt8] = {
        func record(_ flags: UInt8, _ mac: [UInt8], _ name: String) -> [UInt8] {
            let bytes = Array(name.utf8)
            return [flags] + mac + [UInt8(bytes.count)] + bytes
        }
        return [0x00, 0x00, 0x03]
            + record(0x11, [0xA4, 0xC1, 0x38, 0x5B, 0x22, 0x9F], "MacBook Pro")
            + record(0x01, [0x3C, 0x22, 0xFB, 0x10, 0x4E, 0x07], "Pixel 9")
            + record(0x00, [0x58, 0x6D, 0x8F, 0x91, 0x02, 0xC4], "iPad Air")
    }()

    private static func quick(_ session: DeviceSession) -> AnyView {
        card(page("Quick settings", QuickSettingsExtras(session: session)))
    }

    private static func page<V: View>(_ title: String, _ content: V) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.doto(18))
                .foregroundStyle(Theme.primary)
            content
        }
    }
}
#endif
