import AppKit
import CoreText
import SwiftUI

/// Nothing-style palette: near-black surfaces, white type, a single red accent used sparingly.
enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.035)
    static let surface = Color(red: 0.094, green: 0.098, blue: 0.106)
    static let track = Color(red: 0.165, green: 0.169, blue: 0.180)
    static let primary = Color.white
    static let secondary = Color(white: 0.56)
    static let tertiary = Color(white: 0.30)
    static let accent = Color(red: 0.843, green: 0.098, blue: 0.125)

    static let cardRadius: CGFloat = 20
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)
}

extension Font {
    /// Doto dot-matrix display face. Reserved for names, titles and the battery figure.
    static func doto(_ size: CGFloat) -> Font {
        .custom("Doto-Black_Bold", size: size)
    }

    /// Heaviest Doto instance; its larger dots stay legible at menu bar size.
    static func dotoHeavy(_ size: CGFloat) -> Font {
        .custom("Doto-Black", size: size)
    }
}

/// Fonts and images are copied into the app bundle by scripts/build-app.sh. When running the
/// bare binary (e.g. rendering previews), set NOM_RESOURCES to the repo's Resources folder.
enum AppResources {
    static func url(_ name: String, _ ext: String, in subdirectory: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        guard let root = ProcessInfo.processInfo.environment["NOM_RESOURCES"] else { return nil }
        let url = URL(fileURLWithPath: root).appending(path: "\(subdirectory)/\(name).\(ext)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func registerFonts() {
        guard let url = url("Doto", "ttf", in: "Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    @MainActor static func image(_ name: String) -> NSImage? {
        if let cached = imageCache[name] { return cached }
        let image = url(name, "png", in: "Images/Devices").flatMap(NSImage.init(contentsOf:))
        imageCache[name] = image
        return image
    }

    static func data(_ name: String) -> Data? {
        url(name, "json", in: "Data").flatMap { try? Data(contentsOf: $0) }
    }

    @MainActor private static var imageCache: [String: NSImage] = [:]
}
