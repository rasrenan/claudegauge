import Foundation

struct FableReading: Equatable, Codable {
    let percent: Int
    let reset: Date?
}

enum FableParseResult: Equatable {
    case reading(FableReading)
    case noFable
    case invalid
}

enum FableParser {
    static func parse(_ data: Data) -> FableParseResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let limits = root["limits"] as? [Any] else { return .invalid }

        for case let entry as [String: Any] in limits {
            guard entry["kind"] as? String == "weekly_scoped",
                  let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String,
                  name.lowercased() == "fable" else { continue }

            guard let number = entry["percent"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else { return .invalid }
            let percent = min(100, max(0, Int(number.doubleValue.rounded())))
            return .reading(FableReading(percent: percent, reset: date(entry["resets_at"] as? String)))
        }
        return .noFable
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: value) ?? fractional.date(from: value)
    }
}

enum FableFetchOutcome: Equatable {
    case reading(FableReading)
    case noFable
    case rateLimited(retryAfter: TimeInterval?)
    case failed
}

struct FableClient {
    var session: URLSession = .shared

    func fetch(token: String) async -> FableFetchOutcome {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            switch http.statusCode {
            case 200:
                switch FableParser.parse(data) {
                case .reading(let reading): return .reading(reading)
                case .noFable: return .noFable
                case .invalid: return .failed
                }
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
                return .rateLimited(retryAfter: retry)
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}

struct FableSchedule: Equatable {
    static let interval: TimeInterval = 300
    static let backoffStart: TimeInterval = 300
    static let backoffCap: TimeInterval = 1800

    private(set) var nextFetch: Date = .distantPast
    private(set) var backoff: TimeInterval = 0

    func isDue(now: Date) -> Bool { now >= nextFetch }

    mutating func record(_ outcome: FableFetchOutcome, now: Date) {
        switch outcome {
        case .reading, .noFable, .failed:
            backoff = 0
            nextFetch = now.addingTimeInterval(Self.interval)
        case .rateLimited(let retryAfter):
            backoff = backoff == 0 ? Self.backoffStart : min(backoff * 2, Self.backoffCap)
            var wait = backoff
            if let retryAfter, retryAfter > 0 { wait = retryAfter }
            nextFetch = now.addingTimeInterval(min(wait, Self.backoffCap))
        }
    }
}

struct FableStore {
    static let key = "fableReading"
    var defaults: UserDefaults = .standard

    func load() -> FableReading? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(FableReading.self, from: data)
    }

    func save(_ reading: FableReading?) {
        if let reading, let data = try? JSONEncoder().encode(reading) {
            defaults.set(data, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
