import XCTest
@testable import ClaudeGauge

@MainActor
final class StatusMenuTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading() -> UsageReading {
        UsageReading(sessionPercent: 47, sessionReset: now.addingTimeInterval(3600),
                     weeklyPercent: 31, weeklyReset: now.addingTimeInterval(7200))
    }

    func testOkWithFableAddsThirdLine() {
        let reset = now.addingTimeInterval(1800)
        let lines = StatusMenu.statusLines(for: .ok(reading(), updated: now),
                                           fable: FableReading(percent: 0, reset: reset), now: now)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[2], "Fable: 0%  ·  \(ResetFormatter.text(until: reset, now: now))")
        XCTAssertEqual(lines[2], "Fable: 0%  ·  resets in 30m")
    }

    func testOkWithoutFableHasTwoLines() {
        let lines = StatusMenu.statusLines(for: .ok(reading(), updated: now), fable: nil, now: now)
        XCTAssertEqual(lines.count, 2)
    }

    func testPastResetSaysResetsNow() {
        let lines = StatusMenu.statusLines(for: .ok(reading(), updated: now),
                                           fable: FableReading(percent: 80, reset: now.addingTimeInterval(-10)), now: now)
        XCTAssertEqual(lines.last, "Fable: 0%  ·  resets now")
    }

    func testNilResetOmitsSuffix() {
        let lines = StatusMenu.statusLines(for: .ok(reading(), updated: now),
                                           fable: FableReading(percent: 12, reset: nil), now: now)
        XCTAssertEqual(lines.last, "Fable: 12%")
    }

    func testOfflineWithLastShowsFable() {
        let lines = StatusMenu.statusLines(for: .offline(last: reading(), lastUpdate: now),
                                           fable: FableReading(percent: 3, reset: nil), now: now)
        XCTAssertEqual(lines.last, "Fable: 3%")
    }

    func testOfflineWithoutLastHasNoFable() {
        let lines = StatusMenu.statusLines(for: .offline(last: nil, lastUpdate: nil),
                                           fable: FableReading(percent: 3, reset: nil), now: now)
        XCTAssertEqual(lines, ["Offline"])
    }

    func testNotLoggedInAndStartingHaveNoFable() {
        let f = FableReading(percent: 3, reset: nil)
        XCTAssertEqual(StatusMenu.statusLines(for: .notLoggedIn, fable: f, now: now), ["Not logged in"])
        XCTAssertEqual(StatusMenu.statusLines(for: .starting, fable: f, now: now), ["Checking usage…"])
    }

    func testAboutOpensProjectOnGitHub() {
        XCTAssertEqual(StatusMenu.projectURL.absoluteString, "https://github.com/rasrenan/claudegauge")
    }
}
