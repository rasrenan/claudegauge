import AppKit
import ServiceManagement

/// Owns the menu bar item: keeps the gauge icon in step with the poller and
/// builds the dropdown menu each time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    /// Opened by "About claudeGauge".
    static let projectURL = URL(string: "https://github.com/rasrenan/claudegauge")!

    private let poller: UsagePoller
    private let launcher: LoginLauncher
    private let updates: UpdateController
    private let statusItem: NSStatusItem

    init(poller: UsagePoller, launcher: LoginLauncher, updates: UpdateController) {
        self.poller = poller
        self.launcher = launcher
        self.updates = updates
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon(poller.state)
        poller.onChange = { [weak self] state in self?.updateIcon(state) }
    }

    private func updateIcon(_ state: GaugeState) {
        statusItem.button?.image = GaugeIcon.image(for: state)
        statusItem.button?.toolTip = GaugeIcon.label(for: state)
        statusItem.button?.setAccessibilityLabel(GaugeIcon.label(for: state))
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = poller.state

        for line in Self.statusLines(for: state, fable: poller.fable, now: Date()) {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        let loginItem = NSMenuItem(title: "Log in…", action: #selector(logIn), keyEquivalent: "")
        loginItem.target = self
        if Self.needsAttention(state) {
            let bold = NSFontManager.shared.convert(NSFont.menuFont(ofSize: 0), toHaveTrait: .boldFontMask)
            loginItem.attributedTitle = NSAttributedString(string: "Log in…", attributes: [.font: bold])
        }
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About claudeGauge", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit claudeGauge", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.addItem(.separator())
        let row = Self.versionRow(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            state: updates.state)
        menu.addItem(versionItem(text: row.text, button: row.button))
    }

    /// The text of the bottom row, and the title of its button when there is an update to install.
    static func versionRow(version: String?, state: UpdateState) -> (text: String, button: String?) {
        let base = versionText(version)
        switch state {
        case .unknown: return (base, nil)
        case .upToDate: return ("\(base) \u{00B7} updated", nil)
        case .available: return (base, "Update now")
        case .updating: return ("\(base) \u{00B7} updating\u{2026}", nil)
        }
    }

    /// "version <x>", where <x> is read from the running app's CFBundleShortVersionString.
    static func versionText(
        _ version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) -> String {
        "version \(version ?? "?")"
    }

    /// A centred line in the same grey as the disabled usage lines, with an optional button to its right.
    private func versionItem(text: String, button title: String?) -> NSMenuItem {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .disabledControlTextColor
        label.alignment = .center

        let row = NSStackView(views: [label])
        row.orientation = .horizontal
        row.spacing = 8
        if let title {
            let button = NSButton(title: title, target: self, action: #selector(installUpdate))
            button.controlSize = .small
            button.bezelStyle = .rounded
            button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
            row.addArrangedSubview(button)
        }
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: title == nil ? 22 : 28))
        container.autoresizingMask = [.width]
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        return item
    }

    private static func needsAttention(_ state: GaugeState) -> Bool {
        switch state {
        case .notLoggedIn, .offline: return true
        case .starting, .ok: return false
        }
    }

    static func statusLines(for state: GaugeState, fable: FableReading?, now: Date) -> [String] {
        switch state {
        case .starting:
            return ["Checking usage…"]
        case .notLoggedIn:
            return ["Not logged in"]
        case .ok(let reading, _):
            return usageLines(reading, fable: fable, now: now)
        case .offline(let last, let lastUpdate):
            var lines: [String]
            if let lastUpdate {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                lines = ["Offline · last update \(formatter.string(from: lastUpdate))"]
            } else {
                lines = ["Offline"]
            }
            if let last { lines += usageLines(last, fable: fable, now: now) }
            return lines
        }
    }

    private static func usageLines(_ r: UsageReading, fable: FableReading?, now: Date) -> [String] {
        var lines = [line("Session", r.sessionPercent, r.sessionReset, now: now)]
        if let weekly = r.weeklyPercent {
            lines.append(line("Weekly", weekly, r.weeklyReset, now: now))
        }
        if let fable {
            if let reset = fable.reset, reset <= now {
                lines.append("Fable: 0%  ·  resets now")
            } else {
                lines.append(line("Fable", fable.percent, fable.reset, now: now))
            }
        }
        return lines
    }

    private static func line(_ label: String, _ percent: Int, _ reset: Date?, now: Date) -> String {
        var text = "\(label): \(percent)%"
        if let reset { text += "  ·  \(ResetFormatter.text(until: reset, now: now))" }
        return text
    }

    // MARK: Actions

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change Launch at login", error.localizedDescription)
        }
    }

    @objc private func logIn() {
        let poller = self.poller
        switch launcher.launch(onFinish: { Task { await poller.pollOnce() } }) {
        case .started, .alreadyRunning:
            break
        case .claudeNotFound:
            alert("Claude Code not found", "Install Claude Code and log in once, then try again.")
        }
    }

    @objc private func installUpdate() {
        statusItem.menu?.cancelTracking()
        let updates = self.updates
        Task { await updates.installAvailable() }
    }

    @objc private func openAbout() {
        NSWorkspace.shared.open(Self.projectURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
