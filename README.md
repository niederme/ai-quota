# AIQuota

A native macOS menubar utility to monitor your AI coding quota — track [OpenAI Codex](https://openai.com/codex) and [Claude Code](https://claude.ai) usage at a glance, without opening a browser.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

<img alt="AIQuota App & Widgets" src="https://github.com/user-attachments/assets/ff816ffb-7b02-41d3-a688-53f775d0fa86" />


---

## Features

- **Menubar gauge icon** — color-coded arc gauge showing quota consumption at a glance; tracks whichever service you configure (or falls back to whichever is authenticated)
- **Codex + Claude Code** — both services on a single scrollable sheet, each showing a **5-hour window** as the primary gauge and a **7-day window** as a secondary row, with reset timers and plan badges
- **Widget service picker** — small and medium desktop widgets; right-click to choose Codex or Claude Code per instance
- **Auto-refresh** — background polling with manual refresh button
- **Sign in with ChatGPT / Claude** — OAuth via browser session, tokens stored securely in Keychain
- **Notifications** — alerts at 15%, 5%, and when your limit is reached or resets; uses time-has-passed logic so rolling window drift never triggers spurious alerts
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
4. Click the icon and sign in with your ChatGPT and/or Claude account

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
2. Bump `MARKETING_VERSION` in Xcode and archive (`Product → Archive`)
3. Export the notarized `.app` to `~/Desktop/AIQuota.app`
4. Run `./scripts/release.sh <version>`

---

## Roadmap

- [ ] Circular gauge layout — replace the linear bar with a circular arc gauge for a denser, at-a-glance view of both windows
- [ ] Gemini quota support (Google AI plans)
- [x] Claude Code support — 5h and 7-day windows, Max plan credits, reset timers
- [x] Harmonized window display — both Codex and Claude lead with the 5-hour rate-limit window, with 7-day usage always shown as a secondary row
- [x] Widget service picker — choose Codex or Claude Code per widget instance
- [x] Notifications — below 15%, below 5%, limit reached, quota reset; rolling-window drift no longer triggers spurious alerts
- [x] Check for Updates — manual + silent auto-check on launch and twice daily via Sparkle, with gentle reminders

---

## License

MIT with [Commons Clause](https://commonsclause.com). Free to use, modify, and distribute — commercial or proprietary use is not permitted.
