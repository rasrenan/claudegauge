import XCTest
@testable import ClaudeGauge

@MainActor
final class LoginLauncherTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone")

    private func find(existing: Set<String>) -> URL? {
        LoginLauncher.findClaude(home: home, fileExists: { existing.contains($0) })
    }

    func testFindsLocalBin() {
        XCTAssertEqual(find(existing: ["/Users/someone/.local/bin/claude"])?.path, "/Users/someone/.local/bin/claude")
    }

    func testFindsHomebrew() {
        XCTAssertEqual(find(existing: ["/opt/homebrew/bin/claude"])?.path, "/opt/homebrew/bin/claude")
    }

    func testFindsUsrLocal() {
        XCTAssertEqual(find(existing: ["/usr/local/bin/claude"])?.path, "/usr/local/bin/claude")
    }

    func testPrefersLocalBin() {
        let both: Set<String> = ["/Users/someone/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        XCTAssertEqual(find(existing: both)?.path, "/Users/someone/.local/bin/claude")
        XCTAssertEqual(find(existing: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"])?.path, "/opt/homebrew/bin/claude")
    }

    func testFindsNothing() {
        XCTAssertNil(find(existing: []))
    }

    func testLaunchWithoutClaudeReportsNotFound() {
        var ran = false
        let launcher = LoginLauncher(find: { nil }, run: { _ in ran = true }, schedule: { _, _ in })
        XCTAssertEqual(launcher.launch(onFinish: {}), .claudeNotFound)
        XCTAssertFalse(launcher.isRunning)
        XCTAssertFalse(ran)
    }

    func testSecondLaunchWhileRunningIsRejected() {
        var runs = 0
        let launcher = LoginLauncher(
            find: { URL(fileURLWithPath: "/opt/homebrew/bin/claude") },
            run: { _ in runs += 1 },
            schedule: { _, _ in }) // never fires
        XCTAssertEqual(launcher.launch(onFinish: {}), .started)
        XCTAssertTrue(launcher.isRunning)
        XCTAssertEqual(launcher.launch(onFinish: {}), .alreadyRunning)
        XCTAssertEqual(runs, 1)
    }

    func testFinishesAfterNinetySeconds() {
        var scheduled: (delay: TimeInterval, action: @MainActor () -> Void)?
        var finished = 0
        let claude = URL(fileURLWithPath: "/opt/homebrew/bin/claude")
        var ranWith: URL?
        let launcher = LoginLauncher(
            find: { claude },
            run: { ranWith = $0 },
            schedule: { scheduled = ($0, $1) })
        XCTAssertEqual(launcher.launch(onFinish: { finished += 1 }), .started)
        XCTAssertEqual(ranWith, claude)
        XCTAssertEqual(scheduled?.delay, 90)
        XCTAssertEqual(finished, 0)
        scheduled?.action()
        XCTAssertEqual(finished, 1)
        XCTAssertFalse(launcher.isRunning)
        // Can launch again afterwards.
        XCTAssertEqual(launcher.launch(onFinish: {}), .started)
    }

    func testOsascriptArgumentsQuotePathsWithSpacesAndQuotes() {
        let url = URL(fileURLWithPath: "/Users/some one/it's \"x\"/claude")
        let args = LoginLauncher.osascriptArguments(for: url)
        XCTAssertEqual(args, [
            "-e", #"tell application "Terminal" to do script "'/Users/some one/it'\\''s \"x\"/claude' auth login""#,
            "-e", #"tell application "Terminal" to activate"#,
        ])
    }
}
