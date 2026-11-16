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
        XCTAssertEqual(GaugeIcon.label(for: .starting), "--")
        XCTAssertEqual(GaugeIcon.label(for: ok(47)), "47%")
        XCTAssertEqual(GaugeIcon.label(for: ok(100)), "100%")
        XCTAssertEqual(GaugeIcon.label(for: .notLoggedIn), "⚠")
        XCTAssertEqual(GaugeIcon.label(for: offline(47)), "47%")
        XCTAssertEqual(GaugeIcon.label(for: offline(nil)), "--")
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
