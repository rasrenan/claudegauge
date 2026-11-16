import Foundation

struct ReleaseInfo: Equatable {
    let version: SemVer
    let dmgURL: URL
    let pageURL: URL
}

enum ReleaseParser {
    static let assetName = "ClaudeGauge.dmg"

    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["draft"] as? Bool != true,
              root["prerelease"] as? Bool != true,
              let tag = root["tag_name"] as? String,
              let version = SemVer(tag),
              let page = root["html_url"] as? String,
              let pageURL = URL(string: page),
              let assets = root["assets"] as? [Any] else { return nil }

        for case let asset as [String: Any] in assets {
            guard asset["name"] as? String == assetName,
                  let link = asset["browser_download_url"] as? String,
                  let dmgURL = URL(string: link) else { continue }
            return ReleaseInfo(version: version, dmgURL: dmgURL, pageURL: pageURL)
        }
        return nil
    }
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case available(ReleaseInfo)
    case failed
}

struct UpdateChecker {
    static let defaultFeedURL = URL(string: "https://api.github.com/repos/rasrenan/claudegauge/releases/latest")!

    var feedURL: URL = UpdateChecker.resolvedFeedURL()
    var session: URLSession = .shared

    /// Pure decision used by `check`.
    static func decide(current: SemVer, release: ReleaseInfo?) -> UpdateCheckResult {
        guard let release else { return .failed }
        return release.version > current ? .available(release) : .upToDate
    }

    func check(current: SemVer) async -> UpdateCheckResult {
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("claudeGauge", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            switch status {
            case 200: return Self.decide(current: current, release: ReleaseParser.parse(data))
            case 404: return .upToDate
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// The `updateFeedURL` override exists only in Debug builds, to test updates locally.
    static func resolvedFeedURL(defaults: UserDefaults = .standard) -> URL {
        #if DEBUG
        if let value = defaults.string(forKey: "updateFeedURL"),
           let url = URL(string: value), url.scheme != nil {
            return url
        }
        #endif
        return defaultFeedURL
    }
}
