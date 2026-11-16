import AppKit

enum GaugeState: Equatable {
    case starting
    case ok(UsageReading, updated: Date)
    case notLoggedIn
    case offline(last: UsageReading?, lastUpdate: Date?)
}

@MainActor
final class UsagePoller {
    static let interval: TimeInterval = 60

    private let readToken: @Sendable () -> TokenStatus
    private let fetch: (String) async -> FetchOutcome
    private let fetchFable: (String) async -> FableFetchOutcome
    private let fableStore: FableStore
    private let now: () -> Date

    private(set) var state: GaugeState = .starting
    /// Weekly Fable usage, or nil when the account has no Fable limit. Read by the menu when it opens.
    private(set) var fable: FableReading?
    var onChange: ((GaugeState) -> Void)?

    private var fableSchedule = FableSchedule()
    private var isPolling = false
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(readToken: @escaping @Sendable () -> TokenStatus,
         fetch: @escaping (String) async -> FetchOutcome,
         fetchFable: @escaping (String) async -> FableFetchOutcome = { _ in .failed },
         fableStore: FableStore = FableStore(),
         now: @escaping () -> Date = Date.init) {
        self.readToken = readToken
        self.fetch = fetch
        self.fetchFable = fetchFable
        self.fableStore = fableStore
        self.now = now
        self.fable = fableStore.load()
    }

    private func refreshFableIfDue(token: String) async {
        guard fableSchedule.isDue(now: now()) else { return }
        let outcome = await fetchFable(token)
        fableSchedule.record(outcome, now: now())
        switch outcome {
        case .reading(let reading):
            fable = reading
            fableStore.save(reading)
        case .noFable:
            fable = nil
            fableStore.save(nil)
        case .rateLimited, .failed:
            break // keep the last known value
        }
    }

    func pollOnce() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        // Reading the token spawns a process, so keep it off the main thread.
        let read = readToken
        let status = await Task.detached { read() }.value
        guard case .valid(let token) = status else {
            update(.notLoggedIn)
            return
        }
        let outcome = await fetch(token)
        await refreshFableIfDue(token: token)
        switch outcome {
        case .reading(let reading):
            update(.ok(reading, updated: now()))
        case .notLoggedIn:
            update(.notLoggedIn)
        case .offline:
            switch state {
            case .ok(let last, let updated):
                update(.offline(last: last, lastUpdate: updated))
            case .offline:
                break // keep the last known reading
            default:
                update(.offline(last: nil, lastUpdate: nil))
            }
        }
    }

    func start() {
        stop()
        Task { await pollOnce() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollOnce() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.pollOnce() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    private func update(_ new: GaugeState) {
        guard new != state else { return }
        state = new
        onChange?(new)
    }
}
