import XCTest
@testable import ClaudeGauge

final class FableClientTests: XCTestCase {
    private func json(_ s: String) -> Data { Data(s.utf8) }

    private let full = """
    {"limits":[
      {"kind":"session","scope":null,"percent":12,"resets_at":"2026-11-16T16:29:59.973612+00:00"},
      {"kind":"weekly_all","scope":null,"percent":31,"resets_at":"2026-11-20T10:00:00+00:00"},
      {"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":0,"resets_at":"2026-11-22T23:00:00+00:00"}
    ]}
    """

    private func fableEntry(name: String = "Fable", percent: String = "0", resets: String = "\"2026-11-22T23:00:00+00:00\"") -> Data {
        json("""
        {"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"\(name)"}},"percent":\(percent),"resets_at":\(resets)}]}
        """)
    }

    func testParsesRealShapedPayload() {
        let expected = ISO8601DateFormatter().date(from: "2026-11-22T23:00:00Z")!
        XCTAssertEqual(FableParser.parse(json(full)),
                       .reading(FableReading(percent: 0, reset: expected)))
    }

    func testDisplayNameIsCaseInsensitive() {
        guard case .reading = FableParser.parse(fableEntry(name: "FABLE")) else { return XCTFail() }
    }

    func testPercentRoundsAndClamps() {
        guard case .reading(let r) = FableParser.parse(fableEntry(percent: "37.6")) else { return XCTFail() }
        XCTAssertEqual(r.percent, 38)
        guard case .reading(let high) = FableParser.parse(fableEntry(percent: "140")) else { return XCTFail() }
        XCTAssertEqual(high.percent, 100)
        guard case .reading(let low) = FableParser.parse(fableEntry(percent: "-5")) else { return XCTFail() }
        XCTAssertEqual(low.percent, 0)
    }

    func testNonNumericPercentIsInvalid() {
        XCTAssertEqual(FableParser.parse(fableEntry(percent: "\"x\"")), .invalid)
    }

    func testFractionalSecondsResetParses() {
        guard case .reading(let r) = FableParser.parse(fableEntry(resets: "\"2026-11-16T16:29:59.973612+00:00\"")) else { return XCTFail() }
        let whole = ISO8601DateFormatter().date(from: "2026-11-16T16:29:59Z")!
        XCTAssertNotNil(r.reset)
        XCTAssertEqual(r.reset!.timeIntervalSince(whole), 0.97, accuracy: 0.01)
    }

    func testBadResetGivesNilReset() {
        guard case .reading(let r) = FableParser.parse(fableEntry(resets: "\"soon\"")) else { return XCTFail() }
        XCTAssertNil(r.reset)
    }

    func testNoFableEntry() {
        let data = json(#"{"limits":[{"kind":"session","scope":null,"percent":1,"resets_at":null},{"kind":"weekly_scoped","scope":{"model":{"display_name":"Opus"}},"percent":2,"resets_at":null}]}"#)
        XCTAssertEqual(FableParser.parse(data), .noFable)
        XCTAssertEqual(FableParser.parse(json(#"{"limits":[]}"#)), .noFable)
    }

    func testInvalidPayloads() {
        XCTAssertEqual(FableParser.parse(json("not json")), .invalid)
        XCTAssertEqual(FableParser.parse(json(#"{"other":1}"#)), .invalid)
    }

    // MARK: Schedule

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let sample = FableReading(percent: 5, reset: nil)

    func testScheduleInitiallyDue() {
        XCTAssertTrue(FableSchedule().isDue(now: t0))
    }

    func testScheduleAfterReading() {
        var s = FableSchedule()
        s.record(.reading(sample), now: t0)
        XCTAssertFalse(s.isDue(now: t0.addingTimeInterval(299)))
        XCTAssertTrue(s.isDue(now: t0.addingTimeInterval(300)))
    }

    func testScheduleNoFableAndFailedWaitFiveMinutes() {
        for outcome in [FableFetchOutcome.noFable, .failed] {
            var s = FableSchedule()
            s.record(outcome, now: t0)
            XCTAssertFalse(s.isDue(now: t0.addingTimeInterval(299)))
            XCTAssertTrue(s.isDue(now: t0.addingTimeInterval(300)))
        }
    }

    func testRateLimitBackoffDoublesToCap() {
        var s = FableSchedule()
        for wait in [300.0, 600, 1200, 1800, 1800] {
            s.record(.rateLimited(retryAfter: nil), now: t0)
            XCTAssertFalse(s.isDue(now: t0.addingTimeInterval(wait - 1)), "wait \(wait)")
            XCTAssertTrue(s.isDue(now: t0.addingTimeInterval(wait)), "wait \(wait)")
        }
    }

    func testRetryAfterHonouredAndCapped() {
        var s = FableSchedule()
        s.record(.rateLimited(retryAfter: 120), now: t0)
        XCTAssertFalse(s.isDue(now: t0.addingTimeInterval(119)))
        XCTAssertTrue(s.isDue(now: t0.addingTimeInterval(120)))
        var c = FableSchedule()
        c.record(.rateLimited(retryAfter: 5000), now: t0)
        XCTAssertFalse(c.isDue(now: t0.addingTimeInterval(1799)))
        XCTAssertTrue(c.isDue(now: t0.addingTimeInterval(1800)))
    }

    func testReadingResetsBackoff() {
        var s = FableSchedule()
        s.record(.rateLimited(retryAfter: nil), now: t0)
        s.record(.rateLimited(retryAfter: nil), now: t0)
        s.record(.reading(sample), now: t0)
        XCTAssertEqual(s.backoff, 0)
        s.record(.rateLimited(retryAfter: nil), now: t0)
        XCTAssertTrue(s.isDue(now: t0.addingTimeInterval(300)))
    }

    // MARK: Store

    func testStoreRoundTrip() {
        let name = "fable-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FableStore(defaults: defaults)
        XCTAssertNil(store.load())
        let r = FableReading(percent: 42, reset: t0)
        store.save(r)
        XCTAssertEqual(store.load(), r)
        store.save(nil)
        XCTAssertNil(store.load())
    }
}
