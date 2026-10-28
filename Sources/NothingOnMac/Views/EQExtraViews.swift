import HeadphoneProtocol
import SwiftUI

/// Shown at the bottom of the Equaliser card: flat EQ notice, advanced EQ editor, bass.
struct EQExtrasSection: View {
    let session: DeviceSession

    var body: some View {
        let flatOn = session.feature(FlatEQFeature.self)?.isOn == true
        let advancedActive = session.feature(EQFeature.self)?.advancedActive == true
        Group {
            if flatOn {
                FlatEQNotice()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if advancedActive, let advanced = session.feature(AdvancedEQFeature.self), advanced.isAvailable {
                AdvancedEQEditor(feature: advanced)
                    .disabled(flatOn)
                    .opacity(flatOn ? 0.35 : 1)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let bass = session.feature(BassFeature.self), bass.isAvailable {
                BassSection(bass: bass)
            }
        }
        .animation(Theme.spring, value: flatOn)
    }
}

// MARK: - Flat EQ

private struct FlatEQNotice: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Flat EQ is on")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primary)
                Text("Switch it off on the left earcup to change the EQ.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Bass

private struct BassSection: View {
    let bass: BassFeature

    var body: some View {
        let on = bass.enabled == true
        VStack(spacing: 12) {
            SettingDivider()
            SettingToggleRow(title: bass.title, isOn: on) { bass.setEnabled(!on) }
            if on {
                DotLevelPicker(options: bass.scheme.levels.map { ($0, $0 == 0 ? "Off" : "Level \($0)") },
                               selection: bass.level) { bass.select(level: $0) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Theme.spring, value: on)
    }
}

// MARK: - Advanced EQ

/// Band gains as vertical dot columns with frequency labels underneath; the selected band's
/// frequency and Q are tuned below. B192 adds a Main / Precision driver switch and add/remove.
struct AdvancedEQEditor: View {
    let feature: AdvancedEQFeature
    @State private var set: EQBandSet
    @State private var selection = 0

    init(feature: AdvancedEQFeature, set: EQBandSet = .main, selection: Int = 0) {
        self.feature = feature
        _set = State(initialValue: set)
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let bands = feature.bands(set)
        let selected = min(selection, max(bands.count - 1, 0))
        VStack(spacing: 10) {
            if feature.isFlexible {
                PillPicker(options: [(EQBandSet.main, "Main"), (EQBandSet.driver, "Precision driver")],
                           selection: set) { newSet in
                    set = newSet
                    selection = 0
                }
            }
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                        BandColumn(band: band, selected: index == selected,
                                   onSelect: { selection = index },
                                   onGain: { feature.setGain($0, at: index, in: set) },
                                   onCommit: feature.commit)
                    }
                }
                if bands.indices.contains(selected) {
                    BandDetail(feature: feature, set: set, index: selected, band: bands[selected],
                               onSelect: { selection = $0 })
                }
            }
            .padding(12)
            .background(Color.black, in: .rect(cornerRadius: 14))
        }
        .animation(Theme.spring, value: bands.count)
        .animation(Theme.spring, value: set)
        .onAppear { feature.refresh() }
    }
}

private struct BandColumn: View {
    let band: ParametricBand
    let selected: Bool
    let onSelect: () -> Void
    let onGain: (Float) -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(EQFormat.gain(band.gain))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(selected ? Theme.primary : Theme.secondary)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(band.gain)))
            GainDots(gain: band.gain, selected: selected, onGain: { gain in
                if !selected { onSelect() }
                onGain(gain)
            }, onCommit: onCommit)
            .frame(height: 112)
            Button(action: onSelect) {
                Text(EQFormat.shortFrequency(band.frequency))
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(selected ? Color.black : Theme.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(selected ? Theme.primary : Color.clear, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: band.gain)
        .animation(Theme.spring, value: selected)
    }
}

/// −6…+6 dB as 13 dots; dots between 0 and the gain light up and a marker sits at the gain,
/// red on the selected band. Dragging sets the gain in 0.5 dB steps.
private struct GainDots: View {
    let gain: Float
    let selected: Bool
    let onGain: (Float) -> Void
    let onCommit: () -> Void

