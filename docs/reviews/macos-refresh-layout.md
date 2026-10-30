# macOS refresh layout regression

Opening the menu-bar sheet calls `refreshOnPopoverOpenIfNeeded()`. A saved
reading older than 30 seconds starts an automatic refresh. Earlier cards put
status text in a conditional `VStack` row below the usage/reset captions. That
row could appear or disappear as loading and error state changed, moving the
card's heatmap and subsequent cards. An existing error also selected the amber
text style.

The production fixes are already on main:

- `f0ccf01` (PR #149) removes the visible routine refresh row and includes
  authentication recovery in loading state.
- `5217810`, merged by PR #156 as `bf3d81a`, replaces conditional warning text
  with a permanent 16 × 16 title slot. Error details remain in the tooltip and
  accessible card label. Routine refresh retains the saved reading.

The October 30 investigation found clean main at `9b353f1`, containing both
fixes. The running `/Applications/AIQuota.app` was build 447; its executable
timestamp was October 28 at 09:28 local time, before the fixed-slot commit that
evening. This points to an older installed build, not missing source on main.
The exact live flash could not be captured because Computer Use reported the
Mac was locked. No production change, install, or release is justified by this
investigation alone. In particular, the reported word “Refreshing” was not
independently observed; current overview source only uses that text for
accessibility.

Strict signing verification confirms `TestFlight Beta Distribution`, team
`289GY9L343`, bundle `com.niederme.AIQuota`, with the existing app group and
Keychain group. A read-only App Store Connect check on October 30 found build
447 was still the newest Mac upload (October 28, 13:28:11 UTC), before the
fixed-slot commit at 23:01:44 UTC. There is no newer uploaded Mac build to install.
The supported update path is a separately authorized Mac TestFlight release
containing `5217810`, then TestFlight's normal Update action. Updating requires
quitting/relaunching AIQuota, but not uninstalling it or clearing account data.
The current verification build is unsigned and must not replace this installed
TestFlight app. The repository has no normal signed local installer for this
distribution; `scripts/testflight.py` currently handles iOS only.

## Repeatable verification

```sh
python3 scripts/test-mac-refresh-layout.py
```

The runner compiles the production card, dial, heatmap and colors against local
package objects, with synthetic view models and four account shapes: Codex
weekly quota, Claude dual quota, Claude monthly spend, and Codex monthly credits.
It uses an offscreen AppKit host and never starts the real app, accesses live
accounts, or fetches provider data.

At widths 480, 420 and 360, each of three cycles checks a cached error, quick
refresh, success, another refresh, slow refresh, failure and recovery. Recreating
the hosting hierarchy while retaining the model exercises the view lifecycle
on reopening. Assertions cover every card rectangle, both heatmap rectangles,
the sheet fitting size, refresh accessibility, full error accessibility and
removal of stale status after success. The fixture does not invoke the real
network scheduler or simulate a real menu-bar window.

To prove the test catches the prior warning-row defect:

```sh
python3 scripts/test-mac-refresh-layout.py --skip-build --source-ref eedcef4
```

This historical-card run must fail; it does not switch the checkout or run an
old app. Each run writes `geometry-and-accessibility.json` under
`output/mac-refresh-layout/current` or `baseline`. `--skip-build` is for an
unchanged local package build only. There is no configured SwiftLint or single
aggregate check target in this repository; the native fixture supplements the
package suite and existing Python/lifecycle/site checks.

## October 30 results

- Current production card: all 63 transitions pass (252 account observations),
  including stable sheet, card and heatmap geometry and full error accessibility.
- Historical card `eedcef4`: fails geometry checks as expected.
- Full AIQuotaKit suite: 282 Swift Testing tests and 30 XCTest tests pass.
- Unsigned `AIQuota-macOS` Debug app/widget build: passes with existing warnings.
- Existing synthetic Claude lifecycle checks: 28 pass.
- Python test suite: 5 pass. Site smoke check and `git diff --check`: pass.
- Live menu-bar reopen/hover check remains blocked by the locked Mac. The
  installed TestFlight app remains unchanged at 2.0 (447).
