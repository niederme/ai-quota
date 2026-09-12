# AI Quota mobile access probe

A separate iPhone/iPad development app for the first technical feasibility check. It does not change the shipping Mac target, introduce a relay, or implement the full widget product. The first Lock Screen widget is described below.

## What it checks

- Start Codex device-code sign-in on the phone, with no Mac credential import.
- Persist the returned connection in a dedicated device-only Keychain entry.
- Read the short and weekly quota windows directly from Codex.
- Reopen the app and retrieve a fresh reading.
- Explicitly renew the session and retrieve another reading.

Only successful quota snapshots are cached in local preferences. Missing windows stay unavailable; request errors retain the old reading and its original timestamp. The probe does not send prompts, generate API keys, redeem reset credits, or log raw responses or credentials. The connection itself can carry broader authority than the requests this probe makes.

## Authentication status

The implementation follows the public first-party Codex device-code protocol and uses its public CLI client identifier. This is **not** an AI Quota client registration or evidence of third-party distribution permission. The consent screen may identify Codex CLI. Device-code login may need to be enabled in the user's ChatGPT settings. No provider settings are changed automatically.

The user has authorized proceeding with a personal feasibility build despite unresolved distribution risk. Provider permission and App Store suitability remain open, separate from technical success. TestFlight is not an exemption from review requirements.

Claude now has a separate personal access probe using browser authorization and manual code entry. Its implementation and owner check are described below. This does not establish provider permission or successful live Claude access.

## Build and test

Use the installed Xcode 27 RC explicitly and work in this checkout:

```sh
xcodegen generate --spec prototypes/mobile-access/project.yml
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path prototypes/mobile-access/Core
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project prototypes/mobile-access/AIQuota-iOS.xcodeproj -scheme AIQuota-iOS -destination 'generic/platform=iOS Simulator' build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project prototypes/mobile-access/AIQuota-iOS.xcodeproj -scheme AIQuota-iOS -destination 'platform=iOS Simulator,name=AI Quota Access Check' test
```

The project uses the repository's existing development team and a separate bundle identifier, `com.niederme.AIQuota.MobileAccessProbe`. The host test uses a unique Keychain account so it cannot overwrite a real connection.

## Verification status · September 11, 2026

The scheduled feasibility follow-up rebuilt and tested the existing probe with Xcode 27 RC (27A266a). All nine core tests and the hosted simulator Keychain round-trip/deletion test passed. These verify request construction, quota decoding, error handling, token-renewal response handling, and local secure storage using synthetic credentials. No live provider login was performed during the automated run. See the later owner-recorded result below.

At that automated handoff, independent sign-in, live quota accuracy, retrieval with the Mac asleep, and real session renewal remained unverified. The subsequent recording establishes sign-in and a fresh reading; the owner later reported passing renewal and force-close/reopen retrieval with the Mac asleep. The bounded check below is retained for repeatability. Do not treat the passing automated checks as clearing that gate or begin the widget trial yet.

Record each step as pass, fail, or not tested, with a timestamp. For quota comparison, record only percentages, reported resets, and the last successful reading time. Never include a device code, token, or raw provider response. A failure should identify the displayed safe error and the step where it occurred.

## Bounded device check

1. Run the AIQuota-iOS scheme on your iPhone from this worktree's project.
2. Tap Connect Codex. Complete the provider's sign-in using the one-time code shown in the app, then return. Do not share codes or tokens in chat.
3. Confirm the reading against your provider usage page. A completed login alone is not a successful quota check.
4. Put the Mac to sleep, reopen the phone app, and refresh. Record only success/failure, percentages, reset times, and timestamps.
5. Use Check session renewal once, then refresh again after reopening.

Stop if this flow fails. Preserve the safe error category rather than extending into a lengthy device session or adding fallback credentials. A successful forced renewal does not establish long-term session reliability. Widget freshness remains a later gate.

## Sources inspected September 11, 2026

