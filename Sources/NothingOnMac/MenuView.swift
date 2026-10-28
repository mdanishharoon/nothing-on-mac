import HeadphoneProtocol
import SwiftUI

struct MenuView: View {
    let controller: HeadphoneController
    var updates: UpdateChecker?

    private var session: DeviceSession? {
        controller.status == .connected ? controller.session : nil
    }

    var body: some View {
        VStack(spacing: 12) {
            TopBar(status: controller.status)
            Hero(controller: controller, session: session)
            if let session {
                ControlsPager(session: session)
                    .transition(Self.entrance(order: 0))
                EQCard(session: session)
                    .transition(Self.entrance(order: 1))
            } else {
                ConnectionCard(controller: controller)
                    .transition(Self.entrance(order: 0))
            }
            if let release = updates?.available {
                UpdateBanner(release: release)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Footer(controller: controller, session: session)
        }
        .padding(14)
        .frame(width: 340)
        .background(Color.black)
        .overlay(alignment: .top) { NoticeBanner(message: session?.notice) }
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: controller.status)
        .onAppear { controller.checkBluetooth() }
        .onChange(of: controller.status) { controller.checkBluetooth() }
    }

    /// Cards rise and fade in one after another.
    private static func entrance(order: Int) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14))
                .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.06 * Double(order))),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        )
    }
}

private struct NoticeBanner: View {
    let message: String?

    var body: some View {
        ZStack {
            if let message {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.track, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: message)
    }
}

// MARK: - Header

private struct TopBar: View {
    let status: HeadphoneController.Status

    var body: some View {
        HStack(alignment: .center) {
            Text("NOTHING")
                .font(.doto(30))
                .foregroundStyle(Theme.primary)
            Spacer()
            StatusIndicator(status: status)
        }
        .padding(.horizontal, 4)
    }
}

private struct StatusIndicator: View {
    let status: HeadphoneController.Status

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(isBusy && pulse ? 0.25 : 1)
                .animation(isBusy ? .easeInOut(duration: 0.6).repeatForever() : .default, value: pulse)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .contentTransition(.opacity)
        }
        .onAppear { pulse = true }
    }

    private var isBusy: Bool {
        switch status {
        case .connecting, .restarting: true
        default: false
        }
    }

    private var color: Color {
        switch status {
        case .connected: Theme.accent
        case .connecting, .restarting: Theme.primary
        case .searching, .unavailable: Theme.tertiary
        }
    }

    private var label: String {
        switch status {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .restarting: "Restarting"
        case .searching, .unavailable: "Not connected"
        }
    }
}

private struct Hero: View {
    let controller: HeadphoneController
    let session: DeviceSession?

    private var connected: Bool { session != nil }
    private var model: DeviceSKU? { session?.sku ?? controller.displayModel }
    private var singleUnit: Bool {
        model.flatMap { ModelProfile.profile(base: $0.base)?.formFactor.isSingleUnit } ?? true
    }
    private var battery: BatteryFeature? { session?.feature(BatteryFeature.self) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                DotGrid()
                Group {
                    if singleUnit {
                        productImage(model?.images.duo)
                            .padding(.vertical, 6)
                    } else {
                        HStack(alignment: .bottom, spacing: 6) {
                            budColumn(model?.images.left, component: BatteryReading.left, label: "L")
                            budColumn(model?.images.case, component: BatteryReading.case, label: "Case", wide: true)
                            budColumn(model?.images.right, component: BatteryReading.right, label: "R")
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .id(model?.sku)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            .frame(height: singleUnit ? 118 : 132)
            .saturation(connected ? 1 : 0)
            .opacity(connected ? 1 : 0.4)
            .scaleEffect(connected ? 1 : 0.92)
            .animation(.spring(response: 0.7, dampingFraction: 0.8), value: connected)
            .animation(.easeInOut(duration: 0.35), value: model?.sku)

            VStack(spacing: 6) {
                Text(model?.name ?? "Nothing")
                    .font(.doto(20))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if singleUnit, let reading = battery?.readings[BatteryReading.headphones] {
                    BatteryGauge(level: reading.level, isCharging: reading.isCharging)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                if let session {
                    FindDeviceButtons(session: session)
                }
            }
        }
    }

    @ViewBuilder
    private func productImage(_ name: String?) -> some View {
        if let name, let image = AppResources.image(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Color.clear
        }
    }

    private func budColumn(_ image: String?, component: UInt8, label: String, wide: Bool = false) -> some View {
        let reading = battery?.readings[component]
        return VStack(spacing: 6) {
            productImage(image)
                .frame(maxHeight: wide ? 96 : 104)
            HStack(spacing: 3) {
                if reading?.isCharging == true {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold))
                }
                Text(reading.map { "\($0.level)%" } ?? label)
                    .font(.doto(13))
                    .contentTransition(.numericText(value: Double(reading?.level ?? 0)))
            }
            .foregroundStyle(reading == nil ? Theme.tertiary : (reading!.level <= 15 && !reading!.isCharging ? Theme.accent : Theme.primary))
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: reading?.level)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pager

/// Pages of the controls card, in ear-web's order, filtered to what the model supports.
private enum ControlPage: Hashable {
    case noiseControl, quickSettings, controls, devices

    var title: String {
        switch self {
        case .noiseControl: "Noise control"
        case .quickSettings: "Quick settings"
        case .controls: "Controls"
        case .devices: "Devices"
        }
    }
}

private struct ControlsPager: View {
    let session: DeviceSession

    @State private var page: ControlPage = .noiseControl
    @State private var forward = true

    private var pages: [ControlPage] {
        var pages: [ControlPage] = []
        if session.feature(NoiseControlFeature.self)?.isAvailable == true { pages.append(.noiseControl) }
        pages.append(.quickSettings)
        if GesturesPage.isAvailable(session) { pages.append(.controls) }
        if DevicesPage.isAvailable(session) { pages.append(.devices) }
        return pages
    }

    private var current: ControlPage { pages.contains(page) ? page : pages[0] }

    var body: some View {
        let pages = pages
        let index = pages.firstIndex(of: current) ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(current.title)
                    .font(.doto(18))
                    .foregroundStyle(Theme.primary)
                    .id(current)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: forward ? 12 : -12)),
                        removal: .opacity.combined(with: .offset(x: forward ? -12 : 12))
                    ))
                Spacer()
                if pages.count > 1 {
                    PageControl(count: pages.count, page: index) { show(pages[$0], from: index, to: $0) }
                }
            }
            ZStack(alignment: .top) {
                Group {
                    switch current {
                    case .noiseControl: NoiseControlPage(session: session)
                    case .quickSettings: QuickSettingsPage(session: session)
                    case .controls: GesturesPage(session: session)
                    case .devices: DevicesPage(session: session)
                    }
                }
                .id(current)
                .transition(.push(from: forward ? .trailing : .leading))
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .clipped()
        }
        .cardStyle()
    }

    private func show(_ target: ControlPage, from: Int, to: Int) {
        guard target != current else { return }
        forward = to > from
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { page = target }
    }
}

