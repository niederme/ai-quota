# AI Quota for iOS

The iPhone/iPad app lives in this directory for historical reasons; it is no longer
just an access probe. Its separate Xcode project shares the Mac app's App Store
Connect record. The Mac remains the design reference for typography, system colors,
materials, gauge proportions, and Settings language.

## Current release

**TestFlight 0.1.0 (8)** was uploaded and verified valid in App Store Connect on
September 13, 2026. The owner has reviewed the update. The local app, widget, and
XcodeGen configuration all use build 8.

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
remains unconfirmed. Continue field-testing renewal and recovery on real accounts.

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
freshness should continue to receive device review. Onboarding, notifications, Home
Screen widgets, CloudKit, and history remain on the root README roadmap.

## TestFlight release workflow

1. Review changes and update docs; preserve unrelated local Xcode preferences.
2. Verify the latest accepted iOS build number in App Store Connect.
3. Before archiving, increment `CURRENT_PROJECT_VERSION` in both `project.yml` and
   `AIQuota-iOS.xcodeproj/project.pbxproj`. Match app and widget, including any
   target-level overrides. The next intended build after 8 is 9.
4. Archive the active worktree's `AIQuota-iOS` scheme for a generic iOS device.
5. Upload with App Store Connect export options and automatic signing. Use
   `manageAppVersionAndBuildNumber: true` if automatic conflict resolution is desired.
6. Verify upload success, processing status, and the actual accepted build number.
   Synchronize both project files if distribution renumbered it. A local archive
   number alone does not identify the uploaded build.
7. Confirm availability in TestFlight. Upload is distinct from beta distribution
   and App Store review; do not submit for review without authorization.

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
