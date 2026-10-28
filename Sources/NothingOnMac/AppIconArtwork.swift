#if DEBUG
import SwiftUI

/// 1024×1024 app icon source, rendered by `NothingOnMac --render-icon <file.png>` and turned into
/// AppIcon.icns by scripts/make-icon.sh. Black rounded square on Apple's icon grid, the menu bar's
/// dot-matrix headphones in white, and one red dot.
struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.02)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            DotMatrixHeadphones()
                .foregroundStyle(Color.white)
                .frame(width: 520, height: 470)
                .offset(y: 20)
            Circle()
                .fill(Theme.accent)
                .frame(width: 62, height: 62)
                .offset(x: 270, y: -270)
        }
        .frame(width: 1024, height: 1024)
    }
}
#endif
