import SwiftUI

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.doto(18))
                .foregroundStyle(Theme.primary)
            content
        }
        .cardStyle()
    }
}

extension View {
    func cardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
    }
}

/// Chevrons either side of page dots; the current page's dot stretches into a pill.
struct PageControl: View {
    let count: Int
    let page: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            chevron("chevron.left", target: page - 1)
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { index in
                    Button { onSelect(index) } label: {
                        Capsule()
                            .fill(index == page ? Theme.primary : Theme.tertiary)
                            .frame(width: index == page ? 16 : 6, height: 6)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            chevron("chevron.right", target: page + 1)
        }
        .animation(Theme.spring, value: page)
    }

    private func chevron(_ symbol: String, target: Int) -> some View {
        let enabled = (0..<count).contains(target)
        return Button { onSelect(target) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Color.black, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(enabled ? Theme.primary : Theme.tertiary)
        .disabled(!enabled)
    }
}

// MARK: - Settings rows (shared by every quick-settings style page)

struct SettingLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingDivider: View {
    var body: some View {
        Rectangle().fill(Theme.track).frame(height: 1)
    }
}

struct SettingToggleRow: View {
    let title: String
    var subtitle: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            SettingLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 12)
            NothingToggle(isOn: isOn, action: action)
        }
    }
}

/// A row that opens something (a test, a list): title on the left, value and chevron on the right.
struct SettingNavigationRow: View {
    let title: String
    var value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                SettingLabel(title: title)
                Spacer(minLength: 12)
                if let value {
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Scales slightly while pressed, so every control acknowledges the click.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Segmented control: a black capsule track with a white pill sliding to the selection.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    let selection: Value?
    let onSelect: (Value) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    onSelect(option.value)
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color.black : Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background {
                            if selected {
                                Capsule().fill(Theme.primary).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(3)
        .background(Color.black, in: Capsule())
        .animation(Theme.spring, value: selection)
    }
}

/// Labelled dots on a black track; the selected dot grows and turns white (ear-web's strength selector).
struct DotLevelPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    let selection: Value?
    let onSelect: (Value) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(options, id: \.value) { option in
                    let selected = option.value == selection
                    Button {
                        onSelect(option.value)
                    } label: {
                        Circle()
                            .fill(selected ? Theme.primary : Theme.secondary)
                            .frame(width: selected ? 12 : 5, height: selected ? 12 : 5)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 4)
            .background(Color.black, in: Capsule())
            HStack(spacing: 0) {
                ForEach(options, id: \.value) { option in
                    Text(option.label)
                        .font(.system(size: 11, weight: option.value == selection ? .semibold : .regular))
                        .foregroundStyle(option.value == selection ? Theme.primary : Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
        .animation(Theme.spring, value: selection)
    }
}

/// Discrete dot slider for one EQ band. Dots between 0 and the value light up; the value dot is red.
struct DotSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { proxy in
                let count = range.count
                let step = proxy.size.width / CGFloat(count)
                HStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { level in
                        let current = level == value
                        Circle()
                            .fill(color(for: level))
                            .frame(width: current ? 10 : 5, height: current ? 10 : 5)
                            .frame(width: step, height: proxy.size.height)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let index = Int((drag.location.x / step).rounded(.down))
                            let level = range.lowerBound + min(max(index, 0), count - 1)
                            if level != value { value = level }
                        }
                        .onEnded { _ in onCommit() }
                )
            }
            .frame(height: 20)
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.primary)
                .frame(width: 22, alignment: .trailing)
                .contentTransition(.numericText(value: Double(value)))
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: value)
    }

    private func color(for level: Int) -> Color {
        if level == value { return value == 0 ? Theme.primary : Theme.accent }
        let lit = value > 0 ? (0..<value).contains(level) : value < 0 && (value + 1...0).contains(level)
        if lit { return Theme.primary }
        return level == 0 ? Theme.secondary : Theme.tertiary
    }
}

struct NothingToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? Theme.accent : Color.black)
                .frame(width: 40, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Theme.primary : Theme.secondary)
                        .frame(width: 18, height: 18)
                        .padding(3)
                }
        }
        .buttonStyle(PressableStyle())
        .animation(Theme.spring, value: isOn)
    }
}

struct PillButton: View {
    let title: String
    var selected = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(selected ? Color.black : Theme.primary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(selected ? Theme.primary : Color.black, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

/// Faint dot grid that fades out from the centre, drawn behind the product image.
struct DotGrid: View {
    var spacing: CGFloat = 11
    var radius: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = max(size.width, size.height) / 2
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    let distance = hypot(x - center.x, y - center.y) / reach
                    let opacity = max(0, 0.18 * (1 - distance))
                    if opacity > 0.01 {
                        let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(opacity)))
                    }
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

/// Battery figure in Doto with a thin bar underneath, as on ear-web's header.
struct BatteryGauge: View {
    let level: Int
    let isCharging: Bool

    private var low: Bool { level <= 15 && !isCharging }

    private let barWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text("\(level)%")
                    .font(.doto(17))
                    .contentTransition(.numericText(value: Double(level)))
            }
            .foregroundStyle(low ? Theme.accent : Theme.primary)
            Capsule()
                .fill(Theme.track)
                .frame(width: barWidth, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(low ? Theme.accent : Theme.primary)
                        .frame(width: barWidth * CGFloat(min(max(level, 0), 100)) / 100)
                }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: level)
        .animation(Theme.spring, value: isCharging)
    }
}
