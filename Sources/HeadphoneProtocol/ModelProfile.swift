// Per-model traits that ear-web hard-codes in its pages and `modelBase` gates rather than reading
// from ear_config_file.json. Config-driven features (dual connection, codec, spatial audio, …) are
// read from `ModelConfig` instead.
//
// Deliberate departures from ear-web, where its behaviour looks like a bug:
//  - B175 rings with the single-unit payload [0x06, on] (ear-web sends the left-earbud payload).
//  - B185 bass level changes are written (ear-web reads but never writes them).
//  - B190 runs the ear-tip fit test its config advertises (ear-web never sends the start command).
//  - B173 and B190 show an active Advanced EQ after a read (ear-web doesn't).

public enum FormFactor: Sendable {
    case earbuds, headphones, neckband, openEar

    /// Single-unit devices report one battery (component 0x06) and have no case.
    public var isSingleUnit: Bool { self == .headphones || self == .neckband }
}

public enum ANCStyle: Sendable {
    case none
    /// Noise cancelling / Transparency / Off, strengths from the config's ancLevel bits.
    case full
    /// Noise cancelling / Transparency / Off with no strength choice (cancelling is sent as High).
    case basic
    /// Ear (1): Low and High strengths.
    case lowHigh
    /// CMF Buds Pro: High, Mid and Low strengths.
    case highMidLow
    /// Ear (stick): cancelling or off only, and only on firmware x.x.2.x.
    case cancellingOff
}

public enum EQFamily: Sendable {
    /// 0xC01F / 0x401F / 0xF010.
    case preset
    /// "Listening mode": 0xC050 / 0x4050 / 0xF01D.
    case listeningMode
}

public struct EQPresetOption: Hashable, Sendable {
    public let level: UInt8
    public let name: String

    public init(_ level: UInt8, _ name: String) {
        self.level = level
        self.name = name
    }
}

public struct BassProfile: Sendable {
    public let title: String
    /// Three stages (wire 0/5/10, 0 = off) instead of five (wire 2…10).
    public let threeStage: Bool
}

public enum RingStyle: Sendable {
    /// Ear (1): one command rings both buds, payload [on].
    case both
    /// Each bud separately, payload [0x02 left | 0x03 right, on].
    case perSide
    /// Single-unit device, payload [0x06, on].
    case single
}

public struct ModelProfile: Sendable {
    public let base: String
    public let formFactor: FormFactor
    public let anc: ANCStyle
    public let eqFamily: EQFamily
    /// Preset buttons in UI order (excluding Custom and Advanced).
    public let presets: [EQPresetOption]
    /// Wire level of the Custom preset, if the model has one.
    public let customLevel: UInt8?
    /// Advanced (parametric) EQ: selected with 0xF04F, status read with 0xC04C.
    public let hasAdvancedEQ: Bool
    public let bass: BassProfile?
    /// In-ear (or over-ear) detection toggle; nil when the model has none.
    public let inEarDetectionLabel: String?
    public let earTipFitTest: Bool
    public let ring: RingStyle
    public let caseLED: Bool
    public let personalisedANC: Bool
    public let sendsUTCTime: Bool
    /// Level a device may report for Dirac Opteo when its button isn't offered (shown as a note).
    public let hiddenDiracLevel: UInt8?

    public static func profile(base: String) -> ModelProfile? {
        all[base]
    }

