import XCTest
@testable import ClaudeGauge

final class UsageParserTests: XCTestCase {
    private let fullHeaders: [String: String] = [
        "anthropic-ratelimit-unified-5h-utilization": "0.47",
        "anthropic-ratelimit-unified-5h-reset": "1800000000",
        "anthropic-ratelimit-unified-7d-utilization": "0.312",
        "anthropic-ratelimit-unified-7d-reset": "1800100000",
    ]
    private let fullReading = UsageReading(
        sessionPercent: 47,
        sessionReset: Date(timeIntervalSince1970: 1_800_000_000),
        weeklyPercent: 31,
        weeklyReset: Date(timeIntervalSince1970: 1_800_100_000))

    func testOkWithAllHeaders() {
        XCTAssertEqual(UsageParser.parse(statusCode: 200, headers: fullHeaders), .reading(fullReading))
    }

    func test429WithHeadersIsAReading() {
        XCTAssertEqual(UsageParser.parse(statusCode: 429, headers: fullHeaders), .reading(fullReading))
    }

    func test429WithoutHeadersIsOffline() {
        XCTAssertEqual(UsageParser.parse(statusCode: 429, headers: [:]), .offline)
    }

    func testAuthFailuresAreNotLoggedIn() {
        XCTAssertEqual(UsageParser.parse(statusCode: 401, headers: [:]), .notLoggedIn)
        XCTAssertEqual(UsageParser.parse(statusCode: 403, headers: [:]), .notLoggedIn)
    }

    func testServerErrorsAreOffline() {
        XCTAssertEqual(UsageParser.parse(statusCode: 500, headers: [:]), .offline)
        XCTAssertEqual(UsageParser.parse(statusCode: 529, headers: [:]), .offline)
    }

    func testOverageFallbackHidesWeekly() {
        let headers = [
            "anthropic-ratelimit-unified-overage-utilization": "0.2",
            "anthropic-ratelimit-unified-overage-reset": "1800000000",
        ]
        XCTAssertEqual(UsageParser.parse(statusCode: 200, headers: headers),
                       .reading(UsageReading(sessionPercent: 20,
                                             sessionReset: Date(timeIntervalSince1970: 1_800_000_000),
                                             weeklyPercent: nil, weeklyReset: nil)))
    }

    func testPercentIsClamped() {
        var high = fullHeaders
        high["anthropic-ratelimit-unified-5h-utilization"] = "1.37"
        guard case .reading(let r1) = UsageParser.parse(statusCode: 200, headers: high) else { return XCTFail() }
        XCTAssertEqual(r1.sessionPercent, 100)

        var low = fullHeaders
        low["anthropic-ratelimit-unified-5h-utilization"] = "-0.1"
        guard case .reading(let r2) = UsageParser.parse(statusCode: 200, headers: low) else { return XCTFail() }
        XCTAssertEqual(r2.sessionPercent, 0)
    }

    func testUnparsableSessionUtilizationIsOffline() {
        var headers = fullHeaders
        headers["anthropic-ratelimit-unified-5h-utilization"] = "abc"
        XCTAssertEqual(UsageParser.parse(statusCode: 200, headers: headers), .offline)
    }

    func testUnparsableWeeklyUtilizationIsNil() {
        var headers = fullHeaders
        headers["anthropic-ratelimit-unified-7d-utilization"] = "abc"
        guard case .reading(let r) = UsageParser.parse(statusCode: 200, headers: headers) else { return XCTFail() }
        XCTAssertEqual(r.sessionPercent, 47)
        XCTAssertNil(r.weeklyPercent)
    }

    func testUnparsableResetIsNil() {
        var headers = fullHeaders
        headers["anthropic-ratelimit-unified-5h-reset"] = "soon"
        guard case .reading(let r) = UsageParser.parse(statusCode: 200, headers: headers) else { return XCTFail() }
        XCTAssertNil(r.sessionReset)
    }

    func testHeaderKeysAreCaseInsensitive() {
        let headers = ["Anthropic-RateLimit-Unified-5h-Utilization": "0.47"]
        guard case .reading(let r) = UsageParser.parse(statusCode: 200, headers: headers) else { return XCTFail() }
        XCTAssertEqual(r.sessionPercent, 47)
    }
}
