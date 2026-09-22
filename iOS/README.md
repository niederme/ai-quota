# iOS development guide

The iPhone and iPad app is in beta via TestFlight. For features and availability,
see the [project README](../README.md#ios).

- [Build and test](#build-and-validation)
- [TestFlight releases](#testflight-release-workflow)
- [Remaining work](../docs/roadmap.md#ios)
- [Planned Shortcuts and App Intents](../docs/roadmap.md#app-intents-backlog-mac--ios)
- [Historical build and validation notes](HISTORY.md)

Commands below run from the repository root. The Mac app is the design reference
for typography, colors, materials, and gauge proportions.

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
The Codex code-entry page uses a retained WebKit view and persistent website
storage. Closing and reopening the sheet during an active attempt resumes the
same page without loading the sign-in URL again. The code and a labeled Copy code
button sit above the page and keyboard. OpenAI still controls cookie expiration
and reauthentication. Disconnect and Reset All Settings clear this website data.
A system-browser fallback remains available for Google sign-in, which does not
support embedded WebKit authorization; that fallback uses the copy-code extension.
Real provider login, reopening, and keyboard layout remain device checks.

Claude uses browser authorization, PKCE, and manually pasted `code#state`.
State must match the current attempt, which expires after 15 minutes. The app
requests `org:create_api_key user:profile`; it does not request inference scope,
create API keys, send prompts, purchase credits, or redeem resets.

During onboarding, successful sign-in and the initial usage check automatically
return to the service list so the user can connect the other service. This applies
to both Codex and Claude. Failed or canceled attempts stay on the account screen;
account screens opened outside onboarding retain their normal navigation.

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

Run from the repository root with the installed Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/MobileAccessCore

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AIQuota.xcodeproj \
  -scheme AIQuota-iOS \
  -destination 'platform=iOS Simulator,name=AI Quota Access Check' test
```

Choose an available simulator if that local device is absent. Keep signing enabled
for hosted Keychain tests; disabling it causes storage failures.

## TestFlight release workflow

From the active worktree, run `python3 scripts/testflight.py release --wait 0`.
The command checks App Store Connect for this iOS version, advances and synchronizes
all app/widget build settings, archives, and uploads. With `--wait 0`, it checks
processing status once and exits without polling for internal TestFlight availability.
For routine deploys, report the upload result and let the owner test via TestFlight;
do not run follow-up availability checks unless requested. Omitting `--wait 0`
opts into waiting up to ten minutes. The command never submits an App Store or external beta review.
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


The app declares app-local UserDefaults access with CA92.1 in
`PrivacyInfo.xcprivacy`. App Store privacy answers are a separate submission task.

The browser toolbar action uses a bundled action extension with a separate Keychain
access group containing only the current device code and its expiry. Account tokens
are not accessible to that extension. Codes expire after 15 minutes and are cleared
when the sign-in attempt ends. The TestFlight script validates both bundled extensions.
