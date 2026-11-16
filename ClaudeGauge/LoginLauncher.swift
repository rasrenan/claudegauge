import Foundation

enum LaunchResult: Equatable {
    case started, alreadyRunning, claudeNotFound
}

/// Starts `claude auth login` in Terminal.app (mode B). There is no process to
/// watch, so `onFinish` fires a fixed time after launch.
@MainActor
final class LoginLauncher {
    static let finishDelay: TimeInterval = 90

    nonisolated static func findClaude(home: URL, fileExists: (String) -> Bool) -> URL? {
        let candidates = [
            home.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first(where: fileExists).map { URL(fileURLWithPath: $0) }
    }

    /// Arguments for `/usr/bin/osascript` that run `<claude> auth login` in Terminal.
    nonisolated static func osascriptArguments(for claude: URL) -> [String] {
        let shellQuoted = "'" + claude.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let appleScriptEscaped = (shellQuoted + " auth login")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return [
            "-e", "tell application \"Terminal\" to do script \"\(appleScriptEscaped)\"",
            "-e", "tell application \"Terminal\" to activate",
        ]
    }

    private let find: () -> URL?
    private let run: (URL) -> Void
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void

    private(set) var isRunning = false

    init(find: @escaping () -> URL? = {
             LoginLauncher.findClaude(home: FileManager.default.homeDirectoryForCurrentUser,
                                      fileExists: FileManager.default.isExecutableFile(atPath:))
         },
         run: @escaping (URL) -> Void = LoginLauncher.runInTerminal,
         schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = LoginLauncher.scheduleOnMain) {
        self.find = find
        self.run = run
        self.schedule = schedule
    }

    func launch(onFinish: @escaping () -> Void) -> LaunchResult {
        guard !isRunning else { return .alreadyRunning }
        guard let claude = find() else { return .claudeNotFound }
        isRunning = true
        run(claude)
        schedule(Self.finishDelay) { [weak self] in
            self?.isRunning = false
            onFinish()
        }
        return .started
    }

    /// Fire and forget: osascript returns as soon as Terminal has the command.
    nonisolated private static func runInTerminal(_ claude: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = osascriptArguments(for: claude)
        try? process.run()
    }

    nonisolated private static func scheduleOnMain(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            action()
        }
    }
}
