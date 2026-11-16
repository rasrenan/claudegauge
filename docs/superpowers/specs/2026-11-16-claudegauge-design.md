# claudegauge — Design

Date: 2026-11-16
Status: awaiting review

## 1. Goal

A native macOS menu bar app that runs in the background and shows, in real
time, how much of the current Claude session window (the 5-hour rate-limit
window) has been used. It is the desktop equivalent of the "Current" bar on
the Clawdmeter ESP32 device, drawn as a battery-like gauge in the menu bar.

Success criteria:

- The gauge is always visible in the menu bar and updates every 60 s.
- It needs no setup beyond an existing Claude Code login.
- When there is no valid login, the user sees it at a glance and can fix it
  with one click ("Log in…").
- It can be set to launch with the Mac and quit from its own menu.

Out of scope (YAGNI): Bluetooth/device support, the Fable weekly bar, running
agents count, chime, Enterprise billing-period view, notifications, settings
window, localisation, App Store or notarised distribution, Windows/Linux.

## 2. Decisions and reasons

| Decision | Reason |
|---|---|
| Swift + AppKit (`NSStatusItem`), Xcode project | Full control over drawing a coloured icon; SwiftUI `MenuBarExtra` forces monochrome template images. User has full Xcode. |
| Minimum macOS 14 | `SMAppService` (official launch-at-login) needs 13+; 14 keeps APIs modern while covering current Macs. |
| Reuse Claude Code's login (Keychain item `Claude Code-credentials`) | Same as Clawdmeter; no unofficial OAuth flow to maintain; Claude Code owns token refresh. User accepted the dependency. |
| Read usage from rate-limit response headers of a 1-token Haiku call, every 60 s | Proven in Clawdmeter; the dedicated `oauth/usage` endpoint returns 429 on most calls. Cost: one tiny request per minute, same as Clawdmeter today. |
| Rewrite from scratch, no code or assets copied from Clawdmeter | Clawdmeter has no licence and bundles proprietary fonts and the Clawd mascot. Only behaviour and the colour values are reused. System font only. |
| MIT licence, public GitHub repo `rasrenan/claudegauge` | User chose public. Repo is created and pushed only on explicit user authorisation at that moment. |
| Menu text in English | User choice. |
| Ad-hoc local signing ("Sign to Run Locally") | Personal use, no paid developer account. Side effect: macOS may re-ask Keychain permission after each reinstall. |

## 3. Behaviour

### 3.1 Polling cycle

Every 60 s (and immediately at launch, after "Log in…", and when the Mac
wakes from sleep):

1. Read the Keychain item `Claude Code-credentials` (generic password).
   The secret is JSON, either flat (`{"accessToken": ...}`) or nested
   (`{"claudeAiOauth": {"accessToken": ..., "expiresAt": <ms>}}`), and may be
   returned hex-encoded; decode both forms.
2. `POST https://api.anthropic.com/v1/messages` with headers
   `Authorization: Bearer <token>`, `anthropic-version: 2023-06-01`,
   `anthropic-beta: oauth-2025-04-20`, `Content-Type: application/json`, and
   body `{"model": "claude-haiku-4-5-20251001", "max_tokens": 1,
   "messages": [{"role": "user", "content": "hi"}]}`. Timeout 20 s.
3. Parse response headers (a 429 that carries them is a valid reading):
   - `anthropic-ratelimit-unified-5h-utilization` (0–1 float) → session %
   - `anthropic-ratelimit-unified-5h-reset` (epoch seconds) → session reset
   - `anthropic-ratelimit-unified-7d-utilization` → weekly %
   - `anthropic-ratelimit-unified-7d-reset` → weekly reset
   - If 5h headers are absent but `anthropic-ratelimit-unified-overage-utilization`
     is present (Enterprise), show that as the session % and hide the weekly line.

The first Keychain read triggers a macOS prompt; the user picks "Always Allow".

### 3.2 States

| State | Trigger | Icon | Menu |
|---|---|---|---|
| OK | Valid reading | Coloured gauge with % | Session and weekly lines |
| Not logged in | No Keychain item, no token, or HTTP 401/403 | Outlined gauge with ⚠ | "Not logged in" line; "Log in…" shown bold |
| Offline | Network error, timeout, 5xx, or 429 without usage headers | Last % in grey | "Offline · last update HH:MM"; "Log in…" shown bold |
| Starting | Before the first reading | Empty outlined gauge with "--" | "Checking usage…" |

