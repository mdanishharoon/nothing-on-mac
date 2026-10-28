import HeadphoneProtocol
import Observation

// Advanced EQ values (incl. B192 precision driver), bass enhance / ultra bass, flat EQ.
// Owned by the EQ work stream.

extension FeatureRegistry {
    static func eqExtraFeatures(_ session: DeviceSession) -> [any DeviceFeature] {
        [AdvancedEQFeature(session), BassFeature(session), FlatEQFeature(session)]
    }
}

/// Which band set of the advanced EQ is being edited. Only B192 (`supportMiddleEq`) has a driver set.
enum EQBandSet: Hashable {
    case main, driver
}

/// Band values of the advanced (parametric) EQ. Switching Advanced on and off is `EQFeature`'s job;
/// this reads and writes the bands. Values are read when the editor appears (`refresh()`).
@MainActor @Observable
final class AdvancedEQFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    /// Working bands, edited live by the UI and sent with `commit()`.
    private(set) var main = AdvancedEQLayout.fixedDefault
    private(set) var driver = AdvancedEQLayout.defaults(AdvancedEQLayout.driverDefaults)

    @ObservationIgnored private var reportedMain: [ParametricBand]?
    @ObservationIgnored private var reportedDriver: [ParametricBand]?
    @ObservationIgnored private var requested = false
    @ObservationIgnored private var driverModeEnableSent = false

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.profile.hasAdvancedEQ }

    /// B192's layout: 1–8 free main bands plus 1–4 precision-driver bands.
    var isFlexible: Bool { session.config?.flag("supportMiddleEq") == true }

    func bands(_ set: EQBandSet) -> [ParametricBand] {
        set == .driver && isFlexible ? driver : main
    }

    func bandLimit(_ set: EQBandSet) -> ClosedRange<Int> {
        guard isFlexible else { return 8...8 }
        return set == .driver ? AdvancedEQLayout.driverBandLimit : AdvancedEQLayout.mainBandLimit
    }

    func frequencyRange(_ set: EQBandSet, band index: Int) -> ClosedRange<Float> {
        if isFlexible { return set == .driver ? AdvancedEQLayout.driverRange : AdvancedEQLayout.mainRange }
        let fixed = AdvancedEQLayout.fixedBands
        return fixed[min(max(index, 0), fixed.count - 1)].range
    }

    /// Reads the current values (and, on B192, the precision-driver mode and values).
    func refresh() {
        guard isAvailable else { return }
        requested = true
        session.send([.readAdvancedEQValues] + (isFlexible ? driverReads : []))
    }

    private var driverReads: [Request] { [.readPrecisionDriverMode, .readPrecisionDriverValues] }

    func configDidLoad() -> [Request] {
        adoptReported()
        // The editor may have asked for values before the config said this model has a driver set.
        return isAvailable && requested && isFlexible ? driverReads : []
    }

    // MARK: Editing (live; `commit()` sends)

    func setGain(_ gain: Float, at index: Int, in set: EQBandSet) {
        let range = AdvancedEQLayout.gainRange
        update(set, index) { $0.gain = min(max(gain, range.lowerBound), range.upperBound) }
    }

    func setFrequency(_ frequency: Float, at index: Int, in set: EQBandSet) {
        let range = frequencyRange(set, band: index)
        update(set, index) { $0.frequency = min(max(frequency.rounded(), range.lowerBound), range.upperBound) }
    }

    func setQ(_ q: Float, at index: Int, in set: EQBandSet) {
        let range = AdvancedEQLayout.qRange
        update(set, index) { $0.q = min(max((q * 10).rounded() / 10, range.lowerBound), range.upperBound) }
    }

    /// Adds a band in the widest frequency gap; returns its index after sorting.
    @discardableResult
    func addBand(to set: EQBandSet) -> Int? {
        guard isFlexible, bands(set).count < bandLimit(set).upperBound else { return nil }
        var list = bands(set)
        let frequency = AdvancedEQLayout.insertionFrequency(existing: list.map(\.frequency),
                                                            in: frequencyRange(set, band: 0))
        list.append(ParametricBand(frequency: frequency))
        list.sort { $0.frequency < $1.frequency }
        replace(set, with: list)
        commit()
        return list.firstIndex { $0.frequency == frequency }
    }

    /// Removes a band (at least one always remains); returns the index to select next.
    @discardableResult
    func removeBand(at index: Int, from set: EQBandSet) -> Int {
        var list = bands(set)
        guard isFlexible, list.count > bandLimit(set).lowerBound, list.indices.contains(index) else { return index }
        list.remove(at: index)
        replace(set, with: list)
        commit()
        return min(index, list.count - 1)
    }

    /// Sends the whole band set (both sets on B192).
    func commit() {
        guard isAvailable else { return }
        if session.feature(FlatEQFeature.self)?.isOn == true {
            session.show(FlatEQFeature.blockedMessage)
            adoptReported()
            return
        }
        if isFlexible {
            let requests = Request.setAdvancedAndPrecisionEQ(main: main, driver: driver, firmware: session.firmware)
            session.send(requests)
            reportedDriver = ParametricEQPacket(payload: requests[1].payload)?.bands
        } else {
            session.send(.setAdvancedEQValues(main))
        }
        reportedMain = main
    }

    private func update(_ set: EQBandSet, _ index: Int, _ change: (inout ParametricBand) -> Void) {
        var list = bands(set)
        guard list.indices.contains(index) else { return }
        change(&list[index])
        replace(set, with: list)
    }

    private func replace(_ set: EQBandSet, with list: [ParametricBand]) {
        if set == .driver && isFlexible { driver = list } else { main = list }
    }

    // MARK: Device replies

    func handle(_ frame: Frame) -> Bool {
        switch EQExtraMessage(frame: frame) {
        case .advancedEQValues(let packet):
            reportedMain = packet.bands
        case .precisionDriverValues(let packet):
            reportedDriver = packet.bands
        case .precisionDriverMode(let enabled):
            // ear-web turns the precision-driver mode on once per session if it reads as off.
            if !enabled, isFlexible, !driverModeEnableSent {
                driverModeEnableSent = true
                session.send(.enablePrecisionDriverMode)
            }
            return true
        default:
            return false
        }
        adoptReported()
        return true
    }

    /// Working bands from the last reported (or sent) values, or the layout's defaults when the
    /// device's band count doesn't fit the layout.
    private func adoptReported() {
        if isFlexible {
            main = Self.fitted(reportedMain, count: AdvancedEQLayout.mainBandLimit) { _ in AdvancedEQLayout.mainRange }
                ?? AdvancedEQLayout.defaults(AdvancedEQLayout.mainDefaults)
            driver = Self.fitted(reportedDriver, count: AdvancedEQLayout.driverBandLimit) { _ in AdvancedEQLayout.driverRange }
                ?? AdvancedEQLayout.defaults(AdvancedEQLayout.driverDefaults)
        } else {
            let fixed = AdvancedEQLayout.fixedBands
            main = Self.fitted(reportedMain, count: fixed.count...fixed.count) { fixed[$0].range }
                ?? AdvancedEQLayout.fixedDefault
        }
    }

    /// The reported bands clamped into the editor's ranges, or nil if their count doesn't fit.
    private static func fitted(_ bands: [ParametricBand]?, count: ClosedRange<Int>,
                               range: (Int) -> ClosedRange<Float>) -> [ParametricBand]? {
        guard let bands, count.contains(bands.count) else { return nil }
        func clamp(_ value: Float, _ limits: ClosedRange<Float>, fallback: Float) -> Float {
            value.isFinite ? min(max(value, limits.lowerBound), limits.upperBound) : fallback
        }
        return bands.enumerated().map { index, band in
            let frequencies = range(index)
            return ParametricBand(gain: clamp(band.gain, AdvancedEQLayout.gainRange, fallback: 0),
                                  frequency: clamp(band.frequency, frequencies, fallback: frequencies.lowerBound),
                                  q: clamp(band.q, AdvancedEQLayout.qRange, fallback: 1),
                                  filterType: band.filterType)
        }
    }
}

