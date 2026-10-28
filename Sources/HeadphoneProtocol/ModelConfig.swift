import Foundation

/// Loosely-typed JSON, for config entries whose keys vary by model.
public enum JSONValue: Decodable, Equatable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public var double: Double? {
        switch self {
        case .number(let value): value
        case .bool(let value): value ? 1 : 0
        case .string(let value): Double(value)
        default: nil
        }
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// The firmware-matched entry of ear_config_file.json for one model base (`modelSpecs` in ear-web).
public struct ModelConfig: Equatable, Sendable {
    public let values: [String: JSONValue]

    public init(values: [String: JSONValue]) {
        self.values = values
    }

    public func int(_ key: String) -> Int? {
        values[key]?.double.map { Int($0) }
    }

    /// True when the key is present and non-zero.
    public func flag(_ key: String) -> Bool {
        (values[key]?.double ?? 0) != 0
    }

    public func double(_ key: String) -> Double? {
        values[key]?.double
    }

    /// `customEQ` frequencies and Q factors for the three custom bands.
    public var customEQBands: CustomEQBands? {
        guard case .object(let eq)? = values["customEQ"],
              let freqLow = eq["freqLow"]?.double, let qLow = eq["qLow"]?.double,
              let freqPeak = eq["freqPeak"]?.double, let qPeak = eq["qPeak"]?.double,
              let freqHigh = eq["freqHigh"]?.double, let qHigh = eq["qHigh"]?.double else { return nil }
        return CustomEQBands(
            low: (Float(freqLow), Float(qLow)),
            peak: (Float(freqPeak), Float(qPeak)),
            high: (Float(freqHigh), Float(qHigh))
        )
    }
}

/// All model entries from ear_config_file.json (bundled as Resources/Data/ear_config.json).
public struct ModelConfigTable: Sendable {
    private struct Entry: Decodable {
        let id: String
        let configs: [[String: JSONValue]]
    }

    private let entries: [String: [[String: JSONValue]]]

    public init(json: Data) throws {
        let decoded = try JSONDecoder().decode([Entry].self, from: json)
        entries = Dictionary(decoded.map { ($0.id, $0.configs) }, uniquingKeysWith: { first, _ in first })
    }

    /// ear-web's getConfigForFirmware: a single config applies regardless of firmware; otherwise the
    /// first config whose inclusive min/max firmware range contains `firmware` wins.
    public func config(base: String, firmware: String) -> ModelConfig? {
        guard let configs = entries[base], !configs.isEmpty else { return nil }
        if configs.count == 1 { return ModelConfig(values: configs[0]) }
        let match = configs.first {
            FirmwareVersion.isIn(firmware, min: $0["minFirmware"]?.string, max: $0["maxFirmware"]?.string)
        }
        return match.map(ModelConfig.init(values:))
    }
}

/// Port of ear-web's versionUtils.js comparison rules.
public enum FirmwareVersion {
    /// Inclusive range check. Missing bounds are open; `*` components are skipped; a `-suffix` is ignored.
    public static func isIn(_ version: String, min: String?, max: String?) -> Bool {
        if let min, !min.isEmpty {
            guard let order = compare(version, min), order >= 0 else { return false }
        }
        if let max, !max.isEmpty {
            guard let order = compare(version, max), order <= 0 else { return false }
        }
        return true
    }

    /// -1, 0 or 1; nil when a compared component isn't numeric.
    static func compare(_ a: String, _ b: String) -> Int? {
        func parts(_ version: String) -> [Substring] {
            (version.split(separator: "-", maxSplits: 1).first ?? "").split(separator: ".", omittingEmptySubsequences: false)
        }
        let left = parts(a), right = parts(b)
        for index in 0..<Swift.max(left.count, right.count) {
            let l = index < left.count ? left[index] : "0"
            let r = index < right.count ? right[index] : "0"
            if l == "*" || r == "*" { continue }
            guard let lv = Int(l), let rv = Int(r) else { return nil }
            if lv != rv { return lv < rv ? -1 : 1 }
        }
        return 0
    }
}
