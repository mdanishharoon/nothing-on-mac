#if DEBUG
import AppKit
import HeadphoneProtocol
import SwiftUI

/// `NothingOnMac --render-preview <dir>` writes PNGs of the UI in canned states and exits, so it can
/// be checked without hardware. Set NOM_RESOURCES to the repo's Resources folder.
///
/// Connected states are built by feeding fake device replies through the real parsers.
/// Feature groups add their own states in Previews/*.swift via `…Previews()`.
@MainActor
enum PreviewRenderer {
    static let catalog = AppResources.data("catalog").flatMap { try? DeviceCatalog(json: $0) }
    static let configs = AppResources.data("ear_config").flatMap { try? ModelConfigTable(json: $0) }

    /// A controller for `sku` with the given replies already received (firmware first, so the
    /// config is chosen before the rest arrive).
    static func controller(_ sku: String, _ status: HeadphoneController.Status = .connected,
                           replies: [(UInt16, [UInt8])] = []) -> HeadphoneController {
        let controller = HeadphoneController(preview: catalog?.model(sku: sku), status: status,
                                             catalog: catalog, configs: configs)
        for (command, payload) in replies {
            controller.session?.receive(Frame(command: command, operationID: 1, payload: payload, checksumValid: true))
        }
        return controller
    }

    /// A page or section on its own, at card width, for checking one feature group.
    static func card<V: View>(_ content: V) -> AnyView {
        AnyView(content.cardStyle().frame(width: 312).padding(14).background(Color.black)
            .environment(\.colorScheme, .dark))
    }

    static func renderIfRequested() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-icon"), flag + 1 < arguments.count {
            write(AppIconArtwork(), to: URL(fileURLWithPath: arguments[flag + 1]), scale: 1)
            exit(0)
        }
        if let flag = arguments.firstIndex(of: "--render-dmg-background"), flag + 1 < arguments.count {
            AppResources.registerFonts()
            let directory = URL(fileURLWithPath: arguments[flag + 1])
            write(DMGBackground(), to: directory.appending(path: "background.png"), scale: 1)
            write(DMGBackground(), to: directory.appending(path: "background@2x.png"), scale: 2)
            exit(0)
        }
        guard let flag = arguments.firstIndex(of: "--render-preview"), flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        AppResources.registerFonts()

        let headphones = controller("73C9EB", replies: [
            (0x4042, Array("1.0.2.31".utf8)),
            (0x4007, [0x01, 0x06, 72]),
            (0x401E, [0x01, 0x01, 0x00]),
            (0x4050, [0x03, 0x00]),
            (0x404F, [0x02, 0x00]),
            (0x4041, [0x01]),
        ])
        let budsBands = CustomEQBands(low: (140, 0.8), peak: (980, 0.7), high: (6900, 1.0))
        let earbuds = controller("F29566", replies: [
            (0x4042, Array("1.0.1.70".utf8)),
            (0x4007, [0x03, 0x02, 64, 0x03, 81, 0x04, 0xAD]), // case 45%, charging (0x80)
            (0x401E, [0x01, 0x07, 0x00]),
            (0x4050, [0x06, 0x00]),
            (0x4044, CustomEQ(bass: 3, mid: 0, treble: -2).payload(bands: budsBands)),
            (0x4041, [0x02]),
        ])
        var views: [(String, AnyView)] = [
            ("connected", AnyView(MenuView(controller: headphones))),
            ("earbuds", AnyView(MenuView(controller: earbuds))),
            ("disconnected", AnyView(MenuView(controller: controller(
                "563DA5", .unavailable("Connect your CMF Headphone Pro to this Mac first."))))),
        ]
        views += gesturePreviews() + eqExtraPreviews() + settingsPreviews()
        for (name, view) in views {
            write(view, to: directory.appending(path: "\(name).png"))
        }

        // The status item as it would sit on a light and a dark menu bar.
        let bar = VStack(alignment: .leading, spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 16) {
                    Image(nsImage: MenuBarIcon.image(battery: 72, dimmed: false)).renderingMode(.template)
                    Image(nsImage: MenuBarIcon.image(battery: nil, dimmed: true)).renderingMode(.template)
                }
                .foregroundStyle(dark ? Color.white : Color.black)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(dark ? Color(white: 0.12) : Color(white: 0.93))
            }
        }
        write(bar, to: directory.appending(path: "menubar.png"), scale: 4)
        exit(0)
    }

    private static func write<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
#endif
