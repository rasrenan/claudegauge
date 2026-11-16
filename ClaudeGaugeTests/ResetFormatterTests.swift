import XCTest
@testable import ClaudeGauge

final class ResetFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let locale = Locale(identifier: "en_US_POSIX")
    private let zone = TimeZone(identifier: "UTC")!

    private func text(_ offset: TimeInterval) -> String {
        ResetFormatter.text(until: now.addingTimeInterval(offset), now: now, locale: locale, timeZone: zone)
    }

    func testMinutesOnly() { XCTAssertEqual(text(42 * 60), "resets in 42m") }
    func testPartialMinuteRoundsUp() { XCTAssertEqual(text(30), "resets in 1m") }
    func testHoursAndMinutes() { XCTAssertEqual(text(2 * 3600 + 13 * 60), "resets in 2h 13m") }
    func testWholeHours() { XCTAssertEqual(text(3 * 3600), "resets in 3h 0m") }

    func testDaysAwayUsesWeekdayAndTime() {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("EEE j:mm")
        let reset = now.addingTimeInterval(3 * 86400)
        XCTAssertEqual(text(3 * 86400), "resets " + f.string(from: reset))
    }

    func testPastAndNowReadResetsNow() {
        XCTAssertEqual(text(-60), "resets now")
        XCTAssertEqual(text(0), "resets now")
    }
}
