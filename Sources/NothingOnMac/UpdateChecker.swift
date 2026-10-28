import Foundation
import Observation
import os

/// Checks GitHub Releases once a day for a newer version. Nothing is downloaded or installed
/// automatically; the menu shows a link to the release page.
@MainActor @Observable
final class UpdateChecker {
    struct Release: Equatable {
        let version: String
        let page: URL
    }

    private(set) var available: Release?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.mdanishharoon.NothingOnMac", category: "updates")
    private static let latestRelease = URL(string: "https://api.github.com/repos/mdanishharoon/nothing-on-mac/releases/latest")!

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    private func check() async {
        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let body = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let version = body.tagName.hasPrefix("v") ? String(body.tagName.dropFirst()) : body.tagName
            if Self.isNewer(version, than: AppInfo.version), let page = URL(string: body.htmlURL) {
                available = Release(version: version, page: page)
            }
        } catch {
            log.info("update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Numeric dotted comparison; anything unparsable counts as not newer.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) }
        let b = current.split(separator: ".").map { Int($0) }
        guard !a.contains(nil), !b.contains(nil) else { return false }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index]! : 0
            let right = index < b.count ? b[index]! : 0
            if left != right { return left > right }
        }
        return false
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
