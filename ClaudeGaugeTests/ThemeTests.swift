import XCTest
@testable import ClaudeGauge

final class ThemeTests: XCTestCase {
    func testThresholds() {
        XCTAssertEqual(Theme.color(forPercent: 0), Theme.green)
        XCTAssertEqual(Theme.color(forPercent: 49), Theme.green)
        XCTAssertEqual(Theme.color(forPercent: 50), Theme.amber)
        XCTAssertEqual(Theme.color(forPercent: 79), Theme.amber)
        XCTAssertEqual(Theme.color(forPercent: 80), Theme.red)
        XCTAssertEqual(Theme.color(forPercent: 100), Theme.red)
    }

    func testHexValues() {
        XCTAssertEqual(Theme.green.usingColorSpace(.sRGB)!.redComponent, 0x78 / 255, accuracy: 0.002)
        XCTAssertEqual(Theme.red.usingColorSpace(.sRGB)!.blueComponent, 0x2b / 255, accuracy: 0.002)
    }
}
