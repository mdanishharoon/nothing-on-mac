import HeadphoneProtocol
import SwiftUI

/// Extra rows on the "Quick settings" page, after spatial audio and low latency.
/// A `Group`, so each row joins the page's own stack and spacing.
struct QuickSettingsExtras: View {
    let session: DeviceSession

    var body: some View {
        Group {
            if let feature = available(InEarDetectionFeature.self) {
                SettingDivider()
                SettingToggleRow(title: feature.title, subtitle: "Pauses audio when you take them off",
                                 isOn: feature.enabled ?? false) { feature.set(!(feature.enabled ?? false)) }
            }
            if let feature = available(LongPowerModeFeature.self) {
                SettingDivider()
                LongPowerModeRow(feature: feature)
            }
            if let feature = available(DualConnectionFeature.self) {
                SettingDivider()
                DualConnectionRow(feature: feature)
            }
            if let feature = available(AudioCodecFeature.self) {
                SettingDivider()
                AudioCodecRow(feature: feature)
            }
            if let feature = available(PersonalSoundFeature.self) {
                SettingDivider()
                SettingToggleRow(title: "Personal sound profile", subtitle: "Uses your hearing profile from Nothing X",
                                 isOn: feature.enabled ?? false) { feature.set(!(feature.enabled ?? false)) }
            }
            if let feature = available(SuperMicFeature.self) {
                SettingDivider()
                SuperMicRows(feature: feature, walkieTalkie: available(WalkieTalkieFeature.self))
            } else if let feature = available(WalkieTalkieFeature.self) {
                SettingDivider()
                SettingToggleRow(title: "Walkie-talkie mode", isOn: feature.enabled ?? false) {
                    feature.set(!(feature.enabled ?? false))
                }
            }
            if let feature = available(CallTransparencyFeature.self) {
                SettingDivider()
                SettingToggleRow(title: "Call transparency", subtitle: "Hear your surroundings during calls",
                                 isOn: feature.enabled ?? false) { feature.set(!(feature.enabled ?? false)) }
            }
            if let feature = available(AntiLeakageFeature.self) {
                SettingDivider()
                VStack(alignment: .leading, spacing: 8) {
                    SettingLabel(title: "Anti-leakage", subtitle: "Keeps your audio from being overheard")
                    PillPicker(options: AntiLeakageMode.allCases.map { ($0, $0.name) },
                               selection: feature.mode, onSelect: { feature.set($0) })
                }
            }
            if let feature = available(EarTipTestFeature.self) {
                SettingDivider()
                EarTipTestRow(feature: feature)
            }
            if let feature = available(CaseLEDFeature.self) {
                SettingDivider()
                CaseLEDRow(feature: feature)
            }
        }
    }

    private func available<T: DeviceFeature>(_ type: T.Type) -> T? {
        session.feature(type).flatMap { $0.isAvailable ? $0 : nil }
    }
}

/// Extra rows on the "Noise control" page (e.g. personalised ANC).
struct NoiseControlExtras: View {
    let session: DeviceSession

    var body: some View {
        if let feature = session.feature(PersonalisedANCFeature.self), feature.isAvailable {
            Group {
                SettingDivider()
                SettingToggleRow(title: "Personalised ANC", subtitle: "Tunes noise cancelling to your ears",
                                 isOn: feature.enabled ?? false) { feature.set(!(feature.enabled ?? false)) }
            }
        }
    }
}

// MARK: - Restart confirmation

