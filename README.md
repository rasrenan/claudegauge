<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="claudegauge app icon">
</p>

<h1 align="center">claudegauge</h1>

<p align="center">
  <b>A tiny speedometer in your Mac's menu bar that shows how much of your Claude usage limit you have used.</b>
</p>

---

## What is this?

If you use **Claude** (claude.ai or Claude Code) on a Pro or Max plan, your usage
is limited in **5-hour sessions**: once you hit 100% you have to wait for the
session to reset. There is also a **weekly** limit on top of that.

You normally only find out how close you are when you open the usage page, or
when Claude stops you.

**claudegauge puts that number in front of you all the time.** It lives in the
macOS menu bar, next to Wi-Fi and the clock, as a small dial. The needle moves
up as you use Claude, like a car's speedometer.

**At 25% of the session** the dial is mostly empty and green:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/menubar-25-dark.png">
    <img src="docs/images/menubar-25-light.png" width="560" alt="Menu bar with the claudegauge dial at 25%, painted green">
  </picture>
</p>

**At 75% of the session** the needle has passed the top and the dial turns amber.
Time to slow down:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/menubar-75-dark.png">
    <img src="docs/images/menubar-75-light.png" width="560" alt="Menu bar with the claudegauge dial at 75%, painted amber">
  </picture>
</p>

It updates by itself every minute. You don't have to open anything.

## How to read the dial

The dial is the top half of a circle.

- **The needle starts lying flat on the left (0%)** and turns **clockwise** as
  you use Claude. It points straight up at 50% and lies flat on the right at
  100%.
- **The area the needle has passed over is painted**, so you can tell the level
  at a glance even without looking at the needle.
- **Three small ticks** mark 25%, 50% and 75%.
- **The colour tells you how worried to be:**

| Colour | Session usage | Meaning |
|---|---|---|
| 🟢 Green | below 50% | Plenty left |
| 🟠 Amber | 50% to 79% | Over half used |
| 🔴 Red | 80% and above | Close to the limit |

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/states-dark.png">
    <img src="docs/images/states-light.png" width="780" alt="The dial at 0, 25, 50, 75 and 100 percent, offline, not logged in and starting">
  </picture>
</p>

There are also three special states:

- **Offline** (grey): the Mac has no internet. The needle stays at the last
  known value until the connection is back.
