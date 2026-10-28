import Foundation

/// One sellable variant (Fast Pair model ID / SKU) of a Nothing or CMF audio product.
/// Data comes from ear-web's control.js table, bundled as Resources/Data/catalog.json.
public struct DeviceSKU: Decodable, Equatable, Sendable {
    public let sku: String
    public let name: String
    /// Model base (e.g. "B175"), which decides protocol details and features.
    public let base: String
    public let colour: String
    public let images: Images

    public struct Images: Decodable, Equatable, Sendable {
        public let left: String
        public let right: String
        public let `case`: String
        public let duo: String

        public init(left: String, right: String, case: String, duo: String) {
            self.left = left
            self.right = right
            self.case = `case`
            self.duo = duo
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Bundled images are PNGs named after ear-web's .webp files.
            func name(_ key: CodingKeys) throws -> String {
                let file = try container.decode(String.self, forKey: key)
                return file.hasSuffix(".webp") ? String(file.dropLast(5)) : file
            }
            left = try name(.left)
            right = try name(.right)
            self.case = try name(.case)
            duo = try name(.duo)
        }

        private enum CodingKeys: String, CodingKey { case left, right, `case`, duo }
    }

    public init(sku: String, name: String, base: String, colour: String, images: Images) {
        self.sku = sku
        self.name = name
        self.base = base
        self.colour = colour
        self.images = images
    }
}

public struct DeviceCatalog: Sendable {
    public let skus: [DeviceSKU]

    public init(json: Data) throws {
        skus = try JSONDecoder().decode([DeviceSKU].self, from: json)
    }

    public func model(sku: String) -> DeviceSKU? {
        skus.first { $0.sku.caseInsensitiveCompare(sku) == .orderedSame }
    }

    /// Best guess from a Bluetooth name when the Fast Pair ID isn't available.
    public func model(bluetoothName: String) -> DeviceSKU? {
        let name = bluetoothName.lowercased()
        return skus
            .filter { name.contains($0.name.lowercased()) }
            .max { $0.name.count < $1.name.count }
    }
}

public enum FastPair {
    /// The model ID is bytes 4–6 of the 7-byte message sent on the Fast Pair channel.
    public static func sku(fromMessage bytes: [UInt8]) -> String? {
        guard bytes.count >= 7 else { return nil }
        return bytes[4...6].map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16, uppercase: true) }.joined()
    }
}
