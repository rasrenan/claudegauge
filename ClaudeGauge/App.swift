import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var poller: UsagePoller?
    private var launcher: LoginLauncher?
    private var statusMenu: StatusMenu?
    private var updates: UpdateController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit-test host launches this app too; do not touch the Keychain or the API there.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        let poller = UsagePoller(
            readToken: { TokenReader().status(now: Date()) },
            fetch: { await UsageClient().fetch(token: $0) },
            fetchFable: { await FableClient().fetch(token: $0) })
        let launcher = LoginLauncher()
        self.poller = poller
        self.launcher = launcher
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let updates = UpdateController(
            current: bundleVersion.flatMap { SemVer($0) },
            check: { await UpdateChecker().check(current: $0) },
            install: { try await UpdateInstaller().install($0) },
            showError: { message in
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Update failed"
                alert.informativeText = message
                alert.runModal()
            })
        self.updates = updates
        statusMenu = StatusMenu(poller: poller, launcher: launcher, updates: updates)
        poller.start()
        updates.start()
    }
}
