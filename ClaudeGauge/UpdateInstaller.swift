import AppKit
import Foundation

enum UpdateError: Error, Equatable {
    case notReplaceable
    case downloadFailed
    case mountFailed
    case appNotFound
    case wrongBundle
    case versionMismatch
    case signatureInvalid
    case replaceFailed

    var message: String {
        switch self {
        case .notReplaceable:
            return "claudeGauge can't update itself from this location. Move it to Applications and try again."
        case .downloadFailed:
            return "Couldn't download the update. Check your internet connection and try again."
        case .mountFailed, .appNotFound:
            return "The downloaded update looks damaged. Try again later."
        case .wrongBundle, .versionMismatch, .signatureInvalid:
            return "The downloaded update didn't pass verification, so it wasn't installed."
        case .replaceFailed:
            return "Couldn't replace the app in Applications. Try again, or download the update from GitHub."
        }
    }
}

/// Runs a command-line tool. `.system` uses Process off the main thread.
struct CommandRunner {
    var run: @Sendable (_ tool: String, _ arguments: [String]) async -> (status: Int32, output: String)

    static let system = CommandRunner { tool, arguments in
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, "\(error)"))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus,
                                                String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

@MainActor
final class UpdateInstaller {
    static let bundleID = "io.github.rasrenan.claudegauge"

    private let appURL: URL
    private let runner: CommandRunner
    private let session: URLSession
    private let fileManager: FileManager
    private let relaunch: (URL) -> Void

    init(appURL: URL = Bundle.main.bundleURL,
         runner: CommandRunner = .system,
         session: URLSession = .shared,
         fileManager: FileManager = .default,
         relaunch: @escaping (URL) -> Void = UpdateInstaller.relaunchAndQuit) {
        self.appURL = appURL
        self.runner = runner
        self.session = session
        self.fileManager = fileManager
        self.relaunch = relaunch
    }

    /// True when the app can replace itself in place.
    nonisolated static func canReplace(appURL: URL, isWritable: (String) -> Bool) -> Bool {
        let path = appURL.path
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") { return false }
        return isWritable(appURL.deletingLastPathComponent().path)
    }

    /// Downloads, verifies and installs `release`; on success calls `relaunch(appURL)`.
    /// On any failure throws an UpdateError and leaves the installed app untouched.
    func install(_ release: ReleaseInfo) async throws {
        guard Self.canReplace(appURL: appURL, isWritable: fileManager.isWritableFile(atPath:)) else {
            throw UpdateError.notReplaceable
        }

        let tmp = fileManager.temporaryDirectory
            .appendingPathComponent("claudeGauge-update-\(UUID().uuidString)")
        let mount = tmp.appendingPathComponent("mnt")
        let staging = appURL.deletingLastPathComponent().appendingPathComponent(".claudeGauge-update.app")

        do {
            try await perform(release, tmp: tmp, mount: mount, staging: staging)
        } catch {
            await cleanUp(tmp: tmp, mount: mount, staging: staging)
            throw error
        }
        await cleanUp(tmp: tmp, mount: mount, staging: staging)
        relaunch(appURL)
    }

    /// Detaches the image (a no-op failure if it was never attached) and removes temp files.
    private func cleanUp(tmp: URL, mount: URL, staging: URL) async {
        _ = await runner.run("/usr/bin/hdiutil", ["detach", "-quiet", mount.path])
        try? fileManager.removeItem(at: tmp)
        try? fileManager.removeItem(at: staging)
    }

    private func perform(_ release: ReleaseInfo, tmp: URL, mount: URL, staging: URL) async throws {
        do {
            try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
        } catch {
            throw UpdateError.downloadFailed
        }

        // Download
        let dmg = tmp.appendingPathComponent("ClaudeGauge.dmg")
        do {
            let (location, response) = try await session.download(from: release.dmgURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateError.downloadFailed
            }
            try fileManager.moveItem(at: location, to: dmg)
        } catch {
            throw UpdateError.downloadFailed
        }

        // Mount
        let attach = await runner.run("/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        guard attach.status == 0 else { throw UpdateError.mountFailed }

        // Locate and verify
        let entries = (try? fileManager.contentsOfDirectory(
            at: mount, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        guard let found = entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first(where: {
            $0.pathExtension == "app" && ((try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
        }) else { throw UpdateError.appNotFound }

        let info = (NSDictionary(contentsOf: found.appendingPathComponent("Contents/Info.plist"))
                    as? [String: Any]) ?? [:]
        guard info["CFBundleIdentifier"] as? String == Self.bundleID else { throw UpdateError.wrongBundle }
        guard let versionText = info["CFBundleShortVersionString"] as? String,
              SemVer(versionText) == release.version else { throw UpdateError.versionMismatch }

        let sign = await runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", found.path])
        guard sign.status == 0 else { throw UpdateError.signatureInvalid }

        // Stage next to the installed app (same volume), then swap.
        try? fileManager.removeItem(at: staging)
        let copy = await runner.run("/usr/bin/ditto", [found.path, staging.path])
        guard copy.status == 0 else { throw UpdateError.replaceFailed }
        _ = await runner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])

        do {
            _ = try fileManager.replaceItemAt(appURL, withItemAt: staging)
        } catch {
            throw UpdateError.replaceFailed
        }
    }

    nonisolated static func relaunchAndQuit(_ appURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$1\"", "sh", appURL.path]
        try? process.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
