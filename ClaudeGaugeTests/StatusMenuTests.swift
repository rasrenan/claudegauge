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

    func testVersionTextComesFromTheAppBundle() {
        // Unit tests are hosted inside the app, so Bundle.main is ClaudeGauge.app.
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertNotNil(bundleVersion)
        XCTAssertEqual(StatusMenu.versionText(), "version \(bundleVersion!)")
    }

    func testVersionTextFollowsWhateverVersionItIsGiven() {
        XCTAssertEqual(StatusMenu.versionText("2.7"), "version 2.7")
        XCTAssertEqual(StatusMenu.versionText(nil), "version ?")
    }

    func testVersionRowForEachUpdateState() {
        let release = ReleaseInfo(version: SemVer(major: 0, minor: 2, patch: 0),
                                  dmgURL: URL(string: "https://example.com/a.dmg")!,
                                  pageURL: URL(string: "https://example.com/r")!)
        let unknown = StatusMenu.versionRow(version: "0.1.0", state: .unknown)
        XCTAssertEqual(unknown.text, "version 0.1.0")
        XCTAssertNil(unknown.button)
        let upToDate = StatusMenu.versionRow(version: "0.1.0", state: .upToDate)
        XCTAssertEqual(upToDate.text, "version 0.1.0 \u{00B7} updated")
        XCTAssertNil(upToDate.button)
        let available = StatusMenu.versionRow(version: "0.1.0", state: .available(release))
        XCTAssertEqual(available.text, "version 0.1.0")
        XCTAssertEqual(available.button, "Update now")
        let updating = StatusMenu.versionRow(version: "0.1.0", state: .updating)
        XCTAssertEqual(updating.text, "version 0.1.0 \u{00B7} updating\u{2026}")
        XCTAssertNil(updating.button)
    }

    func testAboutOpensProjectOnGitHub() {
        XCTAssertEqual(StatusMenu.projectURL.absoluteString, "https://github.com/rasrenan/claudegauge")
    }
}
