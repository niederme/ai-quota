# Mac distribution channels

AIQuota uses one Xcode project with separate schemes and targets for two builds from the same source. The TestFlight build does not replace the existing direct-download configuration.

| Route | Project / scheme | Updates | Sandbox |
| --- | --- | --- | --- |
| Website / GitHub release | `AIQuota.xcodeproj` / `AIQuota-macOS` | Sparkle, existing feed | Existing unrestricted Mac app |
| TestFlight / Mac App Store | `AIQuota.xcodeproj` / `AIQuota-macOS-TestFlight` | Apple | App and widget sandboxed with outgoing network access |

Both use the existing app and widget bundle identifiers and shared storage groups. They are alternate installations of the same app, not side-by-side products.

## TestFlight archive

Generate the project when changing its spec, then select `AIQuota-macOS-TestFlight` and Product → Archive in Xcode beta:

```sh
xcodegen generate --spec project.yml
open AIQuota.xcodeproj
```

Reproducible archive command from the active worktree:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project AIQuota.xcodeproj \
  -scheme AIQuota-macOS-TestFlight \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath /tmp/AIQuota-TestFlight.xcarchive \
  -allowProvisioningUpdates archive
python3 scripts/verify-mac-distribution.py testflight \
  /tmp/AIQuota-TestFlight.xcarchive/Products/Applications/AIQuota.app
```

Distribute the resulting archive through App Store Connect in Organizer. Do not reuse an archive built with the regular `AIQuota-macOS` scheme: its app and Sparkle executables are not the TestFlight distribution configuration.

## What changes in the store build

- Sparkle is absent from the target dependency graph, linked binary, and app bundle. Its settings and update UI are excluded with `APP_STORE`.
- Both app and widget have sandbox, outgoing-network, shared app-group, and shared Keychain entitlements.
- The store build does not import legacy browser/defaults files or run the Launch Services repair commands that restart widget hosts.
- Local Codex CLI and Claude Code credential discovery is disabled by an explicit host-bundle channel marker. Swift package flags do not inherit target flags, so the runtime marker is present in both store plists.
- AIQuota’s existing browser sign-in and own session storage remain available. Users may need to sign in again because the sandbox has separate preferences and WebKit storage. Live provider sign-in must be checked in the sandboxed build before beta rollout.

The direct build keeps Sparkle, its automatic/manual update controls, startup repair, legacy migration, and local credential discovery.

## Verification

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test \
  --package-path Packages/AIQuotaKit --no-parallel
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project AIQuota.xcodeproj -scheme AIQuota-macOS -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/aiquota-direct-build build
python3 scripts/verify-mac-distribution.py direct \
  /tmp/aiquota-direct-build/Build/Products/Release/AIQuota.app
```

The verifier inspects signatures, app/widget version consistency, actual entitlements, Sparkle linkage, and update-feed metadata in built artifacts. A successful archive/export is packaging evidence, not App Review approval or proof of live provider authentication.

The single `project.yml` owns both routes. The marketing version is shared; the `StoreDistribution` template sets the store build number for both app and widget. The initial store archive is 1.9.27 (388); the existing direct build remains 1.9.27 (387). Future uploads must use an unused build number.

## Why separate targets

The original app enabled sandboxing in commit `ae302e5`. Commit `5132306` removed it in version 1.3.2 to fix the Sparkle installer. Separate store targets preserve that direct-download behavior while restoring sandboxing for TestFlight. Both target pairs share the same source files; only the direct app target depends on Sparkle.
