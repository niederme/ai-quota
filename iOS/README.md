# AI Quota for iOS

**Beta via TestFlight for iPhone and iPad.** See the [iOS roadmap](../README.md#ios)
for implemented features and remaining beta validation. Public TestFlight enrollment
is not currently listed here.

The iPhone/iPad app lives in `iOS/` and builds from the root `AIQuota.xcodeproj`
using the `AIQuota-iOS` scheme. It shares the Mac app's App Store Connect record. The Mac remains the design reference for typography, system colors,
materials, gauge proportions, and Settings language.

## Build 13 release history

**TestFlight 0.1.0 (13)** was confirmed valid and available for internal testing. The owner reviewed the
build and confirmed Claude stayed connected through its next token renewal.
This confirms one successful device renewal, not every long-running recovery case.

- Independent Codex and Claude sign-in, with device-only credential storage.
- Stacked cards with dual-ring gauges, reset times, cached-reading age, and reported
  plan, balance, monthly spending, or usage credits.
- General, Accounts, Privacy, and About settings; explicit Reconnect actions and
  last-successful-update timestamps.
- Pull-to-refresh and a toolbar refresh button for both services.
- Configurable circular, paired-gauge, paired-percentage, and single-service details
  Lock Screen widgets. Taps open the overview.
- Smaller logos in the individual circular and single-service details widgets.
  Service details uses a 56-point gauge, 12/14-point text, and a 5-point text gap.
  Paired-widget logos retain their existing size.
- Mac-style reset-caption emphasis without compounded secondary dimming.
- The accompanying Mac change lets auto-reload status wrap below the balance when
  the row is too narrow. It does not change payment or threshold behavior.

## Project and identities

Open [`AIQuota.xcodeproj`](../AIQuota.xcodeproj) from the repository root and select the `AIQuota-iOS` scheme.

The scheme builds `AIQuota-iOS` and its `AIQuotaWidget-iOS` extension, and runs
`AIQuota-iOSTests`. Shared iOS models and networking live in
[`Packages/MobileAccessCore`](../Packages/MobileAccessCore). The `iOS/project.yml`
file is included by the root spec; it is not a standalone project.

| Configuration | App identifier | Widget identifier |
| --- | --- | --- |
| Debug | `com.niederme.AIQuota` | `com.niederme.AIQuota.mobilewidget` |
| Release | `com.niederme.AIQuota` | `com.niederme.AIQuota.mobilewidget` |

Release belongs to the same App Store Connect app as macOS. Preserve the existing
App Group, shared Keychain groups, and legacy `aiquota-probe` URL scheme so updates
retain connections and widget routing. Debug and Release use the same identifiers,
so running from Xcode replaces the TestFlight app instead of installing a second
copy. The old prototype installation can be removed separately. The iOS app uses
the Mac's native Icon Composer asset.

## Authentication and recovery

Codex uses device-code sign-in. The user may need to enable device-code authorization
on the ChatGPT website under Security and login. The app links to that website in
an in-app browser; the corresponding control may not appear in the ChatGPT iOS app.

Claude uses browser authorization, PKCE, and manually pasted `code#state`.
State must match the current attempt, which expires after 15 minutes. The app
requests `org:create_api_key user:profile`; it does not request inference scope,
create API keys, send prompts, purchase credits, or redeem resets.

These connections use first-party public client identities, not an AIQuota provider
registration. Technical success and TestFlight availability do not establish
provider authorization or App Store approval.

Both app and widgets use one shared Keychain authority and a cross-process lease
around renewal and persistence. Rotated credentials are saved even if the subsequent
usage request fails. Reconnect retains the old credentials and reading until a new
sign-in succeeds. Disconnect explicitly removes the local connection and reading;
it does not revoke authorization at the provider.

Claude errors distinguish sign-in, renewal, and usage requests. A known
`invalid_grant` renewal response requests reconnection; other HTTP 400 responses
are not assumed to mean expired credentials. Raw response bodies and tokens are
never shown. The original build-7 HTTP 400 did not record its stage, so its cause
was subsequently narrowed to `invalid_scope`; build 13 omits the refresh scope
and the owner confirmed a successful renewal. Continue longer-running field tests.

## Refresh and cached readings

Opening the app checks for fresh usage, with a 15-second automatic-refresh guard.
Settings offers Auto/1/5/10/30 minutes while the app is active. Auto uses five minutes
normally and one minute at 85% usage or above. Unlike the Mac policy, it does not
track changing usage or Mac activity. iOS controls background widget delivery;
a requested five-minute timeline refresh is not a guaranteed interval.

App and widgets preserve the last successful reading and its original timestamp
after failures. Old readings retain normal Lock Screen styling. Reading age and
errors remain available in the app and accessibility descriptions. Missing windows
stay unavailable; no reset is inferred merely because an expected reset time passes.

Shared diagnostic records cover attempts, results, and timeline handoff. They do
not measure when someone looks at a widget or prove exactly when iOS displayed an entry.
There is no CloudKit relay, Mac activity signal, or credential sync in this release.

## Account metadata

Codex plan and balance come from its usage response. Credits convert to USD at
25 credits per dollar, matching the Mac implementation. Foreground refresh also
attempts the credit-usage-events endpoint for monthly spending with a five-second
timeout. Failure leaves quota intact and optional spending absent. Widgets do not
make that additional request.

Claude prefers structured spend using its supplied currency exponent, otherwise
using extra_usage values in the response's native units. Unknown currency is
shown as credits. Claude's plan comes from a separate account-profile lookup on
each successful usage refresh, using the app's browser-connected account. No CLI
installation or local CLI credentials are required. The profile is not cached
independently: upgrades and downgrades replace the previous plan, while failed,
malformed, or unknown profiles show “Not reported” and preserve the quota reading.
Claude balance is not exposed and is not inferred. Optional fields remain backward-compatible with old caches.
The owner has observed Codex metadata and Claude usage credits on the phone;
availability across other plans needs further validation.

## Build and validation

Run from the repository root using the installed Xcode release candidate:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/MobileAccessCore

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AIQuota.xcodeproj \
  -scheme AIQuota-iOS \
  -destination 'platform=iOS Simulator,name=AI Quota Access Check' test
```

Choose an available simulator if that local device is absent. Keep signing enabled
for hosted Keychain tests; disabling it causes storage failures.

Build-8 validation: 26 core tests and 10 hosted tests passed; Mac and iOS builds
passed. Hosted render attachments check long metadata, purple/red dark cards,
orange light cards, and mixed widget components for both providers. Real Lock Screen
placement, increased contrast, larger text, long-running renewal, and background
freshness should continue to receive device review. Notifications, Home Screen
widgets, CloudKit, and history remain on the root README roadmap.

## Onboarding (build 9 upload)

Version 0.1.0 (9) archived and uploaded successfully on September 13, 2026.
App Store Connect confirmed VALID processing and IN_BETA_TESTING for internal testers.

First launch offers welcome, independent service connections, and Lock Screen widget
setup. Setup can be skipped, resumed after interruption, or replayed from Settings.
Existing accounts bypass automatic onboarding. Only presentation progress is stored;
setup does not replace credentials or cached readings. The connection steps reuse
the existing provider sign-in screens.

This batch also uses native light card backgrounds, quaternary system fill in dark
mode, and moves centered service names closer beneath the gauges. All 16 hosted
simulator tests passed, including onboarding progression and rendered large-text
guidance. The welcome screen was reviewed in the running simulator. Full sign-in,
skip, and replay flows still need phone verification before release.

## TestFlight release workflow

From the active worktree, run `python3 scripts/testflight.py release`.
The command checks App Store Connect for this iOS version, advances and synchronizes
all app/widget build settings, archives, uploads, and waits up to ten minutes for
internal TestFlight availability. It never submits an App Store or external beta review.
Review and test changes before running it. Python 3, `cryptography`, and XcodeGen are required. iOS version/build settings live in
`iOS/project.yml`; the script updates only iOS targets in the shared project.

Credentials come from `ASC_KEY_ID`, `ASC_ISSUER_ID`, and optional `ASC_KEY_PATH`,
or the existing local `~/.appstoreconnect/sendmoi.env` configuration. Override that
file with `ASC_ENV_FILE`. Credentials are never written into the repository.

Other commands:

- `python3 scripts/testflight.py preflight`: read-only live build-number check.
- `python3 scripts/testflight.py archive`: number and archive without uploading.
- `python3 scripts/testflight.py upload --run /absolute/release/directory`: upload a completed, unsubmitted archive.
- `python3 scripts/testflight.py status --run /absolute/release/directory --wait 0`: check Apple processing and internal beta availability without rebuilding/uploading.

Release records and logs live in `~/Library/Logs/AIQuota/TestFlight/`; archives live
in Xcode's standard Archives directory so Organizer can find them. The printed
release directory is the value for `--run`. A shared Git lock prevents concurrent
script runs across worktrees. Upload preserves the selected build number rather
than letting export silently renumber it.

If upload fails or is interrupted, use `status` first. The record deliberately
blocks another upload attempt because delivery may already have occurred. Inspect
the upload log and App Store Connect before manually recovering an ambiguous run.
A processing timeout preserves the release record and can be followed with `status`.
Failed archives can be rebuilt by a new release command, using a new build number.


Use a command-local `PATH=/usr/bin:/bin:/usr/sbin:/sbin` for distribution. Apple's
rsync can otherwise launch a Homebrew subprocess that rejects its extended-attributes
option, producing Organizer's **Copy failed** error. An archive need not be rebuilt
for that packaging error.

Xcode may also report a missing Apple account token. Reauthenticate the account for
Organizer uploads, or use an existing authorized App Store Connect API key through
xcodebuild's authentication options. Never place keys or tokens in this repository.
The build-8 upload used the API-key route and completed successfully.

The app declares app-local UserDefaults access with CA92.1 in
`PrivacyInfo.xcprivacy`. App Store privacy answers are a separate submission task.


## September 13 connection and onboarding refinement (TestFlight build 11)

The overview now distinguishes known reconnect requirements, rejected renewal,
and temporary update failures. Saved gauges become neutral when a connection
fails; the warning precedes cached metadata and past reset dates are labeled as
last reported. The widget keeps saved readings and replaces its center mark with
an attention symbol when renewal requires opening the app. No account is removed
in response to a failed request.

Claude code submission now retains its challenge after an error, allowing correction
and retry. A known OAuth `invalid_grant` is classified separately from generic HTTP
400. Top-level and nested error codes are recognized; only allowlisted codes are
shown or logged. No provider messages, tokens, or response bodies enter diagnostics.
The Mac can use browser session cookies or externally maintained Claude Code
credentials. Its working connection does not establish that the phone's independent
refresh token is valid. Shared app/widget renewal already holds a file lease through
rotation and persistence. The phone's recurring HTTP 400 root cause is **not yet
confirmed at that checkpoint**; the build-13 section below records the later
`invalid_scope` evidence and successful device renewal.

Onboarding now follows welcome, services, notifications, widgets, and completion.
The existing numeric widget step remains 2 so saved build-9 progress resumes on the
correct screen. The app icon and short Mac tagline replace the verbose welcome.
Detailed provider setup instructions stay in the connection screen. Analytics is a
roadmap item only. The header combines the app title and larger key, and reset
labels/dates use consistent typography. The Service details widget's service name
now matches the percentage size at 14 points.

Notifications currently support estimated 5-hour and 7-day resets, with explicit
permission opt-in and per-service controls. Fresh successful app/widget fetches
replace requests using stable provider/window identifiers. Disabling alerts,
disconnecting, failures, missing windows, zero usage, and stale readings cancel
relevant pending requests when the app or extension runs. Past dates are not
rescheduled. Previously scheduled alerts can still arrive without a subsequent
fresh check, so their wording explicitly describes an estimate and asks the user
to open the app. Usage thresholds and confirmed-reset alerts are not implemented.
See [Apple's local notification requests](https://developer.apple.com/documentation/usernotifications/unnotificationrequest).

Validation: 27 core tests and 23 hosted tests passed, including nested OAuth error
sanitization, failure persistence/recovery without deleting credentials, code retry,
onboarding migration, reset scheduling/replacement/cancellation, and provider
isolation. Simulator render review covered the renewal card and large-text welcome
and widget guidance. Full interactive onboarding, permission denial/re-enabling,
notification delivery, and genuine Claude renewal need phone verification. This
batch was archived and uploaded as 0.1.0 (11), confirmed VALID and IN_BETA_TESTING
in App Store Connect on September 13. Project and widget build numbers match 11.

The hosted XCTest suites reported zero failures, but xcodebuild lingered after
suite completion and was terminated during cleanup. A normal final test-command
exit was not obtained; retain that distinction when reviewing validation.


## Afternoon parity checkpoint (TestFlight build 12 available)

The completion page now includes version and build, the Mac creator credit, a
Need help group with the existing GitHub and X links, and the completion button
above that footer. The overview key is bold with 1.0/0.5 opacity. Source inspection
confirmed the Mac gauge accent is native system purple, so iOS keeps its adaptive
system equivalent rather than introducing a hard-coded color. Service cards use
a 136-point gauge, a divider before metadata, and aligned label/value columns.
Hosted suites reported 23 passing tests; light/dark card renders were inspected.
Full completion-screen and accessibility interaction checks remain outstanding.

This run started with weekly usage at 96% and is intentionally contained. Remaining
requested work: full five-reference parity audit, first-run/reinstall validation,
Mac-style Reset All Settings and separate replay semantics. No credentials
were reset during that afternoon UI pass. The subsequent release-script work is
documented above. Do not treat these pending items
as completed or silently remove them from the next planned work.

Release automation validation: five focused Python tests passed (numbering, platform/version filtering, project synchronization, archive identity, and beta availability). The first end-to-end scripted release, 0.1.0 (12), was confirmed VALID and IN_BETA_TESTING on September 13, 2026. Project and widget build numbers remain 12.

## Renewal and onboarding refinements (TestFlight build 13)

The owner's September 13 screenshot identifies Claude renewal failure as HTTP 400
`invalid_scope`. This is stronger evidence than the earlier generic 400, but does
not prove an installation-triggered disconnect. Keychain service/account identity
is stable across build numbers. Renewal previously resubmitted the fixed sign-in
scope list. It now omits `scope` to retain the original grant, per
[RFC 6749 section 6](https://www.rfc-editor.org/rfc/rfc6749#section-6).
Sign-in permissions are unchanged. The owner subsequently confirmed successful
renewal on build 13. Continue monitoring longer-running renewal and recovery.

Settings now follows the Mac's Guided Setup and Reset All Settings actions.
Guided Setup starts at welcome and preserves accounts/settings. Reset requires
confirmation, cancels and awaits in-flight model tasks, clears credentials and
readings under the existing per-service leases, removes owned preferences and
reset reminders, then returns to welcome. System notification authorization stays
unchanged. Failure is explicit and may leave a partially reset state; retry is
supported. The owner's credentials have not been reset during development.

First-run policy: retained Keychain credentials alone no longer suppress welcome.
Legacy local app history distinguishes a pre-onboarding upgrade from a reinstall;
completed/dismissed onboarding remains respected. This is a local-state policy,
not a guarantee about iOS backup/restore or device migration behavior. Simulator
state tests cover retained-account welcome and non-destructive guided replay;
a physical TestFlight uninstall/reinstall remains a device check.

Five-reference comparison:

- Welcome uses the Mac icon, app name, and short two-line tagline.
- Services use the Mac labels, provider subtitles, connected/sign-in states, logo
  treatment, and refresh-frequency preference. Menu-bar selection is Mac-only.
- Notifications has opt-in and per-service controls. Current iOS alerts remain
  estimated-reset reminders; threshold parity remains on the roadmap.
- Widget instructions remain the agreed placeholder pending Home Screen widgets
  and supplied visuals.
- Completion includes version/build, creator credit, support links, and finish
  action. Analytics remains roadmap-only, without a nonfunctional toggle.

Validation checkpoint: 27 core tests passed. Hosted simulator suites reported
27 passing tests, including a screenshot-only helper whose captures were blank;
that ineffective helper was removed, leaving 26 meaningful hosted cases. The
functional cases passed, but full-page visual and interaction verification remains
unfinished. Xcode again lingered after suite completion and was stopped, so this
is suite-level success rather than a clean test-command exit. Build 13 was subsequently archived and uploaded with the release script, and
the owner confirmed successful Claude renewal. Next: finish visual/interaction
checks and physical-device reset/reinstall verification.

## Home Screen widgets and granular alerts (implementation checkpoint)

Mac widget inventory and iOS equivalents:

| Mac option | Home Screen size | iOS configuration |
| --- | --- | --- |
| Single-service gauge | Small | Codex or Claude Code |
| Single-service details | Medium | Codex or Claude Code |
| Both-service gauges | Medium | Both, centering a single enrolled service |
| Both-service details | Large | Both services with available account metadata |

These add two new widget kinds, preserving the four existing Lock Screen kinds.
They reuse shared credentials, lease-protected refresh, saved readings, freshness
boundaries and attention states. Metadata appears only when supplied by the mobile
provider; Claude plan information and complete Mac billing metadata are not always
available. Taps open the corresponding account. Gallery placement, iOS tint modes,
and background delivery still require physical-device verification.

Reset alerts now offer Off, Only near the limit, and Every reset separately for
each service's 5h and 7d window. Near-limit defaults to 90% and is adjustable.
Existing master and service switches stay intact. Existing enabled reset alerts
adopt the quieter 90% default. Lowering usage to 18% cancels an unneeded reminder;
100% remains eligible. iOS continues to schedule an estimated reset from the latest
fresh reading, not claim that a provider has actually restored capacity. The owner
confirmed an estimated-reset notification arrived at 100% in the prior build.

iOS also has opt-in approaching-limit and limit-reached alerts per window, with an
adjustable approaching threshold (85% default). These run on successful app/widget
refresh, never on a timer that invents usage. A persisted per-window high-water
mark suppresses repeat alerts. Delivery is subject to iOS update opportunities;
it is not a server push service. Missing reset dates suppress usage alerts so a
stable deduplication window is required. Full reset removes these preferences and
state; disconnect clears the account's deduplication state.

Mac Settings gets the same reset choices and threshold wording, retaining its
existing usage-alert groups. The Mac records peak observed usage within the old
window and only considers reset when the provider reports a new future window.
This avoids evaluating the new zero-percent value and avoids repeated alerts when
an expired timestamp is merely repeated. Initial install of this policy establishes
a baseline without sending a reset alert. Existing disabled reset switches remain
disabled. Mac and iOS use the same user-facing policy, with different delivery
mechanisms appropriate to their platforms.

Validation: 29 mobile core tests and 144 AIQuotaKit tests passed. Hosted simulator
suites reported 28 passing cases; the first run exited successfully, while the
later run lingered after all suites passed and was stopped. Both iOS and Mac
Debug builds succeeded. All four Home Screen layouts were rendered at compact
phone widget sizes in light and dark mode; an unintended blue Link tint was
removed and the corrected renders reviewed. Build 14 subsequently archived, uploaded, and reached internal TestFlight
(`VALID`, `IN_BETA_TESTING`), confirmed by the release record and the owner's
Home Screen screenshots. The owner reviewed full-color light/dark and clear/tinted
widget appearances. Delivery of the new notification choices still needs device
coverage beyond the earlier estimated-reset alert.

## September 14 refinement: widget readability and stable refresh layout

Implemented locally after the reset, using the owner's six build-14 widget
screenshots and six sampled frames of the supplied reload recording.

- Home Screen metadata increases from caption2 (11 pt) to 13 pt. Service names
  use 12 pt bold, and reset/status captions increase from 10 pt to 11 pt.
- Single-service medium widgets align their metadata to the top. Gauge captions
  reclaim the empty bottom of the arc, accommodating larger text without growing
  the ring. Medium/large detail layouts show the weekly reset in the metadata
  column instead of repeating it under the gauge.
- Full-color widget containers use regular material, matching the Mac popover's
  material choice. Reduce Transparency uses a neutral grouped background. The
  background stays inside WidgetKit's removable container; no custom glass layer
  is placed over clear/tinted content. Apple controls the final Home Screen
  composition, so physical full-color material rendering needs owner review.
- Overview cards measure together and share the taller natural height. Ordinary
  metadata rows, reset blocks, and status space remain reserved as readings change.
  Content anchors at the top, with unused space below. Connection errors can grow
  both cards together; they are never clipped to a fixed pixel height.
- The toolbar swaps its refresh icon and spinner within the same 24 pt bounds.
  Refreshing replaces the freshness label rather than adding a row. Freshness
  follows the Mac's `Just now`, seconds, minutes, and hours labels, retaining
  explicit saved/older-reading cues. Failed readings do not claim a current limit.

Validation: the iOS app and widget compile successfully. Hosted simulator layout
and regression tests cover refresh/idle and disappearing metadata at default,
extra-large, and accessibility sizes, plus shared height with a renewal failure.
All four Home Screen sizes were rendered and reviewed in light/dark mode. Preview
views now install their SwiftUI environment properly, so accessibility layout is
actually exercised. ImageRenderer previews use a neutral backing surface because
it does not reproduce WidgetKit's wallpaper composition. Final hosted run: 29 tests passed, with `TEST SUCCEEDED` in
`/tmp/aiquota-refinement-final-tests.log`. The build log is
`/tmp/aiquota-refinement-build.log`. The small widget with both reset captions at
a weekly limit was also rendered for fit review. `git diff --check` passed.

References: Mac `CircularGaugeView` refresh swap, `PopoverView` freshness labels
and regular material, and Apple's
[widget background guidance](https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background)
and [Liquid Glass rendering guidance](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass).

No new archive, upload, commit, or merge is part of this pass. Build 14 remains the
TestFlight build. Later observations about explicit 5h/7d labels on Remaining and
secondary-text contrast were not added to the scheduled implementation scope.

## September 14 follow-up: consistent weekly reset captions

The small and dual-gauge Home Screen widgets now show the 7-day reset at all
usage levels, removing the former 85% visibility threshold. Single-medium and
large widgets continue to show it in their metadata column. Weekly captions
include the weekday as well as the time. Saved and disconnected readings retain
their existing status cues instead of presenting stale reset predictions.
The double Lock Screen widget also uses the same 80% logo scale as the other
Lock Screen layouts, already reviewed by the owner in build 16.

## Deferred App Intents plan

See the shared [Mac + iOS App Intents backlog](../README.md#app-intents-backlog-mac--ios) for scope, acceptance criteria, and later integrations. This is planned work, not a shipped feature or scheduled task.


## Overview polish (September 15, 2026)

- Native inline large navigation title; freshness shares a baseline with the 5h/7d key.
- Two-thirds allowance column and one-third account metadata column, with a centered divider and equal gutters.
- Reset captions use “5h resets” / “7d resets”; unreported windows show N/A in secondary gray across app and widget values, with “not reported” reset captions.
- Card footer dividers and repeated timestamps are removed. Connection recovery remains available in each card.
- Entire spending rows are tappable, with the info icon inline beside the label and the value using the full column width. Native popovers use a top arrow and the same title and copy as Mac. Claude uses “Usage credits” and “spent”.
- Card height stays stable through refresh, missing metadata, and connection states at normal and accessibility text sizes.
- Profile transition tests cover Pro → Max → Pro, profile failures, unknown plans, and recovery. Live plan-change verification remains a device check.

Validation: the unified-identifier iOS device build passed with code signing disabled.
After the inline-info correction, all four overview layout tests passed and the
simulator popover screenshot was reviewed. Replacing a TestFlight installation and
tapping the updated rows on a physical device remain manual checks.
