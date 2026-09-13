# AI Quota for iOS

The iPhone/iPad app lives in this directory for historical reasons; it is no longer
just an access probe. Its separate Xcode project shares the Mac app's App Store
Connect record. The Mac remains the design reference for typography, system colors,
materials, gauge proportions, and Settings language.

## Current release

**TestFlight 0.1.0 (13)** is valid and available for internal testing. The local
app, widget, and XcodeGen configuration all use build 13. The owner reviewed the
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

Open `AIQuota-iOS.xcodeproj` and select the `AIQuota-iOS` scheme.

| Configuration | App identifier | Widget identifier |
| --- | --- | --- |
| Debug | `com.niederme.AIQuota.MobileAccessProbe` | `com.niederme.AIQuota.MobileAccessProbe.Widget` |
| Release | `com.niederme.AIQuota` | `com.niederme.AIQuota.mobilewidget` |

Release belongs to the same App Store Connect app as macOS. Preserve the existing
App Group, shared Keychain groups, and legacy `aiquota-probe` URL scheme so updates
retain connections and widget routing. Debug and Release coexistence still needs
care when checking which installed app a widget opens. The iOS app uses the Mac's
native Icon Composer asset.

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
shown as credits. Claude plan and balance are not exposed by the current response
and are not inferred. Optional fields remain backward-compatible with old caches.
The owner has observed Codex metadata and Claude usage credits on the phone;
availability across other plans needs further validation.

## Build and validation

Run from the repository root using the installed Xcode release candidate:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path prototypes/mobile-access/Core

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project prototypes/mobile-access/AIQuota-iOS.xcodeproj \
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
Review and test changes before running it. Python 3 and `cryptography` are required.

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
