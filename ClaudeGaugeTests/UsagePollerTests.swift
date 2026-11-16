import XCTest
@testable import ClaudeGauge

@MainActor
final class UsagePollerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let r1 = UsageReading(sessionPercent: 47, sessionReset: nil, weeklyPercent: nil, weeklyReset: nil)
    private let r2 = UsageReading(sessionPercent: 52, sessionReset: nil, weeklyPercent: nil, weeklyReset: nil)

    private final class Fetcher {
        var outcome: FetchOutcome
        var calls = 0
        var onCall: (() -> Void)?
        init(_ outcome: FetchOutcome) { self.outcome = outcome }
        func fetch(_ token: String) async -> FetchOutcome {
            calls += 1
            onCall?()
            return outcome
        }
    }

    private final class FableFetcher {
        var outcome: FableFetchOutcome
        var calls = 0
        init(_ outcome: FableFetchOutcome) { self.outcome = outcome }
        func fetch(_ token: String) async -> FableFetchOutcome {
            calls += 1
            return outcome
        }
    }

    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private var suites: [String] = []

    private func isolatedStore() -> FableStore {
        let name = "poller-tests-\(UUID().uuidString)"
        suites.append(name)
        return FableStore(defaults: UserDefaults(suiteName: name)!)
    }

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makePoller(token: TokenStatus = .valid("t"), fetcher: Fetcher) -> UsagePoller {
        let now = self.now
        return UsagePoller(readToken: { token }, fetch: { await fetcher.fetch($0) },
                           fableStore: isolatedStore(), now: { now })
    }

    private func makeFablePoller(token: TokenStatus = .valid("t"), fable: FableFetcher,
                                 clock: Clock, store: FableStore) -> UsagePoller {
        let r1 = self.r1
        return UsagePoller(readToken: { token }, fetch: { _ in .reading(r1) },
                           fetchFable: { await fable.fetch($0) }, fableStore: store, now: { clock.date })
    }

    private let fr = FableReading(percent: 9, reset: nil)

    func testFableReadingIsStoredAndPersisted() async {
        let store = isolatedStore()
        let poller = makeFablePoller(fable: FableFetcher(.reading(fr)), clock: Clock(now), store: store)
        await poller.pollOnce()
        XCTAssertEqual(poller.fable, fr)
        XCTAssertEqual(store.load(), fr)
    }

    func testNoFableClearsReading() async {
        let store = isolatedStore()
        let clock = Clock(now)
        let fable = FableFetcher(.reading(fr))
        let poller = makeFablePoller(fable: fable, clock: clock, store: store)
        await poller.pollOnce()
        fable.outcome = .noFable
        clock.date = now.addingTimeInterval(300)
        await poller.pollOnce()
        XCTAssertNil(poller.fable)
        XCTAssertNil(store.load())
    }

    func testRateLimitedAndFailedKeepPreviousFable() async {
        let clock = Clock(now)
        let fable = FableFetcher(.reading(fr))
        let poller = makeFablePoller(fable: fable, clock: clock, store: isolatedStore())
        await poller.pollOnce()
        fable.outcome = .rateLimited(retryAfter: nil)
        clock.date = now.addingTimeInterval(300)
        await poller.pollOnce()
        XCTAssertEqual(poller.fable, fr)
        fable.outcome = .failed
        clock.date = now.addingTimeInterval(1000)
        await poller.pollOnce()
        XCTAssertEqual(fable.calls, 3)
        XCTAssertEqual(poller.fable, fr)
    }

    func testMissingTokenDoesNotFetchFable() async {
        let fable = FableFetcher(.reading(fr))
        let poller = makeFablePoller(token: .missing, fable: fable, clock: Clock(now), store: isolatedStore())
        await poller.pollOnce()
        XCTAssertEqual(fable.calls, 0)
        XCTAssertNil(poller.fable)
    }

    func testFableNotRefetchedWithinFiveMinutes() async {
        let clock = Clock(now)
        let fable = FableFetcher(.reading(fr))
        let poller = makeFablePoller(fable: fable, clock: clock, store: isolatedStore())
        await poller.pollOnce()
        clock.date = now.addingTimeInterval(60)
        await poller.pollOnce()
        XCTAssertEqual(fable.calls, 1)
        clock.date = now.addingTimeInterval(300)
        await poller.pollOnce()
        XCTAssertEqual(fable.calls, 2)
    }

    func testStartsWithPersistedFable() {
        let store = isolatedStore()
        store.save(fr)
        let poller = makeFablePoller(fable: FableFetcher(.failed), clock: Clock(now), store: store)
        XCTAssertEqual(poller.fable, fr)
    }

    func testInitialStateIsStarting() {
        XCTAssertEqual(makePoller(fetcher: Fetcher(.offline)).state, .starting)
    }

    func testValidTokenAndReadingGivesOkAndNotifiesOnce() async {
        let poller = makePoller(fetcher: Fetcher(.reading(r1)))
        var received: [GaugeState] = []
        poller.onChange = { received.append($0) }
        await poller.pollOnce()
        XCTAssertEqual(poller.state, .ok(r1, updated: now))
        XCTAssertEqual(received, [.ok(r1, updated: now)])
    }

    func testMissingTokenIsNotLoggedInWithoutFetching() async {
        let fetcher = Fetcher(.reading(r1))
        let poller = makePoller(token: .missing, fetcher: fetcher)
        await poller.pollOnce()
        XCTAssertEqual(poller.state, .notLoggedIn)
        XCTAssertEqual(fetcher.calls, 0)
    }

    func testExpiredTokenIsNotLoggedIn() async {
        let fetcher = Fetcher(.reading(r1))
        let poller = makePoller(token: .expired, fetcher: fetcher)
        await poller.pollOnce()
        XCTAssertEqual(poller.state, .notLoggedIn)
        XCTAssertEqual(fetcher.calls, 0)
    }

    func testFetchNotLoggedInIsNotLoggedIn() async {
        let poller = makePoller(fetcher: Fetcher(.notLoggedIn))
        await poller.pollOnce()
        XCTAssertEqual(poller.state, .notLoggedIn)
    }

    func testOfflineAfterOkKeepsLastReading() async {
        let fetcher = Fetcher(.reading(r1))
        let poller = makePoller(fetcher: fetcher)
        await poller.pollOnce()
        fetcher.outcome = .offline
        await poller.pollOnce()
        XCTAssertEqual(poller.state, .offline(last: r1, lastUpdate: now))
    }

    func testOfflineFromStartingHasNoReading() async {
        let poller = makePoller(fetcher: Fetcher(.offline))
        await poller.pollOnce()
        XCTAssertEqual(poller.state, .offline(last: nil, lastUpdate: nil))
    }

    func testRecoveryFromOffline() async {
        let fetcher = Fetcher(.reading(r1))
        let poller = makePoller(fetcher: fetcher)
        await poller.pollOnce()
        fetcher.outcome = .offline
        await poller.pollOnce()
        fetcher.outcome = .reading(r2)
        await poller.pollOnce()
        XCTAssertEqual(poller.state, .ok(r2, updated: now))
    }

    func testUnchangedStateDoesNotNotifyAgain() async {
        let poller = makePoller(fetcher: Fetcher(.reading(r1)))
        var count = 0
        poller.onChange = { _ in count += 1 }
        await poller.pollOnce()
        await poller.pollOnce()
        XCTAssertEqual(count, 1)
    }

    func testConcurrentPollsPerformOnlyOneFetch() async {
        var continuation: CheckedContinuation<FetchOutcome, Never>?
        var calls = 0
        let started = expectation(description: "first fetch started")
        let r1 = self.r1
        let now = self.now
        let poller = UsagePoller(
            readToken: { .valid("t") },
            fetch: { _ in
                calls += 1
                started.fulfill()
                return await withCheckedContinuation { continuation = $0 }
            },
            now: { now })
        let first = Task { await poller.pollOnce() }
        await fulfillment(of: [started], timeout: 2)
        await poller.pollOnce() // returns immediately: a poll is in flight
        XCTAssertEqual(calls, 1)
        continuation?.resume(returning: .reading(r1))
        await first.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(poller.state, .ok(r1, updated: now))
    }

    func testWakeTriggersPoll() async {
        let fetcher = Fetcher(.reading(r1))
        let poller = makePoller(fetcher: fetcher)
        let first = expectation(description: "initial poll")
        fetcher.onCall = { first.fulfill() }
        poller.start()
        defer { poller.stop() }
        await fulfillment(of: [first], timeout: 2)
        // Let the initial poll finish so the in-flight guard is clear.
        while poller.state == .starting { await Task.yield() }
        let before = fetcher.calls
        let woke = expectation(description: "poll after wake")
        fetcher.onCall = { woke.fulfill() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await fulfillment(of: [woke], timeout: 2)
        XCTAssertGreaterThan(fetcher.calls, before)
    }
}
