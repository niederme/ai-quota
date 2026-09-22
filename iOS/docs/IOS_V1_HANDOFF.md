# iOS v1 handoff, September 22, 2026

## Updated splash implementation

The owner resumed splash work after the initial checkpoint. The native launch
screen now puts the standalone gauge arcs, enlarged round indicators, and
sparkle directly on the app's purple gradient, with no rounded-square icon tile.

- `App/SplashScreen.storyboard` uses `LaunchArtwork` and `LaunchBackground`.
- Foreground assets now use the approved Figma `icon-1` glass artwork, exported
  as transparent 144/288/432px PNGs. Both appearances use the approved export.
  Source link and 1024px master are in `iOS/Design/Splash`.
- `scripts/generate-ios-splash.py` regenerates only gradient backgrounds,
  preserving the approved Figma foreground.
- The round indicators retain the source radius of 51, enlarged from 44 in PR #70.
- `scripts/export-ios-launch-icon.sh` regenerates this splash and the native
  onboarding icon images. The old launch-tile asset is removed.
- The initial tile checkpoint was merged in PR #71. No startup delay, TestFlight
  upload, or App Store submission is part of either splash change.

## Verification

The latest Figma exports were checked for dimensions and transparency and copied
into the open checkout. This asset replacement has not been run on Karin Air.
The device run and simulator observations below refer to the prior artwork.

The Debug simulator build passed. Native launch screenshots were inspected in
light and dark appearances on a fresh iPhone simulator. The storyboard was
renamed to `SplashScreen` after a reused simulator retained a blank launch
snapshot. The existing Xcode instance built, installed, and reported running
`AIQuota-iOS` on Karin Air. Physical-device visual confirmation remains with
the owner.

## Reliability work remains open

Adding a launch screen did not diagnose or fix the reported slow/blank startup.
Cold-launch timing was discussed but deferred when the owner chose splash work.
After the visual pass, measure startup to the first usable screen, then continue
the existing roadmap's session renewal, stale/offline widget behavior,
notification delivery, and reinstall/reset device checks.

## Local workflow

Use the Xcode instance already open at `/Applications/Xcode.app`, with
`AIQuota-iOS` and `Karin Air`. The duplicate Xcode-beta GUI opened during this
task was quit and only the original process remained. Do not open a second
Xcode or reopen a worktree automatically. Using Xcode-beta's tools through a
command-local `DEVELOPER_DIR` does not require launching its GUI.

The main checkout has pre-existing Xcode-generated project/plist/scheme and
user-settings differences. Preserve them when integrating; do not stash or
silently discard them. Product source-of-truth settings remain in project.yml.

The review-account notes are a draft. Real passwords and unused backup codes
belong only in App Store Connect. Free Codex usage was observed working; the
tested free Claude account was blocked by the provider's Pro/Max requirement.
Demo coverage does not establish live reviewer access or App Review approval.

## TestFlight build 34

Version 0.1.0 (34) archived and uploaded successfully on September 22, 2026,
from codex/ios-gradient-splash with the approved Figma artwork. The archive
contains SplashScreen.storyboardc and selects it in Info.plist. Apple had not
yet exposed build 34 at the initial processing check. Upload reported a missing
GoogleAppMeasurement dSYM warning but completed successfully.

Release record: `/Users/niederme/Library/Logs/AIQuota/TestFlight/2026-09-22-170055-996e87`.
Resume status checks with `python3 scripts/testflight.py status --run /Users/niederme/Library/Logs/AIQuota/TestFlight/2026-09-22-170055-996e87 --wait 0`. Do not upload again for processing delays.
