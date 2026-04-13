# AIQuota

A native macOS menu bar app for monitoring AI coding quota. Track [OpenAI Codex](https://openai.com/codex) and [Claude Code](https://claude.ai) from the menu bar and desktop widgets without living in a browser tab.

The marketing site in `docs/` follows the shared Codex web preview convention using `/Users/niederme/.codex/bin/codex-preview-env`. The canonical global convention lives at `/Users/niederme/.codex/docs/web-preview-convention.md`.

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
- **Adaptive refresh controls** — choose `Auto` to refresh every minute when the app is active or quota is near a threshold, then back off automatically when idle, offline, or on low power
- **Guided onboarding** — first launch walks through connecting services, refresh preferences, notifications, and widget setup; if both services are connected, onboarding also asks which one should drive the menu bar icon
- **Single-service adaptation** — when only one service is enrolled, the app and widgets avoid dead space instead of pretending there should be a second column
- **ChatGPT and Claude sign-in** — authenticates using your existing browser-backed session, with secrets stored in Keychain and shared widget data kept in the app group
- **Notification controls** — per-service master switches plus consolidated threshold alerts (one toggle covers low quota, critical quota, and limit reached) plus reset events
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

## Website Preview

The lightweight website for `aiquota.app` lives in `docs/`.

From the repo root:

```bash
make
```

That serves `docs/` on all interfaces, opens the site locally, and prints:

- a `.local` URL for this Mac
- a LAN URL for other devices on the same network

Default preview port is `8123`. If that port is already in use, `make dev` automatically picks the next available port.

Localhost-only preview:

```bash
make dev-local
```

Worktree-friendly preview:

```bash
make dev-thread
```

`make dev-thread` starts from `8124` so the main checkout can keep `8123`.

Project worktrees should live under repo-local `.worktrees/`.

### Live Reload

Use `make dev-live` for the standard live-reload preview. The underlying switch is `LIVE=1`, which is also available for the thread and local-only variants:

```bash
make dev-live
make dev-live-thread
make dev-local LIVE=1
```

Live reload watches:

- `docs/**/*.html`
- `docs/**/*.css`
- `docs/assets/**/*`

Requirements for live reload:

- Node.js with `npx` available
- a Node runtime that supports `node:path`
- recommended local version: Node 24

### Website Deploy

Pushing to `main` triggers the website deploy workflow automatically, and you can also run the same deploy manually with `workflow_dispatch` in GitHub Actions. The workflow:

- minifies `docs/site.css` and `docs/site.js`
- smoke-checks the public site pages before deploy, including release-page sync against GitHub
- stages the `docs/` site with cache-busted asset URLs
- syncs the staged site to the remote host over SSH
- normalizes remote file permissions so shared hosting serves the site correctly

For manual or local deploys, use:

```bash
./scripts/deploy-site.sh
```

Smoke-check the site before deploy:

```bash
./scripts/check-site-pages.sh
```

Default deploy settings in [`scripts/deploy-site.sh`](scripts/deploy-site.sh):

- `DEPLOY_HOST=ssh.suckahs.org`
- `DEPLOY_USER=suckahs`
- `DEPLOY_PATH=/home2/suckahs/public_html/aiquota`
- `SITE_URL=https://aiquota.app`

Optional overrides:

- `DEPLOY_PORT`
- `DRY_RUN=1`
- `DEPLOY_IDENTITY_FILE`

GitHub Actions expects the repository secret `SSH_PRIVATE_KEY` to contain the deploy key for `suckahs@ssh.suckahs.org`.

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
2. Bump `MARKETING_VERSION` in `project.yml`
3. Run `./scripts/bump-build.sh` to increment `CURRENT_PROJECT_VERSION` and regenerate the Xcode project
4. Archive in Xcode (`Product → Archive`) and export the notarized `.app` to `~/Desktop/AIQuota.app`
5. Run `./scripts/release.sh <version>`
6. Verify `docs/releases/index.html` matches the GitHub releases list, run `./scripts/check-site-pages.sh`, then push the site/appcast updates to `main`

---

## Roadmap

- [ ] iOS / iPadOS app — native app and home screen widgets for iPhone and iPad
- [ ] Gemini quota support (Google AI plans)
- [ ] Menu bar icon monochrome mode — option to disable amber/red status colours for a cleaner, always-white icon
- [x] Marketing website — `aiquota.app` is live with download, releases, and policy pages plus automated deploys from `main`
- [x] Visualize 7-day quota reset timing — the app now surfaces 7-day reset timing when the weekly window enters the warning range
- [x] Settings restructured — Accounts section promoted to the top; notification sections named per service with threshold alerts consolidated into a single toggle per window
- [x] Auth and widget recovery after updates — widgets recover more reliably after app replacements, refresh more aggressively, and valid Claude/Codex sessions now restore automatically instead of showing stale Connect states
- [x] Widget variations — configurable single-service medium widget plus a large two-service overview
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
