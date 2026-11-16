import XCTest
@testable import ClaudeGauge

final class TokenReaderTests: XCTestCase {
    private let nested = #"{"claudeAiOauth":{"accessToken":"abc","expiresAt":1800000000000}}"#
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func hex(_ s: String) -> String {
        s.utf8.map { String(format: "%02x", $0) }.joined()
    }

    private func status(expiresAtMs: Int?) -> TokenStatus {
        let exp = expiresAtMs.map { #","expiresAt":\#($0)"# } ?? ""
        let json = #"{"claudeAiOauth":{"accessToken":"abc"\#(exp)}}"#
        return TokenReader(readRaw: { json }).status(now: now)
    }

    func testFlat() {
        XCTAssertEqual(CredentialsDecoder.decode(#"{"accessToken":"abc"}"#),
                       Credentials(token: "abc", expiresAt: nil))
    }

    func testNestedConvertsMillisecondsToSeconds() {
        XCTAssertEqual(CredentialsDecoder.decode(nested),
                       Credentials(token: "abc", expiresAt: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func testHexEncoded() {
        XCTAssertEqual(CredentialsDecoder.decode(hex(nested)),
                       Credentials(token: "abc", expiresAt: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func testSurroundingWhitespace() {
        let expected = Credentials(token: "abc", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(CredentialsDecoder.decode("\n  " + nested + "\n"), expected)
        XCTAssertEqual(CredentialsDecoder.decode(hex(nested) + "\n"), expected)
    }

    func testInvalidInputs() {
        XCTAssertNil(CredentialsDecoder.decode("not json"))
        XCTAssertNil(CredentialsDecoder.decode(""))
        XCTAssertNil(CredentialsDecoder.decode(#"{"claudeAiOauth":{}}"#))
        XCTAssertNil(CredentialsDecoder.decode(#"{"accessToken":""}"#))
    }

    func testMissingWhenReadFails() {
        XCTAssertEqual(TokenReader(readRaw: { nil }).status(now: now), .missing)
    }

    func testMissingWhenUndecodable() {
        XCTAssertEqual(TokenReader(readRaw: { "garbage" }).status(now: now), .missing)
    }

    func testExpired() {
        XCTAssertEqual(status(expiresAtMs: 1_800_000_000_000 - 1000), .expired)
    }

    func testValidWhenExpiryInFuture() {
        XCTAssertEqual(status(expiresAtMs: 1_800_000_000_000 + 3_600_000), .valid("abc"))
    }

    func testValidWithoutExpiry() {
        XCTAssertEqual(status(expiresAtMs: nil), .valid("abc"))
    }
}