/// Inline confirm step for writes that restart the device. Never a modal.
private struct RestartConfirmation: View {
    let title: String
    var detail: String?
    let onCancel: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text([detail, "Your device will restart."].compactMap { $0 }.joined(separator: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(PressableStyle())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10)
                Button(action: onRestart) {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(12)
        .background(Color.black, in: .rect(cornerRadius: 14))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Quick settings rows

struct LongPowerModeRow: View {
    let feature: LongPowerModeFeature
    @State private var pending: Bool?

    init(feature: LongPowerModeFeature, pending: Bool? = nil) {
        self.feature = feature
        _pending = State(initialValue: pending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingToggleRow(title: "Long battery life mode", subtitle: "Longer playback, AAC only",
                             isOn: feature.enabled ?? false) {
                let target = !(feature.enabled ?? false)
                pending = pending == target ? nil : target
            }
            if let pending {
                RestartConfirmation(
                    title: pending ? "Turn on Long battery life mode?" : "Turn off Long battery life mode?",
                    detail: pending ? "Spatial audio, bass enhancement and LDAC switch off." : nil,
                    onCancel: { self.pending = nil },
                    onRestart: {
                        feature.set(pending)
                        self.pending = nil
                    })
            }
        }
        .animation(Theme.spring, value: pending)
    }
}

struct DualConnectionRow: View {
    let feature: DualConnectionFeature
    @State private var pending: Bool?

    init(feature: DualConnectionFeature, pending: Bool? = nil) {
        self.feature = feature
        _pending = State(initialValue: pending)
    }

    var body: some View {
        let enabled = feature.enabled ?? false
        VStack(alignment: .leading, spacing: 10) {
            SettingToggleRow(
                title: "Dual connection",
                subtitle: enabled ? "Manage devices on the Devices page" : "Stay connected to two devices at once",
                isOn: enabled
            ) {
                if feature.restartsOnToggle {
                    pending = pending == nil ? !enabled : nil
                } else {
                    feature.setEnabled(!enabled)
                }
            }
            if let pending {
                RestartConfirmation(
                    title: pending ? "Turn on dual connection?" : "Turn off dual connection?",
                    onCancel: { self.pending = nil },
                    onRestart: {
                        feature.setEnabled(pending)
                        self.pending = nil
                    })
            }
        }
        .animation(Theme.spring, value: pending)
    }
}

struct AudioCodecRow: View {
    let feature: AudioCodecFeature
    @State private var pending: AudioCodec?

    init(feature: AudioCodecFeature, pending: AudioCodec? = nil) {
        self.feature = feature
        _pending = State(initialValue: pending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingLabel(title: "Audio quality")
            PillPicker(
                options: feature.codecs.map { ($0, $0.name) },
                selection: pending ?? feature.codec,
                onSelect: { codec in
                    if codec == feature.codec {
                        pending = nil
                    } else if feature.canSelect(codec) {
                        pending = codec
                    }
                })
            if let pending {
                RestartConfirmation(
                    title: "Switch to \(pending.name)?",
                    detail: pending == .ldac ? "LDAC uses more battery and may stutter where there's a lot of interference." : nil,
                    onCancel: { self.pending = nil },
                    onRestart: {
                        feature.select(pending)
                        self.pending = nil
                    })
                .padding(.top, 2)
            }
        }
        .animation(Theme.spring, value: pending)
    }
}

private struct SuperMicRows: View {
    let feature: SuperMicFeature
    let walkieTalkie: WalkieTalkieFeature?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingToggleRow(title: "Super Mic", isOn: feature.enabled ?? false) {
                feature.set(!(feature.enabled ?? false))
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingLabel(title: "Mic mode")
                PillPicker(options: MicMode.allCases.map { ($0, $0.name) },
                           selection: feature.micMode, onSelect: { feature.setMicMode($0) })
            }
            if let walkieTalkie {
                SettingToggleRow(title: "Walkie-talkie mode", isOn: walkieTalkie.enabled ?? false) {
                    walkieTalkie.set(!(walkieTalkie.enabled ?? false))
                }
            }
        }
    }
}

/// Small capsule action used inside rows (Start, Connect, …).
private struct RowButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Color.black, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A dot that breathes while something is in progress.
private struct PulsingDot: View {
    var size: CGFloat = 8
    var color: Color = Theme.primary
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(on ? 0.25 : 1)
            .scaleEffect(on ? 0.75 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Ear-tip fit test

private struct EarTipTestRow: View {
    let feature: EarTipTestFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SettingLabel(title: "Ear tip fit test", subtitle: feature.state == .idle ? "Checks the seal of each bud" : nil)
                Spacer(minLength: 12)
                switch feature.state {
                case .testing:
                    Text("Testing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                case .idle:
                    RowButton(title: "Start") { feature.start() }
                case .result, .timedOut:
                    HStack(spacing: 6) {
                        RowButton(title: "Again") { feature.start() }
                        Button { feature.dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 26, height: 26)
                                .background(Color.black, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle())
                        .foregroundStyle(Theme.secondary)
                    }
                }
            }
            if feature.state != .idle {
                EarTipResultPanel(state: feature.state)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Theme.spring, value: feature.state)
    }
}

private struct EarTipResultPanel: View {
    let state: EarTipTestFeature.State

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                side("L", fit: result?.left)
                Rectangle().fill(Theme.track).frame(width: 1, height: 30)
                side("R", fit: result?.right)
            }
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
        }
        .padding(12)
        .background(Color.black, in: .rect(cornerRadius: 14))
    }

    private var result: EarTipResult? {
        if case .result(let result) = state { return result }
        return nil
    }

    private func side(_ label: String, fit: EarTipFit?) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.doto(15))
                    .foregroundStyle(Theme.primary)
                if state == .testing {
                    PulsingDot()
                } else {
                    indicator(fit)
                }
            }
            Text(fitLabel(fit))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(fit == .good ? Theme.primary : Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func indicator(_ fit: EarTipFit?) -> some View {
        switch fit {
        case .good?: Circle().fill(Theme.primary).frame(width: 8, height: 8)
        case .adjust?: Circle().fill(Theme.accent).frame(width: 8, height: 8)
        default: Circle().strokeBorder(Theme.tertiary, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }

    private func fitLabel(_ fit: EarTipFit?) -> String {
        switch state {
        case .testing: return "Listening"
        case .timedOut: return "No result"
        default: break
        }
        switch fit {
        case .good?: return "Good seal"
        case .adjust?: return "Adjust"
        case .notDetected?: return "Not detected"
        case .unknown?, nil: return "Unknown"
        }
    }

    private var message: String {
        switch state {
        case .idle: return ""
        case .testing: return "Keep both earbuds in your ears."
        case .timedOut: return "No result arrived. Make sure both earbuds are in your ears and try again."
        case .result(let result):
            if result.left == .notDetected || result.right == .notDetected {
                return "Put both earbuds in your ears and try again."
            }
            switch (result.left == .adjust, result.right == .adjust) {
            case (true, true): return "Adjust both earbuds or try another tip size."
            case (true, false): return "Adjust the left earbud or try another tip size."
            case (false, true): return "Adjust the right earbud or try another tip size."
            case (false, false):
                return result.left == .good && result.right == .good ? "Both tips fit well." : "Try the test again."
            }
        }
    }
}

// MARK: - Case LED (Ear (1))

struct CaseLEDRow: View {
    let feature: CaseLEDFeature
    @State private var expanded: Bool

    init(feature: CaseLEDFeature, expanded: Bool = false) {
        self.feature = feature
        _expanded = State(initialValue: expanded)
    }
    @State private var slot: CaseLEDColours.Slot = .batteryHigh

    private static let palette: [RGB] = [
        RGB(0xFF, 0xFF, 0xFF), RGB(0xFF, 0x00, 0x00), RGB(0xFF, 0x80, 0x00), RGB(0xFF, 0xE0, 0x00),
        RGB(0x00, 0xFF, 0x00), RGB(0x00, 0xFF, 0xFF), RGB(0x00, 0x60, 0xFF), RGB(0x80, 0x00, 0xFF),
        RGB(0xFF, 0x00, 0xC0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                expanded.toggle()
                if expanded { feature.load() }
            } label: {
                HStack {
                    SettingLabel(title: "Case light", subtitle: "Colours for each battery state")
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            if expanded {
                editor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Theme.spring, value: expanded)
    }

    @ViewBuilder
    private var editor: some View {
        if let colours = feature.colours {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(CaseLEDColours.Slot.allCases, id: \.self) { item in
                        Button { slot = item } label: {
                            VStack(spacing: 5) {
                                swatch(colours[item], size: 18)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(item == slot ? Theme.primary : .clear, lineWidth: 1.5))
                                Text(item.name)
                                    .font(.system(size: 10, weight: item == slot ? .semibold : .regular))
                                    .foregroundStyle(item == slot ? Theme.primary : Theme.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                HStack(spacing: 0) {
                    ForEach(Self.palette, id: \.self) { colour in
                        Button { feature.set(slot, to: colour) } label: {
                            swatch(colour, size: 16)
                                .padding(4)
                                .overlay(Circle().strokeBorder(colours[slot] == colour ? Theme.primary : .clear, lineWidth: 1.5))
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(Color.black, in: .rect(cornerRadius: 14))
            .animation(Theme.spring, value: slot)
        } else {
            HStack(spacing: 8) {
                PulsingDot(size: 6)
                Text("Reading colours")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func swatch(_ colour: RGB, size: CGFloat) -> some View {
        Circle()
            .fill(Color(red: Double(colour.red) / 255, green: Double(colour.green) / 255, blue: Double(colour.blue) / 255))
            .frame(width: size, height: size)
    }
}

// MARK: - Devices page

/// "Devices" page of the pager card (dual connection). Shown while dual connection is on.
struct DevicesPage: View {
    let session: DeviceSession

    static func isAvailable(_ session: DeviceSession) -> Bool {
        guard let feature = session.feature(DualConnectionFeature.self) else { return false }
        return feature.isAvailable && feature.enabled == true
    }

    private var feature: DualConnectionFeature? { session.feature(DualConnectionFeature.self) }

    var body: some View {
        if let feature {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(feature.connectedCount) of \(DualConnectionFeature.maxConnected) connected")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .contentTransition(.numericText(value: Double(feature.connectedCount)))

                if !feature.listLoaded {
                    HStack(spacing: 8) {
                        PulsingDot(size: 6)
                        Text("Reading remembered devices")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                } else if feature.devices.isEmpty {
                    Text("No remembered devices yet. Pair a phone or another computer and it will appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(feature.devices.enumerated()), id: \.element.mac) { index, device in
                            if index > 0 { SettingDivider() }
                            DeviceRow(device: device, feature: feature)
                        }
                    }
                }
            }
            .animation(Theme.spring, value: feature.devices)
            .onAppear { feature.refresh() }
        }
    }
}

private struct DeviceRow: View {
    let device: DualConnectionDevice
    let feature: DualConnectionFeature

    private var busy: Bool { feature.pending.contains(device.mac) }
    private var atCapacity: Bool { feature.connectedCount >= DualConnectionFeature.maxConnected }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(device.isConnected ? Theme.accent : Theme.tertiary)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name.isEmpty ? "Unknown device" : device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                Text(device.isSelf ? "This Mac" : (device.isConnected ? "Connected" : "Not connected"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                Text(device.macString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer(minLength: 8)
            if busy {
                PulsingDot(size: 6)
                    .frame(width: 26, height: 26)
            } else if !device.isSelf {
                if device.isConnected {
                    RowButton(title: "Disconnect") { feature.setConnected(device, false) }
                } else {
                    RowButton(title: "Connect", enabled: !atCapacity) { feature.setConnected(device, true) }
                }
            }
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Find device

/// Find / ring controls under the product image.
struct FindDeviceButtons: View {
    let session: DeviceSession

    var body: some View {
        if let feature = session.feature(FindDeviceFeature.self), feature.isAvailable {
            HStack(spacing: 8) {
                ForEach(feature.sides, id: \.self) { side in
                    RingButton(side: suffix(side), ringing: feature.ringing.contains(side)) {
                        feature.toggle(side)
                    }
                }
            }
            .animation(Theme.spring, value: feature.ringing)
        }
    }

    private func suffix(_ side: FindDeviceFeature.Side) -> String {
        switch side {
        case .left: " L"
        case .right: " R"
        case .single: ""
        }
    }
}

private struct RingButton: View {
    /// " L", " R" or "" for a single unit.
    let side: String
    let ringing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: ringing ? "speaker.wave.2.fill" : "bell")
                    .font(.system(size: 10, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: ringing)
                    .frame(width: 14)
                Text((ringing ? "Stop" : "Ring") + side)
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Theme.primary)
            .frame(width: 92, height: 28)
            .background(ringing ? Theme.accent : Theme.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(ringing ? "Stop ringing" : "Play a sound to find it")
    }
}
