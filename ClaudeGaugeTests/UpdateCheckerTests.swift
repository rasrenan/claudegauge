import XCTest
@testable import ClaudeGauge

final class UpdateCheckerTests: XCTestCase {
    private func release(tag: String = "v0.2.0", draft: Bool = false, prerelease: Bool = false,
                         assetName: String = "ClaudeGauge.dmg") -> Data {
        Data("""
        {"url":"https://api.github.com/repos/rasrenan/claudegauge/releases/1","id":1,
         "tag_name":"\(tag)","name":"Release","draft":\(draft),"prerelease":\(prerelease),
         "html_url":"https://github.com/rasrenan/claudegauge/releases/tag/\(tag)",
         "author":{"login":"rasrenan"},
         "assets":[
           {"name":"ClaudeGauge.dmg.sha256","size":10,"browser_download_url":"https://github.com/rasrenan/claudegauge/releases/download/\(tag)/ClaudeGauge.dmg.sha256"},
           {"name":"\(assetName)","size":1000,"browser_download_url":"https://github.com/rasrenan/claudegauge/releases/download/\(tag)/ClaudeGauge.dmg"}
         ],"body":"notes"}
        """.utf8)
    }

    private func info(_ v: String) -> ReleaseInfo {
        ReleaseInfo(version: SemVer(v)!,
                    dmgURL: URL(string: "https://example.com/ClaudeGauge.dmg")!,
                    pageURL: URL(string: "https://example.com/r")!)
    }

    func testParsesRelease() {
        let r = ReleaseParser.parse(release())
        XCTAssertEqual(r?.version, SemVer("0.2.0"))
        XCTAssertEqual(r?.dmgURL, URL(string: "https://github.com/rasrenan/claudegauge/releases/download/v0.2.0/ClaudeGauge.dmg"))
        XCTAssertEqual(r?.pageURL, URL(string: "https://github.com/rasrenan/claudegauge/releases/tag/v0.2.0"))
    }

    func testParserRejects() {
        XCTAssertNil(ReleaseParser.parse(release(draft: true)))
        XCTAssertNil(ReleaseParser.parse(release(prerelease: true)))
        XCTAssertNil(ReleaseParser.parse(release(assetName: "Other.zip")))
        XCTAssertNil(ReleaseParser.parse(release(tag: "latest")))
        XCTAssertNil(ReleaseParser.parse(Data("not json".utf8)))
    }

    func testDecide() {
        let current = SemVer("0.1.0")!
        XCTAssertEqual(UpdateChecker.decide(current: current, release: nil), .failed)
        XCTAssertEqual(UpdateChecker.decide(current: current, release: info("0.2.0")), .available(info("0.2.0")))
        XCTAssertEqual(UpdateChecker.decide(current: current, release: info("0.1.0")), .upToDate)
        XCTAssertEqual(UpdateChecker.decide(current: current, release: info("0.0.9")), .upToDate)
    }

    private func tempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testCheckWithFileFeed() async throws {
        let newer = try tempFile(release(tag: "v0.2.0"))
        let same = try tempFile(release(tag: "v0.1.0"))
        let current = SemVer("0.1.0")!
        let result = await UpdateChecker(feedURL: newer).check(current: current)
        guard case .available(let r) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(r.version, SemVer("0.2.0"))
        let upToDate = await UpdateChecker(feedURL: same).check(current: current)
        XCTAssertEqual(upToDate, .upToDate)
    }

    func testCheckMissingFileFails() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = await UpdateChecker(feedURL: missing).check(current: SemVer("0.1.0")!)
        XCTAssertEqual(result, .failed)
    }

    func testResolvedFeedURL() {
        let name = "UpdateCheckerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(UpdateChecker.resolvedFeedURL(defaults: defaults), UpdateChecker.defaultFeedURL)
        defaults.set("file:///tmp/x.json", forKey: "updateFeedURL")
        XCTAssertEqual(UpdateChecker.resolvedFeedURL(defaults: defaults), URL(string: "file:///tmp/x.json"))
    }
}
