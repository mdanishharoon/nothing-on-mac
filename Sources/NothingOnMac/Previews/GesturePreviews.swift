#if DEBUG
import SwiftUI

extension PreviewRenderer {
    /// Named previews of the gestures UI (rendered alongside the main ones).
    static func gesturePreviews() -> [(String, AnyView)] {
        func records(_ list: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
            [UInt8(list.count)] + list.flatMap { [$0.0, $0.1, $0.2, $0.3] }
        }
        // CMF Headphone Pro: button, energy slider and roller (device 6).
        let headphonePro = controller("73C9EB", replies: [
            (0x4042, Array("1.0.2.31".utf8)),
            (0x4018, records([(6, 10, 1, 11), (6, 10, 7, 22), (6, 5, 1, 35), (6, 1, 7, 10)])),
        ])
        // CMF Buds Pro 2: both buds plus the smart knob on the case (device 4).
        let budsPro2 = controller("F29566", replies: [
            (0x4042, Array("1.0.1.70".utf8)),
            (0x4018, records([
                (2, 1, 2, 2), (2, 1, 3, 9), (2, 1, 7, 20), (2, 1, 9, 18),
                (3, 1, 2, 9), (3, 1, 3, 8), (3, 1, 7, 11), (3, 1, 9, 42),
                (4, 1, 1, 2), (4, 1, 2, 9), (4, 9, 2, 25), (4, 1, 3, 8), (4, 9, 3, 26), (4, 1, 7, 10), (4, 1, 10, 23),
            ])),
        ])
        // Nothing Ear (3a): pinch family plus "Pinch both buds".
        let ear3a = controller("7B2328", replies: [
            (0x4042, Array("1.0.0.0".utf8)),
            (0x4018, records([(2, 1, 2, 9), (2, 1, 3, 31), (2, 1, 7, 21), (2, 1, 9, 19), (2, 1, 11, 37)])),
        ])
        func page(_ controller: HeadphoneController, group: String? = nil, expanded: String? = nil) -> AnyView {
            guard let session = controller.session else { return AnyView(EmptyView()) }
            return card(GesturesPage(session: session, group: group, expanded: expanded))
        }
        return [
            ("gestures-headphone-pro", page(headphonePro)),
            ("gestures-headphone-pro-hold", page(headphonePro, expanded: "button.hold")),
            ("gestures-headphone-pro-slider", page(headphonePro, group: "slider", expanded: "slider")),
            ("gestures-buds-pro-2-left", page(budsPro2)),
            ("gestures-buds-pro-2-right-unknown", page(budsPro2, group: "right", expanded: "doubleHold")),
            ("gestures-buds-pro-2-dial", page(budsPro2, group: "dial")),
            ("gestures-buds-pro-2-dial-hold", page(budsPro2, group: "dial", expanded: "hold")),
            ("gestures-ear-3a", page(ear3a, expanded: "hold")),
        ]
    }
}
#endif
