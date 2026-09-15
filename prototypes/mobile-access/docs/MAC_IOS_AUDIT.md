# Mac and iOS comparison, September 14, 2026

Status: proposal only. No audit-driven product changes are included in the build-19 deployment, which contains the requested onboarding button and notification grouping fixes.

## Evidence and limits

Reviewed the five owner-provided Mac/iOS onboarding comparisons, recent iOS overview/account/widget screenshots, and current implementations on both platforms. Attempts to capture the installed Mac app through Computer Use timed out. Consequently this is a screenshot-and-source audit, not a completed live visual audit of all Mac states. Current iOS grouping/button changes also await the owner's build-19 review. Financial values in examples are illustrative, not a live account comparison.

## First proposal: organize the overview around two clear tasks

The Mac places reset captions with the gauges, then separates billing information below them with a rule. iOS puts reset blocks and billing into one narrow column alongside each gauge. That column has multiple text styles and wraps short labels despite spare width. Reserving space fixed the refresh jump but did not establish a good hierarchy.

Recommended iOS adaptation:

- Keep vertically stacked, equal-height service cards.
- Left column: gauge, service name, then two compact reset captions. This follows the Mac's grouping of usage and time.
- Right column: billing metadata, top aligned. Give this area the full remaining width and an explicit label/value layout. Normal-size labels stay on one line; monetary values use aligned digits. Use `Spent` instead of `This month`, with the monthly/estimated explanation available on demand as on the Mac.
- Use one quiet vertical rule between usage and billing. Give each card a stable freshness footer; allow blank space above the footer. Keep per-service timestamps because fetches can succeed independently.
- Put actionable connection warnings across the card, outside the billing rows. Keep stale data visibly distinct.
- At accessibility sizes, stack the sections rather than compressing text or clipping values.

Important correction: the Mac's actual CompactStatRow is an inline label/value row, not a trailing-aligned two-column table. The proposed iOS table is a phone adaptation, not a claim of exact parity.

Sources: `AIQuota/Views/PopoverView.swift` (gaugeRow, statsRow, CompactStatRow, footer), `AIQuota/Views/CircularGaugeView.swift` (caption), `App/OverviewView.swift` (ProviderDialCardContent).

## Other findings and proposed decisions

| Area | Observed difference | Proposal |
|---|---|---|
| Naming | Mac uses Claude Code; iOS overview/settings/account titles use Claude in several places, while onboarding/widgets use Claude Code. | Use a shared display-name definition for service labels; retain natural provider wording inside sign-in instructions. |
| Brand | Mac separates BrandAccent for controls from systemPurple for gauges. iOS uses systemPurple for onboarding controls. | Match the Mac's semantic color roles and shared assets. Do not assume one purple serves every purpose. |
| Freshness | iOS Claude account page labels every reading Last saved usage, even after success. Settings says Updating while overview says Refreshing. | Current usage for healthy data, Last saved usage for failures; standardize refresh wording and relative timestamps. |
| Notifications | Mac onboarding has Reset alert checkboxes; Mac Settings has Off / Only near the limit / Every reset. iOS uses one controls view for onboarding and Settings. | Reuse the Mac's richer controls within Mac onboarding, keeping details collapsed. Share policy wording and defaults across platforms. |
| Notification copy | iOS subtitle only mentions reset reminders although usage alerts are also available. | Adopt the Mac's Choose which alerts you'd like to receive. Keep estimated-reset caveats beside the relevant controls. |
| Billing explanations | Mac exposes contextual explanations for estimated Codex spending and Claude usage-credit totals; iOS shows amounts without that context. | Add concise on-demand explanations. Do not put long provider caveats back into the main card. |
| Missing data | Mac reset formatter can turn an unknown timestamp into soon; iOS explicitly reports unavailable. | Preserve iOS's honest unavailable state and consider bringing it to Mac. Do not copy misleading fallback wording for parity. |
| Metadata availability | Mac shows Claude plan; current mobile ClaudeAPI explicitly constructs metadata with plan nil. | Treat as a data-availability investigation, not a layout omission. Never invent a plan or pull in another device's account data. |
| Widget semantics | Remaining means weekly remaining for Codex but five-hour remaining for Claude. | Label the window explicitly wherever Remaining appears. This is still proposed, not implemented. |

