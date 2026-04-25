import Foundation

protocol UpdateService {
    func fetchLatestRelease() async -> UpdateInfo?
    func isNewer(_ remote: String) -> Bool
}

final class UpdateServiceImpl: UpdateService {
    private let atomURL = URL(string: "https://github.com/awsl1414/InputLock/releases.atom")!

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func fetchLatestRelease() async -> UpdateInfo? {
        var request = URLRequest(url: atomURL)
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        return parseAtom(data)
    }

    func isNewer(_ remote: String) -> Bool {
        compareVersions(remote, currentVersion) == .orderedDescending
    }

    // MARK: - Private

    private func parseAtom(_ data: Data) -> UpdateInfo? {
        let doc = try? XMLDocument(data: data, options: [])
        guard let entries = try? doc?.nodes(forXPath: "//entry") as? [XMLElement],
              let first = entries.first else { return nil }

        let link = ((try? first.nodes(forXPath: "link")) ?? [])
            .compactMap { node -> String? in
                guard let el = node as? XMLElement else { return nil }
                return el.attribute(forName: "href")?.stringValue
            }
            .first
        let href = link ?? "https://github.com/awsl1414/InputLock/releases"
        let version = href.components(separatedBy: "/tag/").last ?? ""

        let content = (try? first.nodes(forXPath: "content"))?.first?.stringValue ?? ""

        guard !version.isEmpty, let url = URL(string: href) else { return nil }

        return UpdateInfo(version: version, releaseNotes: content, releaseURL: url)
    }

    private func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let count = max(aParts.count, bParts.count)

        for i in 0..<count {
            let ai = i < aParts.count ? aParts[i] : 0
            let bi = i < bParts.count ? bParts[i] : 0
            if ai > bi { return .orderedDescending }
            if ai < bi { return .orderedAscending }
        }
        return .orderedSame
    }
}
