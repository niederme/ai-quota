# Settings and Onboarding UI Handoff

Last updated: July 2, 2026

## Status

Continue from `main`. The current UI pass is implemented in app code and backed
by lightweight source-shape tests.

Implemented:

- Settings combines account connection state and diagnostics into one
  `Accounts` group.
- Notifications use one master group, per-service inline disclosure rows, and
  checkbox controls for detailed alert choices.
- Onboarding mirrors the Settings notification hierarchy instead of using the
  older card-per-service layout.
- The menu bar display picker supports Codex, Claude Code, or Both when both
  services are connected.
- The double menu bar icon is one menu bar item and one click target. The two
  gauges are visually paired with a small internal gap rather than split into
  separate status items.
- The popover uses system material, semantic foreground styles, tertiary gauge
  tracks, and system red/orange/purple colors for status accents.

## Code Map

Start here:

```text
AIQuota/Views/SettingsView.swift
AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
AIQuota/Views/Onboarding/Steps/ServicesStepView.swift
AIQuota/Views/MenuBarIconView.swift
AIQuota/Views/PopoverView.swift
AIQuota/Views/CircularGaugeView.swift
AIQuota/Views/AdaptiveColors.swift
Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift
```

Related tests:

```text
Packages/AIQuotaKit/Tests/AIQuotaKitTests/NotificationPreferencesNormalizationTests.swift
Packages/AIQuotaKit/Tests/AIQuotaKitTests/AnalyticsConsentSettingsTests.swift
Packages/AIQuotaKit/Tests/AIQuotaKitTests/PopoverTypographyTests.swift
Packages/AIQuotaKit/Tests/AIQuotaKitTests/RefreshSettingsTests.swift
```

## Interaction Decisions

- Settings notification service rows are clickable disclosure rows with a
  separate service enable switch. The row affordance expands details; the switch
  only changes the service's enablement.
- Only connected/enrolled services appear in notification settings.
- Detailed notification choices use checkboxes, not switches, so the service
  switch remains the visual master control.
- Account health text should stay quiet in the normal state: green dot, gray
  copy. HTTP details belong in Copy Diagnostics, not the visible row.
- Popover service names use semantic foreground color. Do not hardcode white or
  black labels to rescue one appearance mode.
- Reset captions and gauge accents use macOS system colors through
  `AdaptiveColors.swift`. Avoid bringing back literal purple/orange/red values
  for the active popover surface.

## Verification

Before handing off another UI pass, run:

```bash
swift test --package-path Packages/AIQuotaKit --no-parallel
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -configuration Debug -destination 'platform=macOS' build
git diff --check
```

For visual review, check these states in light and dark appearances:

- one service connected
- both services connected with `Menu bar display` set to `Both`
- notification master switch off
- notification master switch on with each service expanded
- disconnected service in the popover