The app never refreshes tokens. A token that has expired (`expiresAt` in the
past) is treated as "Not logged in" until Claude Code rewrites it.

### 3.3 Icon

- Battery-like rounded rectangle, roughly 38×16 pt, drawn in code for Retina.
- The fill grows left to right with the session %.
- The percentage is drawn inside the bar in a bold system font with a dark
  outline so it stays readable over any fill.
- Colours (from Clawdmeter `theme.h`):
  - green `#788c5d` for % < 50
  - amber/terra-cotta `#d97757` for 50 ≤ % < 80
  - red `#c0392b` for % ≥ 80
  - track `#2a2a28`; offline fill uses the system secondary label colour.

### 3.4 Menu

```
Session: 47%  ·  resets in 2h 13m
Weekly:  31%  ·  resets Thu 14:00
─────────────
✓ Launch at login
Log in…
─────────────
Quit claudegauge
```

- Reset formatting: under 60 min → "resets in 42m"; under 24 h → "resets in
  2h 13m"; otherwise → "resets Thu 14:00" (user's locale and 12/24 h setting).
- "Launch at login" is a checkmark toggle backed by
  `SMAppService.mainApp.register()/unregister()`; its state is read from the
  system each time the menu opens.
- "Log in…" runs `claude auth login`, which opens the browser. The `claude`
  binary is looked up in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`.
  If it is not found, the item shows an alert explaining that Claude Code must
  be installed. If running it without a terminal does not open the browser
  (to be verified first in implementation), fall back to opening Terminal.app
  with the command. A poll is triggered when the process exits.
- "Quit claudegauge" terminates the app.
- The app has no Dock icon (`LSUIElement = YES`).

## 4. Components

| File | Responsibility | Depends on |
|---|---|---|
| `App.swift` | Entry point; creates poller and status menu; no Dock icon | all below |
| `Theme.swift` | Colour constants; `color(forPercent:)` thresholds | — |
| `TokenReader.swift` | Read and decode Keychain secret → token + expiry | Security framework |
| `UsageClient.swift` | Build request, parse headers into `UsageReading` or an error | URLSession |
| `UsagePoller.swift` | 60 s timer, wake handling, holds last reading and state; publishes changes | TokenReader, UsageClient |
| `GaugeIcon.swift` | Draw `NSImage` from (state, percent) | Theme |
| `StatusMenu.swift` | `NSStatusItem`, builds menu, wires actions | Poller, GaugeIcon, LoginLauncher, SMAppService |
| `LoginLauncher.swift` | Locate `claude`, run `claude auth login`, report exit | Process |
| `ResetFormatter.swift` | Reset date → "resets in…" text | — |

Parsing (`UsageClient` header parsing, `TokenReader` decoding,
`ResetFormatter`, `Theme`) is pure logic with no I/O so it can be unit-tested.

## 5. Repository layout

```
claudegauge/
├── ClaudeGauge.xcodeproj
├── ClaudeGauge/            (sources above + Info.plist, Assets)
├── ClaudeGaugeTests/
├── install.sh              (xcodebuild Release → copy to /Applications, relaunch)
├── README.md               (what it is, install, manual test checklist, credit to Clawdmeter)
├── LICENSE                 (MIT)
└── docs/superpowers/specs/ (this file)
```

## 6. Testing

Automated (XCTest, `xcodebuild test`):

- Header parsing: normal 200; 429 with headers (valid reading); 429 without
  headers (offline); 401 (not logged in); Enterprise overage headers.
- Token decoding: flat JSON, nested JSON, hex-encoded secret, malformed input,
  expired `expiresAt`.
- Colour thresholds: 0, 49 → green; 50, 79 → amber; 80, 100 → red.
- Reset formatting: 42 min, 2 h 13 min, more than 24 h, past date.

Manual checklist (in README):

1. Icon appears and the % matches the Claude usage page.
2. Wi-Fi off → grey "Offline"; Wi-Fi on → recovers within 60 s.
3. `claude auth logout` → ⚠ "Not logged in"; "Log in…" opens the browser and
   the gauge recovers after login.
4. "Launch at login" on → reboot → app is running; off → reboot → not running.
5. "Quit claudegauge" removes the icon.

## 7. Prerequisite for the user

The terminal currently points at Command Line Tools. Before the first build
the user runs once:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
