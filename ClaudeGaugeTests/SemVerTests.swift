import XCTest
@testable import ClaudeGauge

final class SemVerTests: XCTestCase {
    func testAccepts() {
        XCTAssertEqual(SemVer("0.1.0"), SemVer(major: 0, minor: 1, patch: 0))
        XCTAssertEqual(SemVer("v0.1.0"), SemVer(major: 0, minor: 1, patch: 0))
        XCTAssertEqual(SemVer("V1.2.3"), SemVer(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemVer(" 2.0.10 "), SemVer(major: 2, minor: 0, patch: 10))
        XCTAssertEqual(SemVer("v0.1.0"), SemVer("0.1.0"))
    }

    func testRejects() {
        for bad in ["", "0.1", "1.2.3.4", "1.x.0", "-1.0.0", "1.2.3-beta", "v", "1..3", "01a.0.0"] {
            XCTAssertNil(SemVer(bad), "should reject \(bad)")
        }
    }

    func testDescriptionRoundTrip() {
        XCTAssertEqual(SemVer("v0.1.0")?.description, "0.1.0")
        XCTAssertEqual(SemVer(SemVer(major: 3, minor: 14, patch: 15).description), SemVer(major: 3, minor: 14, patch: 15))
    }

    func testOrdering() {
        XCTAssertGreaterThan(SemVer("0.10.0")!, SemVer("0.9.0")!)
        XCTAssertGreaterThan(SemVer("1.0.0")!, SemVer("0.99.99")!)
        XCTAssertGreaterThan(SemVer("0.1.1")!, SemVer("0.1.0")!)
        XCTAssertFalse(SemVer("0.1.0")! < SemVer("0.1.0")!)
    }
}
