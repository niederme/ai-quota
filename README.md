# AIQuota

Native apps for monitoring AI coding quota on Mac and iPhone. Track [OpenAI Codex](https://openai.com/codex) and [Claude Code](https://claude.ai) with paired gauges for five-hour and seven-day allowances.

**Mac:** available through [GitHub releases](https://github.com/niederme/ai-quota/releases/latest), with menu bar monitoring and desktop widgets. **iOS:** in TestFlight testing, with independent account connections and Lock Screen widgets. Public TestFlight enrollment is not currently listed here.

The marketing site in `docs/` follows the shared Codex web preview convention using `/Users/niederme/.codex/bin/codex-preview-env`. The canonical global convention lives at `/Users/niederme/~Repos/ai-dotfiles/codex/docs/web-preview-convention.md`.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

![hero-composite-screenshot-current](https://github.com/user-attachments/assets/78428686-f724-4d02-8cae-24621e227675)


---

## Mac Features

- **Menu bar gauge** — compact, color-coded arc icons that show both Codex and Claude Code together by default when both services are connected
- **Popover dashboard** — Codex and Claude Code share the same dual-arc gauge language: the 5-hour window is the outer ring when reported, and the 7-day window remains on the inner ring
- **Service details that matter** — reset timers, plan info, credit balances, Claude usage-credit spend, and clear warning states are visible at a glance
- **Desktop widgets** — polished widget variants for single-service and dual-service monitoring, including configurable small and medium widgets plus a large two-service layout
- **Graceful empty and loading states** — widgets and the popover keep a stable layout when a service is disconnected, restoring, or waiting on fresh data
- **Adaptive refresh controls** — choose `Auto` for a five-minute baseline that speeds up to every minute while usage is changing or near a threshold, then backs off when the Mac is idle, offline, or on low power
- **Guided onboarding** — first launch walks through connecting services, menu bar display, refresh preferences, notifications, and widget setup
- **Single-service adaptation** — when only one service is enrolled, the app and widgets avoid dead space instead of pretending there should be a second column
- **ChatGPT and Claude sign-in** — reuses an existing Claude Code or Codex CLI login when available, and fully supports browser-backed sessions for people who use Claude on the web (including Google sign-in and Cloudflare verification); app authentication comes only from live OAuth or WebKit sessions, while widget credentials are stored separately for background refresh
- **Notification controls** — a single notifications group with a master switch, per-service disclosure rows, and Mac-style checkbox controls for detailed alert choices
- **Quiet account diagnostics** — Settings combines account status and redacted diagnostics so each service shows whether it is connected without duplicating developer-only HTTP details
- **Recovery after updates** — Codex and Claude Code sessions silently reconnect from accessible CLI credentials or web sessions after app replacements without presenting background Keychain prompts, and widget timelines reload more aggressively on launch
- **Auto-update** — Sparkle checks silently on launch and twice daily, marking available updates with an amber menu-bar badge instead of an intrusive prompt

---

## Mac Widget Lineup

- **Small** — one service, configurable per widget instance
- **Medium (single-service)** — one service with a larger gauge and detail column
- **Medium (two-service)** — Codex and Claude Code side by side
- **Large** — two-service overview with larger gauges and a dedicated detail row

Widgets refresh automatically from cached data, app-driven reloads, and background timeline updates. If macOS ever leaves a pinned widget stuck in a stale state after an update, removing and re-adding that widget instance usually clears the cached archive.

---

## Claude Usage Credits

Claude plan limits and usage credits are separate meters. On Pro, pay-as-you-go models such as Fable 5 use credits without drawing from the 5-hour or 7-day plan windows; credits can also cover continued usage after included limits are exhausted. AIQuota keeps the plan gauges unchanged and shows monthly **Usage credits** spend as a separate row when the reported total is greater than zero.

Claude reports credit spending as one combined monthly total, so AIQuota does not invent a Fable-versus-overage breakdown. When both plan windows are idle while credit spending is nonzero, the popover clarifies that the spending is separate from plan limits. See [Claude Fable 5 on your plan](https://support.claude.com/en/articles/15424964-claude-fable-5-on-your-plan) for Anthropic's current plan rules.

---

## Mac Requirements

- macOS 15 (Sequoia) or later
- An OpenAI account with Codex access (Plus, Pro, or Team plan)
- A Claude.ai Pro or Max account for verified Claude Code quota support
- Team and Enterprise parsing/auth paths are implemented but remain field-unverified

---

## Mac Installation

1. Download `AIQuota.zip` from the [latest release](https://github.com/niederme/ai-quota/releases/latest). Sparkle updates use immutable, build-specific archives internally.
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

## Manual Test Handoffs

- [Settings and onboarding UI handoff](docs/settings-onboarding-ui-handoff.md) — current hierarchy, menu bar display rules, popover material/color choices, and verification commands.
- [Team auth field-test history](docs/team-auth-field-test-handoff.md) — failed attempts, fixes retained on `main`, and the remaining unverified account paths.
- [Claude Team test instructions](docs/jason-team-plan-test-instructions.md) — archived test procedure for a future tester with an accessible Team account.

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

For iOS TestFlight builds, use the [iOS release workflow](prototypes/mobile-access/README.md#testflight-release-workflow). The following steps are for direct Mac releases.

See the pre-release checklist at the top of [`scripts/release.sh`](scripts/release.sh). The short version:

1. Update `README.md` (features, requirements, roadmap) — **always do this first**
2. Bump `MARKETING_VERSION` in `project.yml`
3. Run `./scripts/bump-build.sh` to increment `CURRENT_PROJECT_VERSION` and regenerate the Xcode project
4. Archive in Xcode (`Product → Archive`) and export the notarized `.app` to `~/Desktop/AIQuota.app`
5. Run `./scripts/release.sh <version>`
6. Verify `docs/releases/index.html` matches the GitHub releases list, run `./scripts/check-site-pages.sh`, then push the site/appcast updates to `main`

---

## Roadmaps

The Mac app is the design reference for iOS: gauge proportions, typography, system colors and materials, labels, and visual hierarchy. Adapt layouts to each platform while keeping that shared language. These lists describe priorities, not release dates.

### Mac

- [ ] Finish testing the separate App Store distribution configuration while preserving direct downloads and Sparkle updates.
- [ ] Field-verify Claude Team and Enterprise support with accessible test accounts.
- [ ] Add an optional monochrome menu bar icon mode.
- [ ] Continue testing session recovery, widget freshness, and diagnostics across updates.

<details>
<summary>Completed Mac milestones</summary>

- [x] Balance layout: auto-reload status wraps below the balance when the Mac popover row is too narrow.
- [x] Marketing website — `aiquota.app` is live with download, releases, and policy pages plus automated deploys from `main`
- [x] Visualize 7-day quota reset timing — the app now surfaces 7-day reset timing when the weekly window enters the warning range
- [x] Settings restructured — Accounts and diagnostics are combined, notifications live in one master group, and service details expand inline with checkbox-level alert options
- [x] Google sign-in in the embedded login — OAuth popups (`window.open`) are now hosted in a child window, fixing the generic "There was an error logging you in" failure for Google-SSO accounts on both Claude and ChatGPT logins
- [x] Auth and widget recovery after updates — Codex and Claude Code reconnect from existing CLI credentials or web sessions after app replacements, widgets recover more reliably, and valid sessions restore automatically instead of showing stale Connect states
- [x] Widget variations — configurable single-service medium widget plus a large two-service overview
- [x] Menu bar display preference fully respected — the menu bar icon can show Codex, Claude Code, or a paired double gauge while remaining one clickable menu bar item
- [x] Single-service layout — popover adapts width and layout when only one service is enrolled
- [x] Menu bar preference in onboarding — when both services are connected, setup asks whether to show Codex, Claude Code, or both in the menu bar
- [x] Stable popover layout — Connect button sits inside the gauge arc when a service needs to reconnect; no layout shifts
- [x] Guided onboarding — step-by-step setup wizard on first launch; replayable from Settings
- [x] Per-service notification switches — master toggle per service; detailed alert options collapse inline and use checkbox controls for dense Mac settings
- [x] Dual-arc gauge — concentric tracks for 5h and 7-day windows; unavailable limits stay visibly honest instead of turning into fabricated percentages or reset times
- [x] Widget redesign — dual-arc gauges, single-service and dual-service widget variants, improved placeholder states, and more resilient rendering after updates
- [x] Network recovery — NWPathMonitor detects coming back online and refreshes immediately
- [x] Claude Code support — 5h and 7-day windows, Max plan credits, reset timers
- [x] Harmonized window display — both services retain stable 5-hour and 7-day tracks, while provider-specific unavailable windows are clearly identified
- [x] Widget service picker — choose Codex or Claude Code per widget instance
- [x] Notifications — below 15%, below 5%, limit reached, quota reset; rolling-window drift no longer triggers spurious alerts
- [x] Check for Updates — manual + silent auto-check on launch and twice daily via Sparkle, with an unobtrusive menu-bar badge and in-popover update action

</details>

### iOS

**Working in TestFlight 0.1.0 (8)**

- [x] Independent Codex and Claude sign-in, with credentials stored on the device.
- [x] Stacked service cards with dual-ring gauges, percentages, reset times, and reading age.
- [x] Lock Screen widgets: configurable single-service rings, paired gauges, paired percentages, and single-service details with matching gauge proportions.
- [x] Automatic session renewal, refresh on app activation, and background widget refresh requests. Actual refresh delivery remains subject to iOS scheduling and needs longer device testing.

- [x] Settings: Mac-aligned General, Accounts, Privacy, and About sections, foreground refresh intervals, last-updated status, and explicit reconnect actions.
- [x] Pull-to-refresh and a toolbar refresh button update both services.
- [x] Account metadata: reported Codex plan, balance, and monthly spending plus Claude usage credits.
- [x] Mac-style gauge key and reset colors, centered service names, and stable two-column cards with wrapping metadata.

**Next**

- [ ] Onboarding: clear sign-in steps, provider-specific setup requirements, and widget setup.
- [ ] UI polish: follow the Mac's typography, gauge key, spacing, materials, and color hierarchy; test smaller and larger screens, landscape, and accessibility text sizes.
- [ ] Launch reliability: investigate reported slow or blank launches and any associated crash reports.
- [ ] Background reliability: measure widget freshness and session renewal on real devices, including after resets and connectivity changes.

**Following**

- [ ] Home Screen widgets for one or both services.
- [ ] Reset notifications: help people return when an allowance is expected to reset, while distinguishing that estimate from confirmed availability.
- [ ] Broaden account metadata validation across plans. Codex metadata and Claude usage credits have appeared on the owner’s phone; Claude plan and balance are not available from the current mobile usage response.

### Shared exploration

- [ ] Usage history across the day and week, with gaps and changing allowances handled explicitly.
- [ ] Insightful sentence summaries that add context beyond the gauges, such as recurring busy weekdays or approaching limits. Consider local models once there is enough reliable history.
- [ ] Evaluate CloudKit for sharing timestamped readings between a person's Mac and phone, with explicit provider-account matching and no credential syncing.
- [ ] Investigate Gemini quota support before committing to an integration.

Implementation notes: [iOS development and testing](prototypes/mobile-access/README.md) and [Mac distribution](docs/mac-distribution.md).

---

## License

MIT with [Commons Clause](https://commonsclause.com). Free to use, modify, and distribute — commercial or proprietary use is not permitted.
