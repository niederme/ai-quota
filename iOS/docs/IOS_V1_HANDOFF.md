# iOS v1 handoff, September 22, 2026

Paused at the owner's request until usage resets. Do not resume work automatically.

## Working checkpoint

- Native `App/LaunchScreen.storyboard` centers a 112-point icon on adaptive
  `OverviewBase`. No artificial delay or network gate was added.
- `Assets.xcassets/LaunchIcon.imageset` contains light/dark 1x, 2x, and 3x
  renditions exported directly from `AIQuota/AppIcon.icon`, using Icon Composer's
  design-generation 27 renderer. Regenerate with
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/export-ios-launch-icon.sh`.
- The launch branch was rebased onto `2e3fde2`, which includes PR #70's iOS
  surfaces, gauge weights, and icon indicators. Exports were then refreshed.
- PR #70 enlarged both round indicator radii from 44 to 51 source units (about
  16% larger diameter). Launch and onboarding exports now both reflect that
  source. The old one-ring iOS `AppIcon.appiconset` was removed so the layered
  `AIQuota/AppIcon.icon` is authoritative. The export script updates launch and
  onboarding together. Any further indicator-size adjustment belongs in the
  source SVGs, followed by the export command.
- Simulator Debug build passed. Native light/dark launch screens were visually
  checked on iPhone Duo, and a normal launch reached the dashboard. The owner
  ran on Karin Air and reported that the icon looked good on the splash.
- This is local build/device work. No TestFlight upload or App Store submission.

## Next visual change, requested but not implemented

Put the standalone gauge-and-spark artwork directly over the app's purple
gradient, removing the rounded-square icon tile. Keep the Icon Composer file as
the artwork source and preserve the current restrained 2026 appearance.

The native `ictool --export-image` command includes the icon enclosure. Trials
using a temporary `.icon` copy with transparent solid fill and `fill: none`
still produced the rounded-square backing. No experimental icon source or
foreground assets were added to the repository. The current working splash
still intentionally has the icon tile.

Next investigate an export of just the foreground. A possible fallback is to
compose the same source SVG layers as transparent vector artwork, with an
explicitly static highlight treatment. Do not describe that as native or live
Liquid Glass. The proposed generator/storyboard patch was not applied.

Reuse `OverviewBackground` in `App/OverviewView.swift` as the color/gradient
reference: adaptive base, top-to-bottom purple fade, upper-right radial glow.
Check light/dark contrast, especially the sparkle on the light background, and
iPhone/iPad portrait and landscape before replacing the working checkpoint.

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
