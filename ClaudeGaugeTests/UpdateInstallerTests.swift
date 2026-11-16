import XCTest
@testable import ClaudeGauge

private final class FakeTools: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(tool: String, args: [String])] = []
    var bundleID = "io.github.rasrenan.claudegauge"
    var version = "0.2.0"
    var attachStatus: Int32 = 0
    var codesignStatus: Int32 = 0

    var calls: [(tool: String, args: [String])] {
        lock.withLock { _calls }
    }

    private func record(_ tool: String, _ args: [String]) {
        lock.withLock { _calls.append((tool, args)) }
    }

    var runner: CommandRunner {
        CommandRunner(run: { [self] tool, args in
            record(tool, args)
            switch (tool, args.first) {
            case ("/usr/bin/hdiutil", "attach"):
                if attachStatus != 0 { return (attachStatus, "") }
                let mount = URL(fileURLWithPath: args[args.firstIndex(of: "-mountpoint")! + 1])
                let app = mount.appendingPathComponent("claudeGauge.app")
                let contents = app.appendingPathComponent("Contents")
                try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
                let plist: [String: Any] = ["CFBundleIdentifier": bundleID,
                                            "CFBundleShortVersionString": version]
                (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
                try? "new".write(to: app.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
                return (0, "")
            case ("/usr/bin/codesign", _):
                return (codesignStatus, "")
            case ("/usr/bin/ditto", _):
                do {
                    try FileManager.default.copyItem(atPath: args[0], toPath: args[1])
                    return (0, "")
                } catch { return (1, "\(error)") }
            default:
                return (0, "")
            }
        })
    }
}

@MainActor
final class UpdateInstallerTests: XCTestCase {
    private var sandbox: URL!
    private var appURL: URL!
    private var dmgURL: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = fm.temporaryDirectory.appendingPathComponent("installer-test-\(UUID().uuidString)")
        let apps = sandbox.appendingPathComponent("Applications")
        appURL = apps.appendingPathComponent("ClaudeGauge.app")
        let contents = appURL.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": UpdateInstaller.bundleID,
                                    "CFBundleShortVersionString": "0.1.0"]
        (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        try "old".write(to: appURL.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
        dmgURL = sandbox.appendingPathComponent("fake.dmg")
        try Data("not a real dmg".utf8).write(to: dmgURL)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    private func release(dmg: URL? = nil) -> ReleaseInfo {
        ReleaseInfo(version: SemVer("0.2.0")!, dmgURL: dmg ?? dmgURL,
                    pageURL: URL(string: "https://example.com/r")!)
    }

    private func makeInstaller(_ tools: FakeTools, relaunch: @escaping (URL) -> Void = { _ in }) -> UpdateInstaller {
        UpdateInstaller(appURL: appURL, runner: tools.runner, relaunch: relaunch)
    }

    private func assertUntouched(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(fm.fileExists(atPath: appURL.appendingPathComponent("old.txt").path), file: file, line: line)
        XCTAssertFalse(fm.fileExists(atPath: appURL.appendingPathComponent("new.txt").path), file: file, line: line)
    }

    private func assertInstallFails(_ tools: FakeTools, _ expected: UpdateError,
                                    file: StaticString = #filePath, line: UInt = #line) async {
        var relaunched = 0
        let installer = makeInstaller(tools) { _ in relaunched += 1 }
        do {
            try await installer.install(release())
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? UpdateError, expected, file: file, line: line)
        }
        XCTAssertEqual(relaunched, 0, file: file, line: line)
        assertUntouched(file: file, line: line)
    }

    func testSuccessReplacesAppAndCleansUp() async throws {
        let tools = FakeTools()
        var relaunched: [URL] = []
        let installer = makeInstaller(tools) { relaunched.append($0) }
        try await installer.install(release())

        XCTAssertTrue(fm.fileExists(atPath: appURL.appendingPathComponent("new.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: appURL.appendingPathComponent("old.txt").path))
        XCTAssertEqual(relaunched, [appURL])
        XCTAssertFalse(fm.fileExists(atPath: appURL.deletingLastPathComponent()
            .appendingPathComponent(".claudeGauge-update.app").path))
        XCTAssertTrue(tools.calls.contains { $0.tool == "/usr/bin/hdiutil" && $0.args.first == "detach" })

        let attach = try XCTUnwrap(tools.calls.first { $0.args.first == "attach" })
        let mount = attach.args[attach.args.firstIndex(of: "-mountpoint")! + 1]
        let tmp = URL(fileURLWithPath: mount).deletingLastPathComponent()
        XCTAssertTrue(tmp.lastPathComponent.hasPrefix("claudeGauge-update-"))
        XCTAssertFalse(fm.fileExists(atPath: tmp.path))
    }

    func testWrongBundleID() async {
        let tools = FakeTools()
        tools.bundleID = "com.example.other"
        await assertInstallFails(tools, .wrongBundle)
        XCTAssertTrue(tools.calls.contains { $0.tool == "/usr/bin/hdiutil" && $0.args.first == "detach" })
    }

    func testVersionMismatch() async {
        let tools = FakeTools()
        tools.version = "0.1.5"
        await assertInstallFails(tools, .versionMismatch)
    }

    func testInvalidSignature() async {
        let tools = FakeTools()
        tools.codesignStatus = 1
        await assertInstallFails(tools, .signatureInvalid)
    }

    func testMountFailure() async {
        let tools = FakeTools()
        tools.attachStatus = 1
        await assertInstallFails(tools, .mountFailed)
    }

    func testDownloadFailure() async {
        let tools = FakeTools()
        var relaunched = 0
        let installer = makeInstaller(tools) { _ in relaunched += 1 }
        do {
            try await installer.install(release(dmg: sandbox.appendingPathComponent("missing.dmg")))
            XCTFail("expected downloadFailed")
        } catch {
            XCTAssertEqual(error as? UpdateError, .downloadFailed)
        }
        XCTAssertEqual(relaunched, 0)
        assertUntouched()
    }

    func testCanReplace() {
        XCTAssertTrue(UpdateInstaller.canReplace(appURL: URL(fileURLWithPath: "/Applications/ClaudeGauge.app"),
                                                 isWritable: { _ in true }))
        XCTAssertFalse(UpdateInstaller.canReplace(
            appURL: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/ClaudeGauge.app"),
            isWritable: { _ in true }))
        XCTAssertFalse(UpdateInstaller.canReplace(appURL: URL(fileURLWithPath: "/Volumes/claudeGauge/claudeGauge.app"),
                                                  isWritable: { _ in true }))
        XCTAssertFalse(UpdateInstaller.canReplace(appURL: URL(fileURLWithPath: "/Applications/ClaudeGauge.app"),
                                                  isWritable: { _ in false }))
    }

    func testNotReplaceableNeverRunsTools() async {
        let tools = FakeTools()
        let installer = UpdateInstaller(appURL: URL(fileURLWithPath: "/Volumes/claudeGauge/claudeGauge.app"),
                                        runner: tools.runner, relaunch: { _ in })
        do {
            try await installer.install(release())
            XCTFail("expected notReplaceable")
        } catch {
            XCTAssertEqual(error as? UpdateError, .notReplaceable)
        }
        XCTAssertTrue(tools.calls.isEmpty)
    }

    func testMessages() {
        let all: [UpdateError] = [.notReplaceable, .downloadFailed, .mountFailed, .appNotFound,
                                  .wrongBundle, .versionMismatch, .signatureInvalid, .replaceFailed]
        for e in all { XCTAssertFalse(e.message.isEmpty) }
        XCTAssertEqual(UpdateError.downloadFailed.message,
                       "Couldn't download the update. Check your internet connection and try again.")
        XCTAssertEqual(UpdateError.signatureInvalid.message,
                       "The downloaded update didn't pass verification, so it wasn't installed.")
    }
}
