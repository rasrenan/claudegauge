import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var poller: UsagePoller?
    private var launcher: LoginLauncher?
    private var statusMenu: StatusMenu?

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
            fetch: { await UsageClient().fetch(token: $0) })
        let launcher = LoginLauncher()
        self.poller = poller
        self.launcher = launcher
        statusMenu = StatusMenu(poller: poller, launcher: launcher)
        poller.start()
    }
}
