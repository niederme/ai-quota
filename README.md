# AIQuota

A native macOS menubar utility to monitor your AI coding quota — track [OpenAI Codex](https://openai.com/codex) and [Claude Code](https://claude.ai) usage at a glance, without opening a browser.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

<img alt="AIQuota App & Widgets" src="https://github.com/user-attachments/assets/ff816ffb-7b02-41d3-a688-53f775d0fa86" />


---

## Features

- **Menubar gauge icon** — color-coded arc gauge showing quota consumption at a glance; tracks whichever service you configure (or falls back to whichever is authenticated)
- **Dual-arc gauge** — both services displayed as concentric arc gauges in the popover, with the 5-hour window as the outer ring and the 7-day window as the inner ring; color shifts from purple → amber → red as you approach your limit
- **Codex + Claude Code** — each service shows reset timers, plan badges, and per-service refresh buttons; credits and plan info in a summary row below the gauges
- **Widgets** — small widget shows one service (right-click to choose); medium widget always shows both Codex and Claude Code side by side with a refresh button
- **Network recovery** — detects when connectivity is restored and refreshes immediately, clearing stale error banners automatically
- **Guided onboarding** — a step-by-step setup wizard on first launch walks you through connecting services, configuring notifications, and adding the menu bar widget; when both services are connected, asks which to show in the menu bar
- **Single-service layout** — the popover adapts its width and layout when only one service is enrolled; no wasted space or placeholder columns
- **Sign in with ChatGPT / Claude** — OAuth via browser session, tokens stored securely in Keychain
- **Notifications** — per-service master switches let you silence all alerts for a service at once; individual thresholds at 15%, 5%, limit reached, and quota reset; time-has-passed logic prevents spurious alerts from rolling-window drift
- **Auto-update** — checks for a new version silently on every launch and twice daily via Sparkle; uses gentle reminders so update alerts never steal focus from your active app

---

## Requirements

- macOS 15 (Sequoia) or later
- An OpenAI account with Codex access (Plus, Pro, or Team plan)
- A Claude.ai account (Pro or Max plan) for Claude Code quota

---

## Installation

1. Download `AIQuota.zip` from the [latest release](https://github.com/niederme/ai-quota/releases/latest)
2. Unzip and move **AIQuota** to your Applications folder
3. Launch AIQuota — it appears in your menu bar, not the Dock
4. Follow the guided setup to connect your ChatGPT and/or Claude account

> Notarized by Apple — no Gatekeeper warning on first launch.

---

## Building from Source

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/niederme/ai-quota.git
cd ai-quota
xcodegen generate
open AIQuota.xcodeproj
```

Build and run the `AIQuota` scheme targeting **My Mac**.

---

## Project Structure

```
ai-quota/
├── Packages/
│   └── AIQuotaKit/          # Shared Swift Package (models, networking, storage)
│       └── Sources/AIQuotaKit/
│           ├── Models/      # CodexUsage, ClaudeUsage, AppSettings
│           ├── Networking/  # OpenAIClient, ClaudeClient, AuthManagers, NetworkError
│           ├── Notifications/ # NotificationManager
│           └── Storage/     # KeychainStore, SharedDefaults
├── AIQuota/                 # Main app target (MenuBarExtra)
│   ├── Views/               # PopoverView, MenuBarIconView, SettingsView
│   └── ViewModels/          # QuotaViewModel
└── AIQuotaWidget/           # WidgetKit extension
    ├── Provider/            # QuotaTimelineProvider
    ├── WidgetIntent.swift   # AppIntent for per-widget service selection
    └── Views/               # WidgetSmallView, WidgetMediumView
```

---

## Releasing

See the pre-release checklist at the top of [`scripts/release.sh`](scripts/release.sh). The short version:

1. Update `README.md` (features, requirements, roadmap) — **always do this first**
2. Bump `MARKETING_VERSION` in `project.yml`, then run `xcodegen generate`
3. Archive in Xcode (`Product → Archive`) and export the notarized `.app` to `~/Desktop/AIQuota.app`
4. Run `./scripts/release.sh <version>`

---

## Roadmap

- [ ] iOS / iPadOS app — native app and home screen widgets for iPhone and iPad
- [ ] Settings is cramped — too much scrolling, notifications lack hierarchy; needs a structural pass
- [ ] Debug / release auth-state clarity — make it explicit whether Xcode builds share sign-in state with the installed release app, and add a clean testing mode if needed
- [ ] Menu bar icon monochrome mode — option to disable amber/red status colours for a cleaner, always-white icon
- [ ] Gemini quota support (Google AI plans)
- [x] Single-service layout — popover adapts width and layout when only one service is enrolled
- [x] Menu bar preference in onboarding — when both services are connected, setup asks which to show in the menu bar
- [x] Stable popover layout — Connect button sits inside the gauge arc when a service needs to reconnect; no layout shifts
- [x] Guided onboarding — step-by-step setup wizard on first launch; replayable from Settings
- [x] Per-service notification switches — master toggle per service; sub-thresholds collapse when disabled
- [x] Dual-arc gauge — concentric rings for 5h and 7-day windows; color-coded purple → amber → red; both percentages labelled in the centre
- [x] Widget redesign — dual-arc gauge in small and medium widgets; medium always shows both services; refresh button on each widget
- [x] Network recovery — NWPathMonitor detects coming back online and refreshes immediately
- [x] Claude Code support — 5h and 7-day windows, Max plan credits, reset timers
- [x] Harmonized window display — both Codex and Claude lead with the 5-hour rate-limit window, with 7-day usage always shown as a secondary row
- [x] Widget service picker — choose Codex or Claude Code per widget instance
- [x] Notifications — below 15%, below 5%, limit reached, quota reset; rolling-window drift no longer triggers spurious alerts
- [x] Check for Updates — manual + silent auto-check on launch and twice daily via Sparkle, with gentle reminders

---

## License

MIT with [Commons Clause](https://commonsclause.com). Free to use, modify, and distribute — commercial or proprietary use is not permitted.
