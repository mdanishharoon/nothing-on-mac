import HeadphoneProtocol

/// One capability of a connected device (noise control, gestures, codec, …).
///
/// Every feature is created for every device; each decides from `session.profile` and
/// `session.config` whether it applies (`isAvailable`) and only talks to the device if so.
@MainActor
protocol DeviceFeature: AnyObject {
    /// Whether this model (and its firmware-matched config) supports the feature.
    var isAvailable: Bool { get }
    /// Reads sent as soon as the control channel opens. Only profile-gated reads belong here;
    /// config-gated ones go in `configDidLoad()`.
    var initialReads: [Request] { get }
    /// Called once the firmware arrives and the config is chosen (`session.config` may be nil
    /// when no config matches). Returns the reads to send.
    func configDidLoad() -> [Request]
    /// Handles a frame from the device; returns true if it was this feature's.
    func handle(_ frame: Frame) -> Bool
    /// A user-facing reason this feature's current state forbids `action`, or nil.
    func blockReason(for action: GuardedAction) -> String?
}

extension DeviceFeature {
    var initialReads: [Request] { [] }
    func configDidLoad() -> [Request] { [] }
    func blockReason(for action: GuardedAction) -> String? { nil }
}

/// Actions other features may veto (ear-web's client-side mutual exclusions).
enum GuardedAction: Equatable {
    case selectEQPreset(level: UInt8)
    case selectDiracOpteo
    case enableAdvancedEQ
    case enableSpatialAudio
    case enableBass
    case selectTransparency
    case changeCodec
    case enablePersonalSound
}

/// Creates every feature for a session. Each feature group lives in its own file and provides
/// its own `…Features(_:)` factory, so groups can be developed independently.
@MainActor
enum FeatureRegistry {
    static func make(_ session: DeviceSession) -> [any DeviceFeature] {
        coreFeatures(session)
            + gestureFeatures(session)
            + eqExtraFeatures(session)
            + settingsFeatures(session)
    }
}