    private let inset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let x = proxy.size.width / 2
            ZStack {
                ForEach(-6...6, id: \.self) { level in
                    Circle()
                        .fill(color(for: level))
                        .frame(width: level == 0 ? 4 : 3, height: level == 0 ? 4 : 3)
                        .position(x: x, y: y(Float(level), height))
                }
                Circle()
                    .fill(gain != 0 && selected ? Theme.accent : Theme.primary)
                    .frame(width: selected ? 9 : 7, height: selected ? 9 : 7)
                    .position(x: x, y: y(gain, height))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = Float((drag.location.y - inset) / (height - inset * 2))
                        let raw = 6 - fraction * 12
                        let stepped = (raw / AdvancedEQLayout.gainStep).rounded() * AdvancedEQLayout.gainStep
                        let value = min(max(stepped, -6), 6)
                        if value != gain { onGain(value) }
                    }
                    .onEnded { _ in onCommit() }
            )
        }
    }

    private func y(_ value: Float, _ height: CGFloat) -> CGFloat {
        inset + CGFloat((6 - value) / 12) * (height - inset * 2)
    }

    private func color(for level: Int) -> Color {
        let value = Float(level)
        let lit = gain > 0 ? (0 <= value && value < gain) : gain < 0 && (gain < value && value <= 0)
        if lit { return selected ? Theme.primary : Theme.primary.opacity(0.7) }
        return level == 0 ? Theme.secondary : Theme.tertiary
    }
}

/// Frequency and Q of the selected band, plus add/remove on the flexible layout.
private struct BandDetail: View {
    let feature: AdvancedEQFeature
    let set: EQBandSet
    let index: Int
    let band: ParametricBand
    let onSelect: (Int) -> Void

    var body: some View {
        let range = feature.frequencyRange(set, band: index)
        let limit = feature.bandLimit(set)
        let count = feature.bands(set).count
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(set == .driver ? "Driver band \(index + 1)" : "Band \(index + 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .contentTransition(.numericText(value: Double(index)))
                Spacer(minLength: 8)
                if feature.isFlexible {
                    IconButton(symbol: "minus", enabled: count > limit.lowerBound) {
                        onSelect(feature.removeBand(at: index, from: set))
                    }
                    IconButton(symbol: "plus", enabled: count < limit.upperBound) {
                        if let added = feature.addBand(to: set) { onSelect(added) }
                    }
                }
            }
            ParameterSlider(
                title: "Freq",
                position: frequencyPosition(range),
                value: EQFormat.frequency(band.frequency),
                onChange: { position in
                    let frequency = feature.isFlexible
                        ? AdvancedEQLayout.frequency(atLogPosition: position, in: range)
                        : range.lowerBound + Float(position) * (range.upperBound - range.lowerBound)
                    feature.setFrequency(frequency, at: index, in: set)
                },
                onCommit: feature.commit)
            ParameterSlider(
                title: "Q",
                position: Double((band.q - AdvancedEQLayout.qRange.lowerBound)
                    / (AdvancedEQLayout.qRange.upperBound - AdvancedEQLayout.qRange.lowerBound)),
                value: String(format: "%.1f", band.q),
                onChange: { position in
                    let q = AdvancedEQLayout.qRange
                    feature.setQ(q.lowerBound + Float(position) * (q.upperBound - q.lowerBound), at: index, in: set)
                },
                onCommit: feature.commit)
        }
    }

    private func frequencyPosition(_ range: ClosedRange<Float>) -> Double {
        if feature.isFlexible { return AdvancedEQLayout.logPosition(of: band.frequency, in: range) }
        return Double((band.frequency - range.lowerBound) / (range.upperBound - range.lowerBound))
    }
}

/// A thin horizontal slider: grey track, white fill and knob. Reports 0…1 while dragging.
private struct ParameterSlider: View {
    let title: String
    let position: Double
    let value: String
    let onChange: (Double) -> Void
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .frame(width: 30, alignment: .leading)
            GeometryReader { proxy in
                let width = proxy.size.width
                let clamped = min(max(position, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track).frame(height: 4)
                    Capsule().fill(Theme.primary).frame(width: max(4, width * clamped), height: 4)
                    Circle().fill(Theme.primary).frame(width: 12, height: 12)
                        .offset(x: (width - 12) * clamped)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { onChange(min(max($0.location.x / max(width, 1), 0), 1)) }
                        .onEnded { _ in onCommit() }
                )
            }
            .frame(height: 20)
            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(enabled ? Theme.primary : Theme.tertiary)
        .disabled(!enabled)
    }
}

private enum EQFormat {
    static func gain(_ value: Float) -> String {
        let text = value.rounded() == value ? String(format: "%.0f", abs(value)) : String(format: "%.1f", abs(value))
        return value > 0 ? "+" + text : value < 0 ? "−" + text : "0"
    }

    /// Column label: "55", "440", "1.3k", "13k".
    static func shortFrequency(_ hz: Float) -> String {
        guard hz >= 1000 else { return String(format: "%.0f", hz) }
        let khz = hz / 1000
        return khz >= 10 || (khz * 10).rounded() / 10 == khz.rounded() ? String(format: "%.0fk", khz) : String(format: "%.1fk", khz)
    }

    static func frequency(_ hz: Float) -> String {
        guard hz >= 1000 else { return String(format: "%.0f Hz", hz) }
        let khz = hz / 1000
        return khz >= 10 ? String(format: "%.1f kHz", khz) : String(format: "%.2f kHz", khz)
    }
}
