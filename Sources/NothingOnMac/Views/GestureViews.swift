import HeadphoneProtocol
import SwiftUI

/// "Controls" page of the pager card.
struct GesturesPage: View {
    let session: DeviceSession

    @State private var groupID: String?
    @State private var expandedSlot: String?

    init(session: DeviceSession, group: String? = nil, expanded: String? = nil) {
        self.session = session
        _groupID = State(initialValue: group)
        _expandedSlot = State(initialValue: expanded)
    }

    static func isAvailable(_ session: DeviceSession) -> Bool {
        session.feature(GestureFeature.self)?.isAvailable == true
    }

    private var feature: GestureFeature? { session.feature(GestureFeature.self) }

    var body: some View {
        if let feature, let layout = feature.layout, let first = layout.groups.first {
            let group = layout.groups.first { $0.id == groupID } ?? first
            VStack(alignment: .leading, spacing: 8) {
                if layout.groups.count > 1 {
                    PillPicker(
                        options: layout.groups.map { ($0.id, $0.name) },
                        selection: group.id,
                        onSelect: { id in
                            withAnimation(Theme.spring) {
                                groupID = id
                                expandedSlot = nil
                            }
                        }
                    )
                    .padding(.bottom, 2)
                }
                VStack(spacing: 0) {
                    ForEach(Array(group.slots.enumerated()), id: \.element.id) { index, slot in
                        if index > 0 { SettingDivider() }
                        GestureSlotRow(
                            feature: feature, group: group, slot: slot,
                            expanded: expandedSlot == slot.id,
                            onToggleExpanded: {
                                withAnimation(Theme.spring) {
                                    expandedSlot = expandedSlot == slot.id ? nil : slot.id
                                }
                            },
                            onSelect: { option in
                                feature.select(option, slot: slot, in: group)
                                // Keep the list open for "Noise control" so its cycle can be edited.
                                if !option.isNoiseCycle {
                                    withAnimation(Theme.spring) { expandedSlot = nil }
                                }
                            }
                        )
                    }
                }
                .id(group.id)
                .transition(.opacity)
            }
            .onAppear { feature.refresh() }
        }
    }
}

private struct GestureSlotRow: View {
    let feature: GestureFeature
    let group: GestureGroup
    let slot: GestureSlot
    let expanded: Bool
    let onToggleExpanded: () -> Void
    let onSelect: (GestureOption) -> Void

    private var key: GestureSlotKey { group.key(slot) }
    private var action: UInt8? { feature.state.action(key) }
    private var current: GestureOption? { action.flatMap(slot.option(for:)) }
    private var cycle: NoiseCycle { feature.state.cycle(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleExpanded) {
                HStack(spacing: 10) {
                    SettingLabel(title: slot.title,
                                 subtitle: current?.isNoiseCycle == true ? cycleSummary : nil)
                    Spacer(minLength: 8)
                    Text(action.map(slot.label(for:)) ?? "–")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                              spacing: 6) {
                        ForEach(slot.options, id: \.self) { option in
                            OptionPill(title: option.label, selected: option == current) { onSelect(option) }
                        }
                    }
                    if current?.isNoiseCycle == true {
                        VStack(spacing: 6) {
                            ForEach(NoiseCycle.Mode.allCases, id: \.self) { mode in
                                HStack {
                                    Text(mode.name)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.primary)
                                    Spacer()
                                    NothingToggle(isOn: cycle.contains(mode)) {
                                        feature.toggle(mode, slot: slot, in: group)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(Theme.spring, value: current)
        .animation(Theme.spring, value: cycle)
    }

    private var cycleSummary: String {
        cycle.modes.map(\.name).joined(separator: " · ")
    }
}

/// A choice in an expanded slot: white when it's the current action.
private struct OptionPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color.black : Theme.primary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(selected ? Theme.primary : Color.black, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}
