import AppKit

enum UpdateState: Equatable {
    case unknown              // not checked yet, or every check so far failed
    case upToDate
    case available(ReleaseInfo)
    case updating
}

/// Holds the update state, checks for a new release daily and runs the install.
@MainActor
final class UpdateController {
    static let firstCheckDelay: TimeInterval = 10
    static let checkInterval: TimeInterval = 24 * 60 * 60

    private(set) var state: UpdateState = .unknown {
        didSet { if state != oldValue { onChange?(state) } }
    }
    var onChange: ((UpdateState) -> Void)?

    private let current: SemVer?
    private let check: (SemVer) async -> UpdateCheckResult
    private let install: (ReleaseInfo) async throws -> Void
    private let openPage: (URL) -> Void
    private let showError: (String) -> Void
    private var timer: Timer?

    init(current: SemVer?,
         check: @escaping (SemVer) async -> UpdateCheckResult,
         install: @escaping (ReleaseInfo) async throws -> Void,
         openPage: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         showError: @escaping (String) -> Void) {
        self.current = current
        self.check = check
        self.install = install
        self.openPage = openPage
        self.showError = showError
    }

    /// First check after `firstCheckDelay`, then every `checkInterval`.
    func start() {
        guard current != nil, timer == nil else { return }
        let first = Timer(timeInterval: Self.firstCheckDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.checkNow()
                self.scheduleDaily()
            }
        }
        RunLoop.main.add(first, forMode: .common)
        timer = first
    }

    private func scheduleDaily() {
        let daily = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkNow() }
        }
        RunLoop.main.add(daily, forMode: .common)
        timer = daily
    }

    func checkNow() async {
        guard let current, state != .updating else { return }
        let result = await check(current)
        // An install may have started while the check was in flight.
        guard state != .updating else { return }
        switch result {
        case .upToDate: state = .upToDate
        case .available(let release): state = .available(release)
        case .failed: break
        }
    }

    func installAvailable() async {
        guard case .available(let release) = state else { return }
        state = .updating
        do {
            try await install(release)
        } catch UpdateError.notReplaceable {
            openPage(release.pageURL)
            state = .available(release)
        } catch let error as UpdateError {
            showError(error.message)
            state = .available(release)
        } catch {
            showError("The update failed. Try again later.")
            state = .available(release)
        }
    }
}