// MARK: - Noise control

private struct NoiseControlPage: View {
    let session: DeviceSession

    private enum Kind: Hashable { case noiseCancelling, transparency, off }

    /// Strength to restore when switching back to noise cancelling.
    @State private var lastStrength: ANCStrength?
    @Namespace private var selector

    private var feature: NoiseControlFeature? { session.feature(NoiseControlFeature.self) }

    private var kind: Kind? {
        switch feature?.mode {
        case .noiseCancelling: .noiseCancelling
        case .transparency: .transparency
        case .off: .off
        case nil: nil
        }
    }

    private var kinds: [Kind] {
        feature?.hasTransparency == true ? [.noiseCancelling, .transparency, .off] : [.noiseCancelling, .off]
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(kinds, id: \.self) { mode in
                        modeButton(mode)
                    }
                }
                .padding(4)
                .background(Color.black, in: Capsule())

                HStack(spacing: 0) {
                    ForEach(kinds, id: \.self) { mode in
                        Text(label(for: mode))
                            .font(.system(size: 11, weight: kind == mode ? .semibold : .regular))
                            .foregroundStyle(kind == mode ? Theme.primary : Theme.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if case .noiseCancelling(let strength) = feature?.mode, let strengths = feature?.strengths, !strengths.isEmpty {
                DotLevelPicker(
                    options: strengths.map { ($0, $0.name) },
                    selection: strength,
                    onSelect: { feature?.set(.noiseCancelling($0)) }
                )
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear { lastStrength = strength }
                .onChange(of: strength) { lastStrength = strength }
            }

            NoiseControlExtras(session: session)
        }
        .animation(Theme.spring, value: kind)
        .animation(Theme.spring, value: feature?.mode)
    }

    private func label(for mode: Kind) -> String {
        switch mode {
        case .noiseCancelling: "Cancelling"
        case .transparency: "Transparency"
        case .off: "Off"
        }
    }

    private func modeButton(_ mode: Kind) -> some View {
        let selected = kind == mode
        return Button {
            switch mode {
            case .noiseCancelling:
                let strengths = feature?.strengths ?? []
                let strength = lastStrength.flatMap { strengths.contains($0) ? $0 : nil } ?? strengths.first ?? .high
                feature?.set(.noiseCancelling(strength))
            case .transparency: feature?.set(.transparency)
            case .off: feature?.set(.off)
            }
        } label: {
            Group {
                switch mode {
                case .noiseCancelling: NoiseCancellingIcon()
                case .transparency: TransparencyIcon()
                case .off: NoiseOffIcon()
                }
            }
            .frame(width: 22, height: 22)
            .foregroundStyle(selected ? Color.black : Theme.primary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                if selected {
                    Capsule().fill(Theme.primary).matchedGeometryEffect(id: "selector", in: selector)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Quick settings

private struct QuickSettingsPage: View {
    let session: DeviceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let spatial = session.feature(SpatialAudioFeature.self), spatial.isAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    SettingLabel(title: "Spatial audio")
                    PillPicker(
                        options: spatial.modes.map { ($0, $0.name) },
                        selection: spatial.mode ?? .off,
                        onSelect: { spatial.set($0) }
                    )
                }
                SettingDivider()
            }
            if let latency = session.feature(LowLatencyFeature.self) {
                SettingToggleRow(title: "Low latency mode", subtitle: "Reduces audio lag for games and video",
                                 isOn: latency.enabled ?? false) {
                    latency.set(!(latency.enabled ?? false))
                }
            }
            QuickSettingsExtras(session: session)
        }
    }
}

// MARK: - Equaliser

private struct EQCard: View {
    let session: DeviceSession

    private var eq: EQFeature? { session.feature(EQFeature.self) }

    var body: some View {
        if let eq {
            Card(title: "Equaliser") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                    ForEach(session.profile.presets, id: \.self) { option in
                        PillButton(title: option.name, selected: eq.isSelected(option)) { eq.select(option) }
                    }
                    if session.profile.customLevel != nil {
                        PillButton(title: "Custom", selected: eq.isCustom) { eq.selectCustom() }
                    }
                    if session.profile.hasAdvancedEQ {
                        PillButton(title: "Advanced", selected: eq.advancedActive) { eq.selectAdvanced() }
                    }
                }

                if let unlisted = eq.unlistedLevelName {
                    Text("\(unlisted) is active.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }

                if eq.isCustom {
                    CustomEQSliders(eq: eq)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                EQExtrasSection(session: session)
            }
            .animation(Theme.spring, value: eq.level)
            .animation(Theme.spring, value: eq.advancedActive)
        }
    }
}

private struct CustomEQSliders: View {
    @Bindable var eq: EQFeature

    var body: some View {
        VStack(spacing: 6) {
            DotSlider(title: "Bass", value: $eq.customEQ.bass, range: CustomEQ.range, onCommit: eq.commitCustomEQ)
            DotSlider(title: "Mid", value: $eq.customEQ.mid, range: CustomEQ.range, onCommit: eq.commitCustomEQ)
            DotSlider(title: "Treble", value: $eq.customEQ.treble, range: CustomEQ.range, onCommit: eq.commitCustomEQ)
        }
        .padding(12)
        .background(Color.black, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Disconnected

private struct ConnectionCard: View {
    let controller: HeadphoneController

    var body: some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if let issue = controller.bluetoothIssue {
                PillButton(title: issue.actionTitle) { NSWorkspace.shared.open(issue.settingsURL) }
                    .frame(width: 200)
            } else {
                switch controller.status {
                case .connecting, .restarting:
                    LoadingDots().frame(height: 34)
                default:
                    PillButton(title: "Connect") { controller.reconnect() }
                        .frame(width: 140)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
    }

    private var message: String {
        if let issue = controller.bluetoothIssue { return issue.message }
        return switch controller.status {
        case .searching: "Waiting for your Nothing or CMF device to connect to this Mac."
        case .connecting(let name): "Connecting to \(name)…"
        case .restarting: "Your device is restarting to apply the change."
        case .unavailable(let reason): reason
        case .connected: ""
        }
    }
}

/// Three dots lighting up in turn.
private struct LoadingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 2.2
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    let wave = (sin(phase - Double(index) * 0.9) + 1) / 2
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: 7, height: 7)
                        .opacity(0.25 + 0.75 * wave)
                        .scaleEffect(0.8 + 0.3 * wave)
                }
            }
        }
    }
}

// MARK: - Footer

private struct Footer: View {
    let controller: HeadphoneController
    let session: DeviceSession?

    var body: some View {
        HStack(spacing: 14) {
            if let firmware = session?.firmware {
                Text("Firmware \(firmware)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            if session != nil {
                Button { controller.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PressableStyle())
                .foregroundStyle(Theme.secondary)
                .help("Re-read settings from the device")
            }
            AppMenu()
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }
}

private struct UpdateBanner: View {
    let release: UpdateChecker.Release

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.accent).frame(width: 7, height: 7)
            Text("Version \(release.version) is available")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primary)
            Spacer()
            PillButton(title: "Download") { NSWorkspace.shared.open(release.page) }
                .frame(width: 96)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }
}

/// The "…" menu: login item, version, project page, quit.
private struct AppMenu: View {
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Menu {
            Toggle("Open at login", isOn: Binding(
                get: { openAtLogin },
                set: { LoginItem.setEnabled($0); openAtLogin = LoginItem.isEnabled }
            ))
            Divider()
            Button("Nothing on Mac \(AppInfo.version)") {}
                .disabled(true)
            Button("View on GitHub") { NSWorkspace.shared.open(AppInfo.repository) }
            Divider()
            Button("Quit Nothing on Mac") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 26, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.secondary)
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }
}