    public static let all: [String: ModelProfile] = {
        let classic = [EQPresetOption(0, "Balanced"), .init(3, "More bass"), .init(2, "More treble"), .init(1, "Voice")]
        let listening = [EQPresetOption(0, "Dirac Opteo"), .init(3, "Pop"), .init(1, "Rock"), .init(5, "Classical"),
                         .init(2, "Electronic"), .init(4, "Vocals")]
        let listeningNoDirac = Array(listening.dropFirst())
        let ultra5 = BassProfile(title: "Ultra bass", threeStage: false)
        let ultra3 = BassProfile(title: "Ultra bass", threeStage: true)
        let enhance5 = BassProfile(title: "Bass enhance", threeStage: false)
        let enhance3 = BassProfile(title: "Bass enhance", threeStage: true)

        func make(_ base: String, _ form: FormFactor, anc: ANCStyle, eq: EQFamily = .preset,
                  presets: [EQPresetOption], custom: UInt8?, advanced: Bool = false, bass: BassProfile? = nil,
                  inEar: String? = "In-ear detection", earTip: Bool = false, ring: RingStyle = .perSide,
                  caseLED: Bool = false, personalisedANC: Bool = false, utc: Bool = true,
                  hiddenDirac: UInt8? = nil) -> (String, ModelProfile) {
            (base, ModelProfile(
                base: base, formFactor: form, anc: anc, eqFamily: eq, presets: presets, customLevel: custom,
                hasAdvancedEQ: advanced, bass: bass, inEarDetectionLabel: inEar, earTipFitTest: earTip,
                ring: ring, caseLED: caseLED, personalisedANC: personalisedANC, sendsUTCTime: utc,
                hiddenDiracLevel: hiddenDirac))
        }

        return Dictionary(uniqueKeysWithValues: [
            make("B181", .earbuds, anc: .lowHigh, presets: classic, custom: nil, ring: .both, caseLED: true, utc: false),
            make("B157", .earbuds, anc: .cancellingOff, presets: classic, custom: 5, advanced: true),
            make("B155", .earbuds, anc: .full, presets: classic, custom: 5, advanced: true, earTip: true, personalisedANC: true),
            make("B171", .earbuds, anc: .full, presets: classic, custom: 5, advanced: true, bass: enhance5, earTip: true),
            make("B162", .earbuds, anc: .full, presets: classic, custom: 5, bass: enhance5, earTip: true),
            make("B163", .earbuds, anc: .highMidLow, presets: classic, custom: 5),
            make("B164", .neckband, anc: .full, presets: classic, custom: 5, bass: ultra5, inEar: nil, ring: .single),
            make("B168", .earbuds, anc: .basic, eq: .listeningMode, presets: listening, custom: 6, bass: ultra5),
            make("B172", .earbuds, anc: .full, eq: .listeningMode, presets: listening, custom: 6, bass: ultra5, earTip: true),
            make("B195", .earbuds, anc: .full, eq: .listeningMode, presets: listening, custom: 6, bass: ultra3, earTip: true),
            make("B174", .openEar, anc: .none, presets: classic, custom: 5, advanced: true, inEar: nil),
            make("B170", .headphones, anc: .full, presets: classic, custom: 5, advanced: true, bass: enhance5,
                 inEar: "Over-ear detection", ring: .single),
            make("B175", .headphones, anc: .full, eq: .listeningMode, presets: listeningNoDirac, custom: 6,
                 inEar: nil, ring: .single, hiddenDirac: 0),
            make("B179", .earbuds, anc: .full, eq: .listeningMode, presets: listening, custom: 6, bass: ultra5, earTip: true),
            make("B197", .earbuds, anc: .full, eq: .listeningMode, presets: listening, custom: 6, bass: ultra3, earTip: true),
            make("B184", .earbuds, anc: .full, eq: .listeningMode, presets: listeningNoDirac, custom: 6, bass: ultra5,
                 earTip: true, hiddenDirac: 0),
            make("B185", .earbuds, anc: .basic, eq: .listeningMode,
                 presets: [EQPresetOption(7, "Dirac")] + listeningNoDirac, custom: 6, bass: ultra5, inEar: nil),
            make("B173", .earbuds, anc: .full, presets: classic, custom: 5, advanced: true, bass: enhance5, earTip: true),
            make("B186", .headphones, anc: .full, presets: classic, custom: 5, advanced: true, bass: enhance3,
                 inEar: nil, ring: .single),
            make("B190", .earbuds, anc: .full, presets: classic, custom: 5, advanced: true, earTip: true),
            make("B189", .openEar, anc: .none, eq: .listeningMode,
                 presets: [EQPresetOption(3, "Pop"), .init(1, "Rock"), .init(2, "Electronic"), .init(5, "Classical"),
                           .init(4, "Vocals")],
                 custom: 6, bass: BassProfile(title: "Bass enhancement", threeStage: true), inEar: nil),
            make("B192", .headphones, anc: .full,
                 presets: [EQPresetOption(0, "Balanced"), .init(3, "More bass"), .init(2, "More treble"),
                           .init(1, "More vocals"), .init(7, "More detail")],
                 custom: 5, advanced: true, inEar: "Over-ear detection", ring: .single),
        ])
    }()
}
