# Mac Claude Keychain verification

The change applies to the direct-distribution Mac app. AIQuotaKit is a macOS-only
package; iPhone/iPad use MobileAccessCore and separate token stores. The Mac App
Store build continues to disallow host credential discovery and hides this toggle.

## Automated evidence

- Mac Debug app and widget build succeeded with signing disabled.
- 45 focused tests in ClaudeAuthCoordinatorTests and ClaudeOAuthCredentialsStoreTests passed.
- Tests inject synthetic Security responses; they verify both no-UI query controls,
  persistent-reference and service reads, denied/unavailable outcomes, default-off
  consent, sign-in fallback, automatic recovery, and cached-token revocation.
- The legacy UI-fail constants intentionally generate deprecation warnings. The
  LAContext control is also present; the legacy control covers file-Keychain ACL UI.

These checks do not prove absence of operating-system dialogs in a signed installed
app or validate an update against a previously authorized Keychain item.

## Manual check before release

Use this branch's Xcode project and the AIQuota-macOS scheme on a test Mac/account.
Use a disposable Claude account or a synthetic Keychain item in a dedicated harness;
never print or copy real credential values for testing.

1. Start with the new setting absent. Confirm Settings → Accounts shows reuse off.
   Check launch, periodic refresh, opening the popover, and reconnect after an update.
   No Claude Code Keychain authorization prompt should appear.
2. Sign in through AIQuota's login flow. Confirm usage refreshes with reuse off.
3. Enable reuse. With authorized Claude Code credentials available, confirm recovery.
   With access denied or requiring interaction, confirm no prompt appears and the
   normal AIQuota sign-in flow remains available. Background recovery must not open login.
4. Disable reuse after successful Keychain recovery. The next credential request
   must not reuse the cached Keychain token. File credentials and web sessions remain
   separate sources, so they may keep an existing connection working.
5. Reset All Settings and confirm reuse returns to off.
6. Repeat denied-access and recovery checks after replacing the signed app with a
   newer signed build. Record signing identity, macOS version, and observed dialogs.

## Commands from the active worktree

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project AIQuota.xcodeproj -scheme AIQuota-macOS \
  -destination 'platform=macOS' build

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --package-path Packages/AIQuotaKit \
  --filter 'ClaudeAuthCoordinatorTests|ClaudeOAuthCredentialsStoreTests'
```
