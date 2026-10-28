import AppKit
import SwiftUI

/// Headphones drawn as a dot-matrix bitmap, in the spirit of Nothing's Glyph and Doto type.
struct DotMatrixHeadphones: View {
    private static let rows = [
        "...#####...",
        ".##.....##.",
        ".#.......#.",
        "#.........#",
        "#.........#",
        "###.....###",
        "###.....###",
        "###.....###",
        "###.....###",
        ".##.....##.",
    ]

    var body: some View {
        Canvas { context, size in
            let columns = Self.rows[0].count
            let pitch = min(size.width / CGFloat(columns), size.height / CGFloat(Self.rows.count))
            let diameter = pitch * 0.82
            let origin = CGPoint(
                x: (size.width - pitch * CGFloat(columns)) / 2,
                y: (size.height - pitch * CGFloat(Self.rows.count)) / 2
            )
            for (row, line) in Self.rows.enumerated() {
                for (column, cell) in line.enumerated() where cell == "#" {
                    let rect = CGRect(
                        x: origin.x + CGFloat(column) * pitch + (pitch - diameter) / 2,
                        y: origin.y + CGFloat(row) * pitch + (pitch - diameter) / 2,
                        width: diameter, height: diameter
                    )
                    context.fill(Path(ellipseIn: rect), with: .foreground)
                }
            }
        }
    }
}

/// The status-item content: dot headphones plus the battery figure in Doto.
///
/// MenuBarExtra labels ignore custom fonts, so this is rendered to a template image,
/// which macOS tints for light and dark menu bars like any system icon.
@MainActor
enum MenuBarIcon {
    static func image(battery: Int?, dimmed: Bool) -> NSImage {
        let content = HStack(spacing: 3) {
            DotMatrixHeadphones()
                .frame(width: 15, height: 14)
            if let battery {
                Text("\(battery)%")
                    .font(.dotoHeavy(12))
            }
        }
        .foregroundStyle(Color.black)
        .opacity(dimmed ? 0.5 : 1)
        .frame(height: 18)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }
}
