#if DEBUG
import SwiftUI

/// Background of the installer window, rendered by `NothingOnMac --render-dmg-background <dir>`
/// and laid out by scripts/make-dmg.sh. Geometry here must match the window size and icon
/// positions there.
struct DMGBackground: View {
    static let size = CGSize(width: 640, height: 340)
    /// Icon centres in window coordinates (also in make-dmg.sh).
    static let appCenter = CGPoint(x: 170, y: 196)
    static let applicationsCenter = CGPoint(x: 470, y: 196)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            DotGrid(spacing: 14, radius: 1.1)

            Text("NOTHING")
                .font(.doto(30))
                .foregroundStyle(Color.white)
                .frame(width: Self.size.width)
                .position(x: Self.size.width / 2, y: 54)

            DotArrow()
                .frame(width: 112, height: 28)
                .position(x: (Self.appCenter.x + Self.applicationsCenter.x) / 2, y: Self.appCenter.y)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// A right-pointing arrow made of dots, ending in the accent red.
private struct DotArrow: View {
    var body: some View {
        Canvas { context, size in
            let dot: CGFloat = 5
            let step: CGFloat = 11
            let midY = size.height / 2
            var x: CGFloat = dot / 2
            while x < size.width - step {
                context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: midY - dot / 2, width: dot, height: dot)),
                             with: .color(.white.opacity(0.85)))
                x += step
            }
            let tip = CGPoint(x: size.width - dot / 2, y: midY)
            for offset in [1, 2] {
                let o = CGFloat(offset) * 8
                for y in [midY - o, midY + o] {
                    context.fill(Path(ellipseIn: CGRect(x: tip.x - o - dot / 2, y: y - dot / 2, width: dot, height: dot)),
                                 with: .color(.white.opacity(0.85)))
                }
            }
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7)), with: .color(Theme.accent))
        }
    }
}
#endif
