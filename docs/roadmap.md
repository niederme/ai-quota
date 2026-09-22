# Roadmap

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

**Beta via TestFlight.** The iPhone and iPad app is now part of the shared
`AIQuota.xcodeproj`, using the `AIQuota-iOS` scheme. Public TestFlight enrollment
is not currently listed here.

**Implemented**

- [x] Independent Codex and Claude sign-in, device-only credential storage, session renewal, and reconnect flows.
- [x] Dual-ring service cards with percentages, reset times, reading age, and reported account metadata.
- [x] Missing quota values use secondary-gray N/A across apps and widgets. Spending rows are fully tappable, with inline info icons and Mac-matching popover copy.
- [x] Configurable Lock Screen widgets and four Home Screen layouts for individual or paired services.
- [x] Foreground refresh controls, pull-to-refresh, and background widget refresh requests, subject to iOS scheduling.
- [x] Per-service and per-window alert controls, including approaching-limit alerts, limit-reached alerts, and estimated reset reminders.
- [x] Guided onboarding, Guided Setup replay, and Reset All Settings.
- [x] Shared Xcode project with separate platform schemes and independent version/build settings.
- [x] Scripted TestFlight archive, upload, and processing checks. See the [release workflow](../iOS/README.md#testflight-release-workflow).

This list describes the current codebase. Build-specific release and device-validation
history lives in the [iOS development history](../iOS/HISTORY.md).

**Beta priorities**

- [ ] Validate layouts and onboarding on smaller and larger phones, iPad, landscape, and accessibility text sizes.
- [x] Keep card heights stable during refresh, metadata loss, and connection recovery, including accessibility text sizes.
- [ ] Investigate reported slow or blank launches and associated crash reports.
- [ ] Measure widget freshness and session renewal on real devices, including after resets and connectivity changes.
- [ ] Verify Home Screen widget gallery placement, tinting, and notification permission/delivery behavior on devices.
- [ ] Confirm physical-device reinstall/reset behavior and onboarding replay.
- [ ] Broaden account metadata validation across plans. Codex metadata and Claude usage credits have appeared on the owner's phone; Claude plan refresh now uses the connected account's profile; balance remains unavailable. Live plan-change verification is pending.

**Later**

- [x] Optional anonymous analytics with explicit consent in Settings and guided setup, matching Mac. Release builds require the local Firebase configuration.

### Shared exploration

- [ ] Usage history across the day and week, with gaps and changing allowances handled explicitly.
- [ ] Insightful sentence summaries that add context beyond the gauges, such as recurring busy weekdays or approaching limits. Consider local models once there is enough reliable history.
- [ ] Evaluate CloudKit for sharing timestamped readings between a person's Mac and phone, with explicit provider-account matching and no credential syncing.
- [ ] Investigate Gemini quota support before committing to an integration.

### App Intents backlog (Mac + iOS)

Deferred plan, saved September 14, 2026. Start with useful Shortcuts actions;
keep names, parameters, and result meanings consistent across Mac and iOS.
Existing widget configuration intents do not complete this backlog.

**First release**

- [ ] **Get Usage:** select Codex or Claude; return structured 5-hour and weekly usage, reset dates, and the last-updated time. Keep an absent window explicitly “not reported,” never zero or unlimited.
- [ ] **Refresh Usage:** reuse existing authentication, token recovery, and refresh handling; return the resulting reading or a clear failure with saved-data freshness.
- [ ] Add ready-made **Check Codex** and **Check Claude** App Shortcuts, with concise spoken and visual summaries where supported.

**Acceptance**

- [ ] Verify actions in Shortcuts on both platforms, including execution without opening AIQuota where supported.
- [ ] Verify structured results can feed conditions and subsequent actions in a custom shortcut.
- [ ] Verify healthy, stale, missing-window, offline, and reconnect-required states without presenting saved values as fresh.
- [ ] Verify spoken responses and visual summaries on supported system surfaces; distinguish Shortcuts, App Shortcuts, Spotlight, and Siri support based on observed behavior.

**Later**

- [ ] Configure reset reminders and pause alerts through intents.
- [ ] Explore Spotlight and Siri search/open integration for service accounts.
- [ ] After public release and verified support, submit to [Siri AI Apps](https://siriaiapps.com/submit). Its [review criteria](https://siriaiapps.com/how-we-review) distinguish Shortcuts from Siri AI support and TestFlight from public-release availability.

Implementation notes: [iOS development and testing](../iOS/README.md) and [Mac distribution](mac-distribution.md).
