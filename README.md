# AIQuota

A native macOS menubar utility to monitor your AI coding quota — track [OpenAI Codex](https://openai.com/codex) and [Claude Code](https://claude.ai) usage at a glance, without opening a browser.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

<img width="400" alt="AIQuota menubar popover" src="https://github.com/user-attachments/assets/e76381d7-3d71-4ecc-aee5-3309c65a7e93" /><img width="400" alt="AIQuota Widgets" src="https://github.com/user-attachments/assets/3a74348c-fe52-4344-ac73-8269206b1eb7" />

---

## Features

- **Menubar gauge icon** — color-coded arc gauge showing quota consumption at a glance
- **Codex + Claude Code** — both services on a single scrollable sheet with usage bars, reset timers, and plan badges
- **Widget service picker** — small and medium desktop widgets; right-click to choose Codex or Claude Code per instance
- **Auto-refresh** — background polling with manual refresh button
- **Sign in with ChatGPT / Claude** — OAuth via browser session, tokens stored securely in Keychain
- **Notifications** — alerts at 15%, 5%, and when your limit is reached or resets
- **Auto-update** — silently checks for a new version on every launch via Sparkle

---

## Requirements

- macOS 26 (Tahoe) or later
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

Requires Xcode 26 beta and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/niederme/ai-quota.git
cd ai-quota
xcodegen generate
open AIQuota.xcodeproj
```

Build and run the `AIQuota` scheme.

---

## Project Structure

```
ai-quota/
├── Packages/
│   └── AIQuotaKit/          # Shared Swift Package (models, networking, storage)
│       └── Sources/AIQuotaKit/
│           ├── Models/      # CodexUsage, ClaudeUsage, AppSettings
│           ├── Networking/  # OpenAIClient, ClaudeClient, AuthManagers, NetworkError
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

## Roadmap

- [ ] Gemini quota support (Google AI plans)
- [x] Claude Code support — 5h and 7-day windows, Max plan credits, reset timers
- [x] Widget service picker — choose Codex or Claude Code per widget instance
- [x] Notifications — below 15%, below 5%, limit reached, quota reset
- [x] Check for Updates — manual + silent auto-check on launch via Sparkle

---

## License

MIT with [Commons Clause](https://commonsclause.com). Free to use, modify, and distribute — commercial or proprietary use is not permitted.
