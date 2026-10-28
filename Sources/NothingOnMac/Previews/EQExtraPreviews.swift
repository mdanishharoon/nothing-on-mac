#if DEBUG
import HeadphoneProtocol
import SwiftUI

extension PreviewRenderer {
    /// Named previews of the EQ extras UI (rendered alongside the main ones).
    static func eqExtraPreviews() -> [(String, AnyView)] {
        func packet(_ bands: [(Float, Float, Float)]) -> [UInt8] {
            [0xFF] + Array(ParametricEQPacket(
                bands: bands.map { ParametricBand(gain: $0.0, frequency: $0.1, q: $0.2) }, totalGain: 0).payload.dropFirst())
        }
        func section(_ controller: HeadphoneController) -> AnyView {
            guard let session = controller.session else { return AnyView(EmptyView()) }
            return card(EQExtrasSection(session: session))
        }

        // Ear (2): fixed 8-band layout with Advanced active.
        let ear2 = controller("ACC520", replies: [
            (0x4042, Array("1.0.1.120".utf8)),
            (0x401F, [0x05, 0x00]),
            (0x404C, [0x01]),
            (0x404D, packet([(3, 55, 1), (4.5, 110, 0.8), (2, 220, 1), (0, 440, 1),
                             (-1.5, 1320, 1.4), (-3, 3300, 1), (1, 6600, 2), (2.5, 13200, 0.7)])),
        ])

        // Headphone (1): fixed layout plus 5-stage bass enhance.
        let headphone1 = controller("C19ECD", replies: [
            (0x4042, Array("1.0.1.80".utf8)),
            (0x401F, [0x05, 0x00]),
            (0x404C, [0x01]),
            (0x404D, packet([(0, 55, 1), (2, 110, 1), (1, 220, 1), (0, 440, 1),
                             (0, 1320, 1), (-2, 3300, 1), (0, 6600, 1), (-1, 13200, 1)])),
            (0x404E, [0x01, 0x06]),
        ])

        // Headphone (1) Pro: flexible main bands and the precision driver.
        let proReplies: [(UInt16, [UInt8])] = [
            (0x4042, Array("1.0.1.50".utf8)),
            (0x401F, [0x05, 0x00]),
            (0x404C, [0x01]),
            (0x404D, packet([(2, 60, 0.7), (-1.5, 250, 1), (0.5, 1200, 1), (3, 4000, 2), (-2, 9000, 1)])),
            (0x406C, [0x01]),
            (0x406D, packet([(1.5, 7000, 1), (-2, 11000, 1.5)])),
        ]
        let pro = controller("CDFDEC", replies: proReplies)
        let proDriver = controller("CDFDEC", replies: proReplies)
        let proFlat = controller("CDFDEC", replies: proReplies + [(0x4068, [0x01])])

        // Headphone (a): three-stage bass enhance, Advanced off.
        let headphoneA = controller("BFD53B", replies: [
            (0x4042, Array("1.0.1.20".utf8)),
            (0x401F, [0x00, 0x00]),
            (0x404C, [0x00]),
            (0x404E, [0x01, 0x05]),
        ])

        // CMF Buds Pro 2: five-stage ultra bass.
        let budsPro2 = controller("F29566", replies: [
            (0x4042, Array("1.0.1.70".utf8)),
            (0x4050, [0x03, 0x00]),
            (0x404E, [0x01, 0x08]),
        ])

        var views: [(String, AnyView)] = [
            ("eq-advanced-ear2", section(ear2)),
            ("eq-advanced-headphone1", section(headphone1)),
            ("eq-flexible-headphone1pro", section(pro)),
            ("eq-flat-headphone1pro", section(proFlat)),
            ("eq-bass-3stage-headphone-a", section(headphoneA)),
            ("eq-bass-5stage-budspro2", section(budsPro2)),
            ("eq-card-headphone1pro", AnyView(MenuView(controller: pro))),
        ]
        if let session = proDriver.session, let advanced = session.feature(AdvancedEQFeature.self) {
            views.append(("eq-precision-driver-headphone1pro",
                          card(KeepAlive(session: session, content: AdvancedEQEditor(feature: advanced, set: .driver,
                                                                                      selection: 1)))))
        }
        return views
    }
}

/// Holds the session a bare feature view needs (features only keep an unowned reference).
private struct KeepAlive<Content: View>: View {
    let session: DeviceSession
    let content: Content

    var body: some View { content }
}
#endif
