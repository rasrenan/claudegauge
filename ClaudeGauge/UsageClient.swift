import Foundation

struct UsageReading: Equatable {
    let sessionPercent: Int
    let sessionReset: Date?
    let weeklyPercent: Int?
    let weeklyReset: Date?
}

enum FetchOutcome: Equatable {
    case reading(UsageReading)
    case notLoggedIn
    case offline
}

enum UsageParser {
    private static let prefix = "anthropic-ratelimit-unified-"

    static func parse(statusCode: Int, headers: [String: String]) -> FetchOutcome {
        if statusCode == 401 || statusCode == 403 { return .notLoggedIn }
        guard statusCode == 200 || statusCode == 429 else { return .offline }

        let h = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })

        if let session = percent(h[prefix + "5h-utilization"]) {
            return .reading(UsageReading(
                sessionPercent: session,
                sessionReset: date(h[prefix + "5h-reset"]),
                weeklyPercent: percent(h[prefix + "7d-utilization"]),
                weeklyReset: date(h[prefix + "7d-reset"])))
        }
        if let overage = percent(h[prefix + "overage-utilization"]) {
            return .reading(UsageReading(
                sessionPercent: overage,
                sessionReset: date(h[prefix + "overage-reset"]),
                weeklyPercent: nil,
                weeklyReset: nil))
        }
        return .offline
    }

    private static func percent(_ value: String?) -> Int? {
        guard let value, let util = Double(value), util.isFinite else { return nil }
        return min(100, max(0, Int((util * 100).rounded())))
    }

    private static func date(_ value: String?) -> Date? {
        guard let value, let secs = Double(value), secs.isFinite else { return nil }
        return Date(timeIntervalSince1970: secs)
    }
}

struct UsageClient {
    var session: URLSession = .shared

    func fetch(token: String) async -> FetchOutcome {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}"#.utf8)

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .offline }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers["\(key)"] = "\(value)"
            }
            return UsageParser.parse(statusCode: http.statusCode, headers: headers)
        } catch {
            return .offline
        }
    }
}
