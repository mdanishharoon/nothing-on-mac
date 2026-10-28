import SwiftUI

// Noise-control glyphs redrawn after ear-web's anc_on / anc_transparent / anc_off icons,
// on a 24-point grid so they scale cleanly.

/// Two concentric open arcs around a centre dot.
struct NoiseCancellingIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            let center = CGPoint(x: 12 * s, y: 12.5 * s)
            let stroke = StrokeStyle(lineWidth: 1.8 * s, lineCap: .round)
            for radius in [8.6, 4.8] {
                var arc = Path()
                arc.addArc(center: center, radius: radius * s, startAngle: .degrees(135), endAngle: .degrees(45), clockwise: false)
                context.stroke(arc, with: .foreground, style: stroke)
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.6 * s, y: center.y - 1.6 * s, width: 3.2 * s, height: 3.2 * s)), with: .foreground)
        }
    }
}

/// A ring of small dots around a centre dot.
struct TransparencyIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            let center = CGPoint(x: 12 * s, y: 12.5 * s)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2 * s, y: center.y - 2 * s, width: 4 * s, height: 4 * s)), with: .foreground)
            for index in 0..<10 {
                let angle = Double(index) / 10 * 2 * .pi
                let point = CGPoint(x: center.x + cos(angle) * 8.6 * s, y: center.y + sin(angle) * 8.6 * s)
                context.fill(Path(ellipseIn: CGRect(x: point.x - s, y: point.y - s, width: 2 * s, height: 2 * s)), with: .foreground)
            }
        }
    }
}

/// The cancelling arcs, struck through.
struct NoiseOffIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            let center = CGPoint(x: 12 * s, y: 12.5 * s)
            let stroke = StrokeStyle(lineWidth: 1.8 * s, lineCap: .round)
            var arc = Path()
            arc.addArc(center: center, radius: 8.6 * s, startAngle: .degrees(135), endAngle: .degrees(45), clockwise: false)
            context.stroke(arc, with: .foreground, style: stroke)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.6 * s, y: center.y - 1.6 * s, width: 3.2 * s, height: 3.2 * s)), with: .foreground)
            var slash = Path()
            slash.move(to: CGPoint(x: 4 * s, y: 3.5 * s))
            slash.addLine(to: CGPoint(x: 20 * s, y: 20.5 * s))
            context.stroke(slash, with: .foreground, style: stroke)
        }
    }
}
