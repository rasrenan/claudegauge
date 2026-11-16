# claudegauge

A native macOS menu bar app that shows your Claude 5-hour session usage as a
coloured, battery-like gauge: green below 50%, amber from 50%, red from 80%.
Click it to see the exact numbers.

```
Session: 47%  ·  resets in 2h 13m
Weekly:  31%  ·  resets Thu 14:00
─────────────
✓ Launch at login
Log in…
─────────────
Quit claudegauge
```

## Requirements

- macOS 14 or later
- Xcode (installed at `/Applications/Xcode.app`)
- Claude Code, logged in at least once

## Install

```
./install.sh
```

This builds the app in Release mode, copies it to `/Applications` and opens it.
Then click the gauge in the menu bar and tick **Launch at login** to start it
with your Mac.

The first time it runs, macOS asks whether `security` may read
"Claude Code-credentials" from your Keychain. Click **Always Allow**.

## Uninstall

1. Click the gauge and choose **Quit claudegauge**.
2. Untick **Launch at login** first if it was on.
3. Delete `/Applications/ClaudeGauge.app`.

## How it works

- The OAuth token is read from the Keychain item that Claude Code creates
  ("Claude Code-credentials"), using the `security` command.
- Once a minute (and on wake) the app sends a 1-token Haiku request and reads
  the rate-limit headers from the response. That gives the session and weekly
  percentages and their reset times.
- **Log in…** opens Terminal running `claude auth login`, which opens the
  browser. The gauge refreshes about 90 seconds later.

## Manual test checklist

1. Icon appears and the % matches the Claude usage page.
2. Wi-Fi off → grey "Offline"; Wi-Fi on → recovers within 60 s.
3. `claude auth logout` → ⚠ "Not logged in"; "Log in…" opens the browser and
   the gauge recovers after login.
4. "Launch at login" on → reboot → app is running; off → reboot → not running.
5. "Quit claudegauge" removes the icon.

## Credit

Inspired by Clawdmeter (github.com/HermannBjorgvin/Clawdmeter). No code or
assets are copied from it.

## Licence

MIT. See [LICENSE](LICENSE).