/// Bass enhance / ultra bass: on/off plus a 5-stage (wire 2…10) or 3-stage (wire 0/5/10) level.
@MainActor @Observable
final class BassFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var enabled: Bool?
    /// UI level (1…5, or 0…2 on three-stage models); nil until known.
    private(set) var level: Int?

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.profile.bass != nil }
    var initialReads: [Request] { [.readBass] }

    var title: String { session.profile.bass?.title ?? "Bass enhance" }
    var scheme: BassScheme { BassScheme(threeStage: session.profile.bass?.threeStage ?? false) }

    func setEnabled(_ on: Bool) {
        if on, !session.permits(.enableBass) { return }
        var newLevel = level ?? 1
        // Three-stage level 0 means off, so switching on starts at level 1.
        if on, scheme == .threeStage, newLevel == 0 { newLevel = 1 }
        enabled = on
        level = newLevel
        session.send(.setBass(enabled: on, wireLevel: scheme.wire(level: newLevel)))
    }

    func select(level newLevel: Int) {
        guard scheme.levels.contains(newLevel) else { return }
        var on = enabled ?? false
        if scheme == .threeStage {
            // Picking level 0 turns bass off; 1 or 2 turns it on.
            if newLevel > 0, !session.permits(.enableBass) { return }
            on = newLevel > 0
        }
        enabled = on
        level = newLevel
        session.send(.setBass(enabled: on, wireLevel: scheme.wire(level: newLevel)))
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .bass(let on, let wire)? = EQExtraMessage(frame: frame) else { return false }
        enabled = on
        if let value = scheme.level(wire: wire) { level = value }
        return true
    }

    func blockReason(for action: GuardedAction) -> String? {
        guard action == .enableSpatialAudio, enabled == true, session.config?.flag("mutuallyExclusive") == true else { return nil }
        return "Spatial audio isn't available while \(title.lowercased()) is on."
    }
}

/// Flat EQ (B192 studio switch). Read-only: the user turns it off on the left earcup.
@MainActor @Observable
final class FlatEQFeature: DeviceFeature {
    @ObservationIgnored unowned let session: DeviceSession
    private(set) var isOn = false

    static let blockedMessage = "Flat EQ is on. Switch it off on the left earcup."

    init(_ session: DeviceSession) { self.session = session }

    var isAvailable: Bool { session.config?.flag("supportStudio") == true }

    func configDidLoad() -> [Request] {
        isAvailable ? [.readFlatEQ] : []
    }

    func handle(_ frame: Frame) -> Bool {
        guard case .flatEQ(let on)? = EQExtraMessage(frame: frame) else { return false }
        isOn = on && isAvailable
        return true
    }

    func blockReason(for action: GuardedAction) -> String? {
        guard isOn else { return nil }
        switch action {
        case .selectEQPreset, .selectDiracOpteo, .enableAdvancedEQ, .selectTransparency, .enableSpatialAudio:
            return Self.blockedMessage
        default:
            return nil
        }
    }
}