- **Not logged in** (`!`): claudegauge can't find a valid Claude login. See
  [Logging in](#logging-in).
- **Starting** (empty dial): shown for a few seconds while the first reading
  comes in.

To see the exact percentage, **hover over the dial**. A tooltip shows it.

## The menu

Click the dial to open its menu:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/menu-dark.png">
    <img src="docs/images/menu-light.png" width="290" alt="claudegauge menu showing session, weekly and Fable usage, Launch at login, Log in, About and Quit">
  </picture>
</p>

| Item | What it does |
|---|---|
| **Session** | Usage of the current 5-hour session and how long until it resets. This is what the dial shows. |
| **Weekly** | Usage of your 7-day limit and when it resets. |
| **Fable** | Weekly usage of the Fable model. **Only shown if your account has a Fable limit.** |
| **Launch at login** | When ticked, claudegauge starts automatically every time you turn on your Mac. |
| **Log in…** | Logs you in to Claude if claudegauge says you're not logged in. It is shown in **bold** when you need it. |
| **About claudegauge** | Opens this project's page on GitHub in your browser. |
| **Quit claudegauge** | Closes the app and removes the dial from the menu bar. |

## Requirements

- A Mac with **macOS 14 (Sonoma) or later**
- **[Claude Code](https://claude.com/claude-code)** installed and logged in at
  least once. claudegauge reuses its login, so there is no separate account or
  password.
- **Xcode** (free on the Mac App Store), only to build the app the first time

## Install

1. Download this repository (green **Code** button → **Download ZIP**, or
   `git clone`).
2. Open **Terminal** in the downloaded folder and run:

   ```bash
   ./install.sh
   ```

   This builds the app, copies it to your **Applications** folder and opens it.
   The dial appears in the menu bar.
3. **The first time it runs**, macOS asks whether `security` may use the
   "Claude Code-credentials" item from your keychain. Click **Always Allow**.
   This is how claudegauge reads your Claude login. If you click *Deny*, the
   dial shows `!`.
4. Click the dial and tick **Launch at login** so it starts with your Mac.

## Logging in

claudegauge doesn't have its own account. It uses the login that **Claude
Code** already saved on your Mac.

If the dial shows `!` (not logged in), click it and choose **Log in…**. A
Terminal window opens and runs `claude auth login`, which opens your browser to
sign in to Claude. Once you've signed in, the dial comes back by itself within
about a minute and a half.

## Uninstall

1. Click the dial and untick **Launch at login**.
2. Click the dial and choose **Quit claudegauge**.
3. Delete **ClaudeGauge** from your **Applications** folder.

## Questions

**Does claudegauge use up my Claude quota?**
Barely. Once a minute it sends Claude the smallest possible request (one word,
one token of reply) and reads the usage numbers that come back with the answer.
The effect on your limit is negligible.

**Where does my login go?**
Nowhere new. claudegauge reads Claude Code's token from your Mac's keychain and
sends it **only to Anthropic's API** (`api.anthropic.com`), the same place
Claude Code sends it. Nothing is stored or sent anywhere else, and claudegauge
never refreshes or changes your login.

**The dial is grey.**
You're offline, or Anthropic's API didn't answer. It recovers by itself.

**Why is the Fable line missing?**
Your account has no Fable limit, or claudegauge hasn't read it yet. The Fable
number is checked every 5 minutes.

**Does it work without Claude Code?**
No. Claude Code provides the login. Install it and log in once.

## How it works (technical)

- **Login:** the OAuth token is read from the keychain item Claude Code creates
  (`Claude Code-credentials`) using Apple's `security` command. The app never
  refreshes the token; Claude Code does.
- **Session and weekly usage:** every 60 s, and when the Mac wakes from sleep,
  the app sends a 1-token request to `claude-haiku-4-5` and reads the
  `anthropic-ratelimit-unified-5h-*` and `-7d-*` response headers. An HTTP 429
  still carries those headers, so it counts as a valid reading.
- **Fable usage:** read from `/api/oauth/usage` every 5 minutes. That endpoint
  rate-limits easily, so on HTTP 429 the wait doubles (5 → 10 → 20 → 30 min) and
  the last value is kept, including across restarts.
- **No Dock icon:** it is a menu bar-only app (`LSUIElement`).

## Development

The app is written in Swift with AppKit and has no third-party dependencies.

```
ClaudeGauge/          app sources (one responsibility per file)
  TokenReader.swift     reads Claude Code's login from the keychain
  UsageClient.swift     asks the API and parses the usage headers
  FableClient.swift     Fable weekly usage, with rate-limit back-off
  UsagePoller.swift     60 s timer and the ok / offline / not-logged-in state
  GaugeIcon.swift       draws the dial
  StatusMenu.swift      the menu bar item and its menu
  LoginLauncher.swift   "Log in…" (opens Terminal with `claude auth login`)
  ResetFormatter.swift  "resets in 2h 13m" text
  Theme.swift           the green / amber / red colours
ClaudeGaugeTests/     unit tests (XCTest)
tools/                icon and README image generators
project.yml           XcodeGen project definition
```

Run the tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ClaudeGauge.xcodeproj -scheme ClaudeGauge \
  -destination 'platform=macOS' -derivedDataPath build test
```

Other useful commands:

- `xcodegen generate` regenerates `ClaudeGauge.xcodeproj` after adding files
  (`brew install xcodegen`).
- `./tools/make-icon.sh` regenerates the app icon.
- `./tools/make-readme-images.sh` regenerates the images in this README.

### Manual test checklist

1. The dial appears and the hover percentage matches Claude's usage page.
2. Turn Wi-Fi off and the dial turns grey. Turn it on and the dial recovers within 60 s.
3. Run `claude auth logout` and the dial shows `!`. Use **Log in…** to log back
   in and the dial recovers.
4. Turn **Launch at login** on and reboot: the app is running. Turn it off and
   reboot: the app is not running.
5. **Quit claudegauge** removes the dial.

## Credit

Inspired by [Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter), an
ESP32 desk display for Claude usage. No code or assets are copied from it. The
icon and the dial are original drawings made in code.

## Licence

MIT. See [LICENSE](LICENSE).
