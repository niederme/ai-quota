# AIQuota

A native macOS menu bar app for monitoring AI coding quota. Track [OpenAI Codex](https://openai.com/codex) and [Claude Code](https://claude.ai) from the menu bar and desktop widgets without living in a browser tab.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

![hero-composite-screenshot-current](https://github.com/user-attachments/assets/78428686-f724-4d02-8cae-24621e227675)


---

## Features

- **Menu bar gauge** — a compact, color-coded arc icon that tracks the selected service and shifts from purple to amber to red as you approach the limit
- **Popover dashboard** — Codex and Claude Code both use the same dual-arc gauge language: the 5-hour window is the outer ring, the 7-day window is the inner ring
- **Service details that matter** — reset timers, plan info, credits or extra usage, and clear warning states are visible at a glance
- **Desktop widgets** — polished widget variants for single-service and dual-service monitoring, including configurable small and medium widgets plus a large two-service layout
- **Graceful empty and loading states** — widgets and the popover keep a stable layout when a service is disconnected, restoring, or waiting on fresh data
- **Guided onboarding** — first launch walks through connecting services, notifications, and widget setup; if both services are connected, onboarding also asks which one should drive the menu bar icon
- **Single-service adaptation** — when only one service is enrolled, the app and widgets avoid dead space instead of pretending there should be a second column
- **ChatGPT and Claude sign-in** — authenticates using your existing browser-backed session, with secrets stored in Keychain and shared widget data kept in the app group
- **Notification controls** — per-service master switches plus threshold alerts for low quota, critical quota, limit reached, and reset events
- **Recovery after updates** — widget timelines reload more aggressively on launch, and installed widgets recover more reliably after app replacements
- **Auto-update** — Sparkle checks silently on launch and twice daily, with gentle reminders instead of intrusive prompts

---

## Widget Lineup

- **Small** — one service, configurable per widget instance
- **Medium (single-service)** — one service with a larger gauge and detail column
- **Medium (two-service)** — Codex and Claude Code side by side
- **Large** — two-service overview with larger gauges and a dedicated detail row

Widgets refresh automatically from cached data, app-driven reloads, and background timeline updates. If macOS ever leaves a pinned widget stuck in a stale state after an update, removing and re-adding that widget instance usually clears the cached archive.

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

If you are iterating on widgets, launching the built app once after install helps WidgetKit pick up new timelines and layouts.

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
    └── Views/               # WidgetSmallView, WidgetMediumView, WidgetGaugeView
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

- [x] Visualize 7-day quota reset timing — the app now surfaces 7-day reset timing when the weekly window enters the warning range
- [ ] Settings is cramped — too much scrolling, notifications lack hierarchy; needs a structural pass
- [x] Auth and widget recovery after updates — widgets recover more reliably after app replacements, refresh more aggressively, and valid Claude/Codex sessions now restore automatically instead of showing stale Connect states
- [x] Widget variations — configurable single-service medium widget plus a large two-service overview
- [ ] iOS / iPadOS app — native app and home screen widgets for iPhone and iPad
- [ ] Gemini quota support (Google AI plans)
- [ ] Menu bar icon monochrome mode — option to disable amber/red status colours for a cleaner, always-white icon
- [x] Menu bar preference fully respected — the menu bar icon now follows the selected service for both gauge values and warning colour
- [x] Single-service layout — popover adapts width and layout when only one service is enrolled
- [x] Menu bar preference in onboarding — when both services are connected, setup asks which to show in the menu bar
- [x] Stable popover layout — Connect button sits inside the gauge arc when a service needs to reconnect; no layout shifts
- [x] Guided onboarding — step-by-step setup wizard on first launch; replayable from Settings
- [x] Per-service notification switches — master toggle per service; sub-thresholds collapse when disabled
- [x] Dual-arc gauge — concentric rings for 5h and 7-day windows; color-coded purple → amber → red; both percentages labelled in the centre
- [x] Widget redesign — dual-arc gauges, single-service and dual-service widget variants, improved placeholder states, and more resilient rendering after updates
- [x] Network recovery — NWPathMonitor detects coming back online and refreshes immediately
- [x] Claude Code support — 5h and 7-day windows, Max plan credits, reset timers
- [x] Harmonized window display — both Codex and Claude lead with the 5-hour rate-limit window, with 7-day usage always shown as a secondary row
- [x] Widget service picker — choose Codex or Claude Code per widget instance
- [x] Notifications — below 15%, below 5%, limit reached, quota reset; rolling-window drift no longer triggers spurious alerts
- [x] Check for Updates — manual + silent auto-check on launch and twice daily via Sparkle, with gentle reminders

---

## License

MIT with [Commons Clause](https://commonsclause.com). Free to use, modify, and distribute — commercial or proprietary use is not permitted.