Sources: `AIQuota/Views/AdaptiveColors.swift`, `AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift`, `AIQuota/Views/SettingsView.swift`, `Packages/AIQuotaKit/Sources/AIQuotaKit/Formatting/ResetTimeTextFormatter.swift`, `App/MobileSettingsView.swift`, `App/ClaudeProbeView.swift`, `Core/Sources/MobileAccessCore/ClaudeAPI.swift`, `Shared/HomeQuotaView.swift`.

## How to prevent drift

Maintain one parity checklist for copy, color roles, button hierarchy, window labels, notification policy, and connection states. Share semantic definitions and formatters where practical; keep platform-specific layout and delivery behavior explicit.

Before approval, compare Mac and iOS with equivalent fixture data for: both healthy services; sparse metadata; long billing values; refreshing; unavailable resets; stale saved readings; reconnect required. Review light/dark and normal/accessibility type. Verify no ordinary refresh height changes, no wrapped short labels at normal phone sizes, no fictional values, and clear window ownership in notifications.

Suggested order: overview layout prototype for owner review; shared copy/state vocabulary and billing explanations; Mac notification onboarding parity; then a live cross-platform visual review. The recently requested iOS onboarding fixes can be checked independently in build 19.

## Implementation checkpoint

Implemented locally: two-column overview with reset captions under the gauge,
trailing-aligned billing values and a stable footer; full-width connection notices;
responsive stacked layout; Claude Code naming in overview/settings/account title;
Current usage versus Last saved usage on the Claude account; notification subtitle
covering all alerts; explicit 5h/7d left widget labels. Mac onboarding now reuses
Settings' NotificationInlineControls, including reset modes and thresholds.

First validation: 29 iOS hosted tests passed (including equal-height, refreshing,
missing metadata, and accessibility cases); Mac Debug build passed. A final iOS
run checks the shortened reset captions. Review remains needed on a device before
release. No archive or upload of these audit changes was requested or performed.

Still unfinished: shared brand-color assets and broader display-name/formatter
consolidation; contextual billing explanations; investigation of Claude plan
availability; Mac unavailable-reset wording; live Mac capture and equivalent-state
visual review. Stop this window before 85% usage, then resume these items when
there is capacity and authorization to continue. Build 19 predates this audit work.


## Upgrade recovery and stable error layout (September 14)

Build 20 reached TestFlight before this follow-up. The following changes are local
and are not included in build 20:

- Codex retries a rejected, unexpired access token by renewing once under the
  shared app/widget credential lease. A second 401 stops recovery and preserves
  cached usage; revoked refresh grants request reconnection.
- Codex exposes the persisted connection state on overview and promotes Reconnect
  on the account screen when required.
- Connection messages occupy the reserved card footer instead of inserting a
  header. Healthy, refreshing, empty, and error states retain the same height.
- Both platforms display the provider's `prolite` plan as Pro, retaining the raw
  value in data. Weekly-only responses keep the five-hour metric absent.
- Mac distinguishes reported usage without a reset date from an absent window.
  Missing reset dates are unavailable; expired dates are unconfirmed, including
  mobile widgets. Neither condition promises an imminent reset.

Validation: 31 MobileAccessCore tests and 146 AIQuotaKit tests pass. Hosted iOS
recovery/layout tests pass; rendered normal and enlarged-type fixtures reviewed.
Live iOS recovery still needs the next TestFlight build and phone verification.
This supersedes the earlier full-width connection notices and unavailable-reset
wording listed above.


Mac reset-date follow-up: the September 14, 2:50 PM cached reading reports
weekly reset September 21 at 2:27 PM, with 603467 seconds remaining. The screenshot
was ambiguous because it showed only Monday and the time, not an expired provider
date. Reset captions at least seven calendar days away now include month and day
(e.g. Mon. Sep 21 2:27pm). The regression test uses these exact dates. This is a
cache/source verification, not a new live provider request or an installed Mac
update.
