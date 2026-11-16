import XCTest
@testable import ClaudeGauge

final class GaugeIconTests: XCTestCase {
    private func reading(_ percent: Int) -> UsageReading {
        UsageReading(sessionPercent: percent, sessionReset: nil, weeklyPercent: nil, weeklyReset: nil)
    }
    private func ok(_ percent: Int) -> GaugeState {
        .ok(reading(percent), updated: Date(timeIntervalSince1970: 0))
    }
    private func offline(_ percent: Int?) -> GaugeState {
        .offline(last: percent.map(reading), lastUpdate: nil)
    }

    func testLabels() {
        XCTAssertEqual(GaugeIcon.label(for: .starting), "Claude usage: checking…")
        XCTAssertEqual(GaugeIcon.label(for: ok(47)), "Claude session usage: 47%")
        XCTAssertEqual(GaugeIcon.label(for: ok(100)), "Claude session usage: 100%")
        XCTAssertEqual(GaugeIcon.label(for: .notLoggedIn), "Claude usage: not logged in")
        XCTAssertEqual(GaugeIcon.label(for: offline(47)), "Claude usage: offline (last 47%)")
        XCTAssertEqual(GaugeIcon.label(for: offline(nil)), "Claude usage: offline")
    }

    func testTicksAtQuarters() {
        XCTAssertEqual(GaugeIcon.tickPercents, [25, 50, 75])
        XCTAssertEqual(GaugeIcon.size, NSSize(width: 24, height: 18))
    }

    func testNeedleSweepsClockwiseFromFlatLeftToFlatRight() {
        XCTAssertEqual(GaugeIcon.needleAngle(forPercent: 0), .pi, accuracy: 1e-9)
        XCTAssertEqual(GaugeIcon.needleAngle(forPercent: 50), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(GaugeIcon.needleAngle(forPercent: 100), 0, accuracy: 1e-9)
        XCTAssertEqual(GaugeIcon.needleAngle(forPercent: 25), 3 * .pi / 4, accuracy: 1e-9)
        // Out-of-range values are clamped.
        XCTAssertEqual(GaugeIcon.needleAngle(forPercent: -5), .pi, accuracy: 1e-9)
        XCTAssertEqual(GaugeIcon.needleAngle(forPercent: 130), 0, accuracy: 1e-9)
    }

    func testFillColors() {
        XCTAssertEqual(GaugeIcon.fillColor(for: ok(47)), Theme.green)
        XCTAssertEqual(GaugeIcon.fillColor(for: ok(83)), Theme.red)
        XCTAssertEqual(GaugeIcon.fillColor(for: offline(47)), NSColor.secondaryLabelColor)
        XCTAssertNil(GaugeIcon.fillColor(for: .starting))
        XCTAssertNil(GaugeIcon.fillColor(for: .notLoggedIn))
    }

    func testImagesHaveExpectedSizeAndAreNotTemplates() {
        let states: [GaugeState] = [.starting, ok(47), ok(100), .notLoggedIn, offline(47), offline(nil)]
        for state in states {
            let image = GaugeIcon.image(for: state)
            XCTAssertEqual(image.size, GaugeIcon.size)
            XCTAssertFalse(image.isTemplate)
            // Forces the drawing handler to run.
            XCTAssertNotNil(image.tiffRepresentation)
        }
    }
}