- [Official Codex authentication documentation](https://developers.openai.com/codex/auth/)
- [First-party device-code protocol](https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs)
- [First-party token exchange](https://github.com/openai/codex/blob/main/codex-rs/login/src/server.rs)
- [First-party client identifier](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/manager.rs)
- Existing AIQuotaKit CodexUsage and OpenAIClient source for quota-window semantics and request headers.

## Sign-in prerequisite shortcut

The signed-out screen now explains the device-code authorization prerequisite before starting a challenge and offers `https://chatgpt.com/#settings/Security`. This is a best-effort web settings shortcut, not a verified native ChatGPT iOS deep link. The UI includes the manual Settings → Security and login route if the fragment is not honored. Phone routing and preservation of the fragment through sign-in still need verification. No setting is enabled automatically.

The owner's September 11 recording confirms successful phone sign-in and a fresh quota reading after enabling this setting. The owner subsequently confirmed session renewal and fresh retrieval after force-closing and reopening the app while the Mac was asleep. These are owner-reported passes of the bounded Codex technical check; long-term reliability and widget freshness remain untested.

The settings shortcut now presents `SFSafariViewController` inside the probe instead of dispatching the URL with `openURL`. This keeps the initial settings navigation on the web. The native ChatGPT app was observed to omit the device-code authorization toggle. The settings browser does not expose cookies or page contents to the probe. Verify the signed-in and signed-out website paths on the phone; subsequent website links or redirects may still launch another app. The working device-code authentication flow is unchanged.

## Claude access investigation · September 11, 2026

The existing Mac implementation retrieves subscription windows through `https://api.anthropic.com/api/oauth/usage` using OAuth, or `/api/organizations/{org}/usage` using a web session. Neither route establishes an independent, supported mobile client registration.

A candidate mobile flow is Safari authorization followed by an explicit paste of the authorization code into the app. Limits publicly describes this flow with `org:create_api_key` and `user:profile`. The API-key scope is broader than quota viewing; omission of `user:inference` alone does not establish a read-only credential. Its client registration, redirect configuration, token renewal behavior, and provider permission have not been established for AI Quota.

Anthropic's current authentication guidance restricts third-party Claude.ai login and handling of subscription credentials. The published Usage and Cost Admin API reports organization API consumption, not this personal subscription allowance. No documented replacement for personal five-hour/weekly quota access was established in this investigation.

At the end of the initial investigation the provider-access gate remained unresolved and no Claude implementation had been added. The later personal-probe implementation below follows the owner’s explicit instruction to proceed despite that unresolved permission basis. The user has already accepted personal feasibility/distribution risk; that decision is recorded and is not being requested again. Before treating the candidate as a supported integration, establish its client and scope contract and the permission basis, or explicitly revise the provider-access gate. Existing Codex access remains available for the next product slice.

Sources checked:

- https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use
- https://platform.claude.com/docs/en/manage-claude/usage-cost-api
- https://getlimits.app/ (connection description, not independent proof)

## Claude personal probe implementation

Open the Claude card’s connection control, then **Connect Claude** and **Open Claude sign-in**. Complete the provider's browser flow and explicitly paste the full `code#state` value into the secure field. No automatic clipboard reading is used. The state must match this attempt; a random PKCE verifier binds the exchange, and the local attempt expires after 15 minutes. Closing the process discards pending authorization state, so start again in that case.

Protocol constants and JSON exchange were checked against the publicly published `@anthropic-ai/claude-code` npm package version 2.1.0 (downloaded without executing it). This is a known first-party protocol snapshot, not a supported third-party contract or a claim that it is the latest CLI. Public client ID: `9d1c250a-e61b-44d9-88ed-5944d1962f5e`; manual callback: `https://console.anthropic.com/oauth/code/callback`; token endpoint: `https://console.anthropic.com/v1/oauth/token`. These values may change.

Requested scopes follow the candidate quota-only behavior described publicly: `org:create_api_key user:profile`. They exclude `user:inference`, but the first scope is broad and is disclosed before authorization. The probe does not call the key-creation endpoint or any inference endpoint. The quota request uses the existing OAuth usage endpoint and an honest `AIQuotaMobileProbe/0.1` user agent, without impersonating the CLI. Whether this scope combination and user agent are accepted is unverified until the owner tests it. HTTP errors stop the attempt; no cookie or Mac-token fallback is implemented.

Claude credentials use a separate Keychain service, with device-only, unlocked-device accessibility. Quota snapshots have a separate preferences key. A failed fetch retains the previous snapshot and timestamp. Refresh can renew an expiring token; **Check session renewal** forces renewal. Disconnect removes only the local Claude connection and cached reading, not provider-side authorization.

### Claude owner check

1. Run the updated probe on the phone and open **Check Claude access**.
2. Connect using the browser and paste the complete authorization code into the app, not chat.
3. Compare the five-hour and weekly percentages and reset times with Claude's own usage page.
4. Tap **Check session renewal** and confirm a new successful reading.
5. Force-close, put the Mac to sleep, reopen, and refresh. Confirm the successful-reading timestamp advances.

If a step fails, report the step and the safe error shown. Do not paste codes, credentials, or provider response bodies. Live Claude sign-in and access remain unverified until this check passes. Model-specific weekly windows and extra usage are outside this minimal two-window probe.

Validation: Xcode 27 RC built the updated app; all 16 core tests and both simulator Keychain tests passed. The second Keychain test verifies separate provider storage and that removing Claude leaves Codex intact. No live Claude credentials were used during these tests.

Claude sign-in now presents Apple’s `SFSafariViewController` inside the probe, sharing the same browser wrapper as the ChatGPT settings shortcut. After copying the code, tap Done and paste it into the probe. This is a system browser surface, not an app-readable embedded webview. Live Claude sign-in in this surface remains to be checked on the phone.

## First overview UI slice

The app now opens with equal Codex and Claude cards. The dials reuse the Mac app's provider assets, 270-degree flat-ended arcs, 9/7-point ring widths, subordinate weekly arc, and system purple/orange/red thresholds. Native regular material sits over the system grouped background. Five-hour and weekly values sit inside each dial beneath the provider mark, with explicit accessibility labels; missing readings stay unavailable.

Connection and diagnostics screens are now destinations of each provider card, sharing the same live models as the overview. The toolbar refreshes connected providers. Each card shows its own last-checked age and fetch error; readings at least 30 minutes old are labeled older. This is a display convention, not a freshness guarantee.

The provider cards stack vertically with equal minimum heights. Each places the dial beside the provider name and reset times, falling back to a vertical arrangement when space or accessibility text sizes require it; scrolling remains available. The revised Xcode RC simulator build passed, and the disconnected stacked layout was visually checked in dark appearance. Connected-phone and landscape layout review remain to be done. No widgets, history, or generated insight sentence were added in this contained slice.


## Lock Screen widgets · September 12, 2026

Two options are now available:

- **AI allowance**: circular widget, configurable for Codex or Claude.
- **Codex and Claude**: rectangular Lock Screen widget with both dials side by side.

Each dial has a thicker outer five-hour ring, a subordinate inner weekly ring, and its provider logo centered. No visible text. Missing readings have dashed tracks; stale readings have dimmed, dashed progress. VoiceOver retains both percentages and freshness context. Tap a dial to open the main overview and refresh. A reset boundary marks a reading old, never replenishes it speculatively.

### Refresh and renewal

Opening or returning to the phone app refreshes both connected providers. A 15-second guard prevents repeated activation and deep-link events from issuing duplicate requests. Successful app fetches request a widget timeline reload. Widgets request their next refresh after **five minutes**, subject to iOS scheduling, and reuse a successful reading less than one minute old. Separate widget instances therefore do not immediately repeat the app's fetch. This is a requested cadence, not measured delivery.

Both processes now share each provider's access AND refresh credentials in the existing device-only shared Keychain group. The earlier access-only limitation is superseded. No new signing group or Mac credential import is introduced. The app migrates its existing phone connection under a per-provider file lease and removes the old private copy; it never overwrites a newer shared connection. Expired sessions renew automatically when either process fetches.

The same asynchronous cross-process lease covers loading credentials, renewal, saving rotated credentials, usage retrieval, and disconnect. A second process rereads the current credential after obtaining the lease. Renewal is saved before cancellation is checked again. Failed quota requests retain the last successful reading and any newly rotated credential. Disconnect waits for in-flight work, then clears the connection and reading. The app requests a bounded background completion period when a foreground fetch is interrupted by leaving the app. Process termination releases the lease; timeout or cancellation is a failed attempt, not a fresh reading.

Credentials remain in the Keychain with `AfterFirstUnlockThisDeviceOnly` accessibility. Timestamped readings and credential-free diagnostics live in the App Group. Logs record provider, attempt/result, source timestamp, and timeline handoff dates. They contain no credentials or response bodies and do not prove onscreen rendering. Missing diagnostic intervals remain unknown in a later freshness trial.

### Owner check

1. Run **AIQuota-iOS** on the iPhone from this worktree. Open it once to migrate existing connections and refresh both providers.
2. Customize the Lock Screen and add **AI allowance**. Tap it while editing to choose Codex or Claude. Existing circular instances default to Codex.
3. Add **Codex and Claude** for the two-dial option. Check that tapping either dial opens the main overview.
4. Leave the phone app closed while using the accounts on the Mac. Compare later ring changes without first reopening the app. Record actual delivery separately from the requested five-minute cadence.
5. Check automatic renewal across expiry and stale presentation after missing refreshes. No extended seven-day trial has started.

There is no Mac activity signal or CloudKit sync in this build. The Mac can consume quota that the phone subsequently observes, but that activity does not itself wake the phone widget. Physical-device renewal and sustained locked-phone freshness remain unverified.

Validation: Xcode 27 RC builds the app and both widget configurations. Eight hosted tests pass, including shared renewal serialization, rotated-token persistence after fetch failure, disconnect ordering, provider isolation, one-minute cache reuse, and synthetic Keychain round-trips. The existing core suite covers provider APIs and stale/reset rules. New widget layouts and background delivery still need phone verification.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project /Users/niederme/.codex/worktrees/0f46/ai-quota/prototypes/mobile-access/AIQuota-iOS.xcodeproj -scheme AIQuota-iOS -destination 'platform=iOS Simulator,name=AI Quota Access Check' -derivedDataPath /tmp/aiquota-mobile-rc-build test
```

Reference: [Apple: Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

## iOS archive and alternate Lock Screen layout (September 12)

Release uses `com.niederme.AIQuota`, matching the existing Mac App Store Connect record. Its extension uses `com.niederme.AIQuota.mobilewidget`. Debug keeps the installed development identifiers. Both configurations retain the existing App Group and shared Keychain groups. Release is version 0.1.0 (1); iOS has its own platform version.

The **Allowance details** rectangular widget offers Both, Codex, or Claude. Each column places a small paired gauge and service name above a primary five-hour percentage and secondary seven-day percentage. The original text-free widgets remain available. All options open the overview and add no background. Actual Lock Screen fit still needs phone review.

A signed local archive is at `/tmp/AIQuota-iOS-TestFlight.xcarchive`. This is a development-signed archive; Xcode distribution must re-sign it for App Store Connect. On September 12, 2026 at 2:43 p.m. ET, the owner-authorized iOS upload succeeded and App Store Connect reported the package processing. TestFlight availability has not yet been verified. The iOS target now references the Mac's native Icon Composer asset at `AIQuota/AppIcon.icon`; Xcode compiles the platform-specific icon instead of using the transparent Mac PNG as the sole icon source. Existing development connections have not been tested against a Release install on the phone.

Add iOS to the existing AI Quota record in App Store Connect before distributing this archive. Keep the existing Debug app installed. The two builds share connection storage and the legacy URL scheme, so coexistence and widget routing need a phone check.

The app declares its app-local UserDefaults access with CA92.1 in PrivacyInfo.xcprivacy, following [Apple's required-reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). App Store privacy answers remain a separate submission step.

Upload command (run only with owner authorization):

```sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -exportArchive -archivePath /tmp/AIQuota-iOS-TestFlight.xcarchive -exportOptionsPlist /tmp/AIQuota-iOS-Upload.plist -exportPath /tmp/AIQuota-iOS-Upload -allowProvisioningUpdates
```

Use `method: app-store-connect`, `destination: upload`, automatic signing, and team `289GY9L343` in the export options. The restricted command-local PATH avoids Homebrew rsync being selected by Apple's rsync subprocess, which otherwise fails packaging with an unsupported extended-attributes option.

Upload result: `/tmp/aiquota-ios-upload.log` reports `Upload succeeded` and `EXPORT SUCCEEDED`. The first packaging attempt failed locally due to rsync PATH selection; retrying with the system-only PATH completed successfully. Apple accepted the native icon asset during upload validation.

September 12, 2026 follow-up: the compact widget now uses a 3-point center dot in place of the logo; larger text-free gauges retain provider logos. The owner-authorized follow-up archive and App Store Connect upload succeeded. Apple reported the uploaded package processing.
