#if DEBUG
import SwiftUI

/// Background of the installer window, rendered by `NothingOnMac --render-dmg-background <dir>`
/// and laid out by scripts/dmg-settings.py. Geometry here must match the icon positions there.
struct DMGBackground: View {
    static let size = CGSize(width: 640, height: 420)
    /// Icon centres in window coordinates (also in dmg-settings.py).
    static let appCenter = CGPoint(x: 170, y: 196)
    static let applicationsCenter = CGPoint(x: 470, y: 196)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            DotGrid(spacing: 14, radius: 1.1)

            Text("NOTHING ON MAC")
                .font(.doto(30))
                .foregroundStyle(Color.white)
                .frame(width: Self.size.width)
                .position(x: Self.size.width / 2, y: 54)

            tile(at: Self.appCenter)
            tile(at: Self.applicationsCenter)

            DotArrow()
                .frame(width: 112, height: 28)
                .position(x: (Self.appCenter.x + Self.applicationsCenter.x) / 2, y: Self.appCenter.y)

            VStack(spacing: 8) {
                Text("Drag Nothing on Mac into Applications")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("First launch: System Settings › Privacy & Security › Open Anyway")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.56))
            }
            .frame(width: Self.size.width)
            .position(x: Self.size.width / 2, y: 356)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// A card behind each icon. Finder draws icon names black in Light Mode and white in Dark Mode,
    /// so the name sits on a mid-grey strip along the card's bottom edge, readable either way.
    private func tile(at center: CGPoint) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(spacing: 0) {
            Theme.surface
            Color(white: 0.43).frame(height: 34)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .frame(width: 168, height: 186)
        .position(x: center.x, y: center.y + 9)
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
