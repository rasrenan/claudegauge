import XCTest
@testable import ClaudeGauge

@MainActor
final class UpdateControllerTests: XCTestCase {
    private let release = ReleaseInfo(
        version: SemVer(major: 0, minor: 2, patch: 0),
        dmgURL: URL(string: "https://example.com/ClaudeGauge.dmg")!,
        pageURL: URL(string: "https://example.com/release")!)
    private let current = SemVer(major: 0, minor: 1, patch: 0)

    private final class Spy {
        var checkCalls = 0
        var installCalls = 0
        var openedPages: [URL] = []
        var errors: [String] = []
        var checkResult: UpdateCheckResult = .upToDate
        var installError: Error?
        var installGate: CheckedContinuation<Void, Never>?
        var suspendInstall = false
    }

    private func makeController(_ spy: Spy, current: SemVer?) -> UpdateController {
        UpdateController(
            current: current,
            check: { _ in spy.checkCalls += 1; return spy.checkResult },
            install: { _ in
                spy.installCalls += 1
                if spy.suspendInstall {
                    await withCheckedContinuation { spy.installGate = $0 }
                }
                if let error = spy.installError { throw error }
            },
            openPage: { spy.openedPages.append($0) },
            showError: { spy.errors.append($0) })
    }

    private func availableController(_ spy: Spy) async -> UpdateController {
        let controller = makeController(spy, current: current)
        spy.checkResult = .available(release)
        await controller.checkNow()
        return controller
    }

    func testStartsUnknown() {
        XCTAssertEqual(makeController(Spy(), current: current).state, .unknown)
    }

    func testUpToDateResult() async {
        let spy = Spy()
        let controller = makeController(spy, current: current)
        await controller.checkNow()
        XCTAssertEqual(controller.state, .upToDate)
    }

    func testAvailableResult() async {
        let spy = Spy()
        let controller = await availableController(spy)
        XCTAssertEqual(controller.state, .available(release))
    }

    func testFailedKeepsUnknown() async {
        let spy = Spy()
        spy.checkResult = .failed
        let controller = makeController(spy, current: current)
        await controller.checkNow()
        XCTAssertEqual(controller.state, .unknown)
    }

    func testFailedKeepsUpToDate() async {
        let spy = Spy()
        let controller = makeController(spy, current: current)
        await controller.checkNow()
        spy.checkResult = .failed
        await controller.checkNow()
        XCTAssertEqual(controller.state, .upToDate)
    }

    func testNilCurrentNeverChecks() async {
        let spy = Spy()
        let controller = makeController(spy, current: nil)
        await controller.checkNow()
        controller.start()
        XCTAssertEqual(spy.checkCalls, 0)
        XCTAssertEqual(controller.state, .unknown)
    }

    func testInstallFromUpToDateDoesNothing() async {
        let spy = Spy()
        let controller = makeController(spy, current: current)
        await controller.checkNow()
        await controller.installAvailable()
        XCTAssertEqual(spy.installCalls, 0)
        XCTAssertEqual(controller.state, .upToDate)
    }

    func testInstallSuccessCallsInstallOnce() async {
        let spy = Spy()
        let controller = await availableController(spy)
        await controller.installAvailable()
        XCTAssertEqual(spy.installCalls, 1)
        XCTAssertTrue(spy.errors.isEmpty)
    }

    func testNotReplaceableOpensPage() async {
        let spy = Spy()
        let controller = await availableController(spy)
        spy.installError = UpdateError.notReplaceable
        await controller.installAvailable()
        XCTAssertEqual(spy.openedPages, [release.pageURL])
        XCTAssertTrue(spy.errors.isEmpty)
        XCTAssertEqual(controller.state, .available(release))
    }

    func testUpdateErrorShowsItsMessage() async {
        let spy = Spy()
        let controller = await availableController(spy)
        spy.installError = UpdateError.downloadFailed
        await controller.installAvailable()
        XCTAssertEqual(spy.errors, [UpdateError.downloadFailed.message])
        XCTAssertEqual(controller.state, .available(release))
    }

    func testGenericErrorShowsFallbackMessage() async {
        struct Boom: Error {}
        let spy = Spy()
        let controller = await availableController(spy)
        spy.installError = Boom()
        await controller.installAvailable()
        XCTAssertEqual(spy.errors, ["The update failed. Try again later."])
        XCTAssertEqual(controller.state, .available(release))
    }

    func testCheckIgnoredWhileUpdating() async {
        let spy = Spy()
        let controller = await availableController(spy)
        spy.suspendInstall = true
        let installing = Task { await controller.installAvailable() }
        while spy.installGate == nil { await Task.yield() }
        XCTAssertEqual(controller.state, .updating)
        let before = spy.checkCalls
        await controller.checkNow()
        XCTAssertEqual(spy.checkCalls, before)
        XCTAssertEqual(controller.state, .updating)
        spy.installGate?.resume()
        await installing.value
    }

    func testOnChangeFiresOnlyOnRealChanges() async {
        let spy = Spy()
        let controller = makeController(spy, current: current)
        var changes: [UpdateState] = []
        controller.onChange = { changes.append($0) }
        await controller.checkNow()
        await controller.checkNow()
        spy.checkResult = .failed
        await controller.checkNow()
        XCTAssertEqual(changes, [.upToDate])
    }
}
