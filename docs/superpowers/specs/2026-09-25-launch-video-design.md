# Launch video (Mac + iOS) — design

## Purpose

A short motion piece showing both AIQuota apps in action inside device frames. First cut is 16:9 for launch/social; a square cut will later replace the website hero video (`docs/assets/aiquota-demo-inline.mp4`). The existing video is not a starting point.

## Storyboard (16:9, ~17 s, 60 fps)

| Time | Shot |
|---|---|
| 0–4 s | Open tight on a MacBook Air, slow push-in. Menu bar gauge icons tick, the AIQuota popover drops open, Codex + Claude gauges climb. |
| 4–6.5 s | Caption **"Know your limits."** fades up; the Mac glides aside. |
| 6.5–10 s | iPhone Air rises in showing the iOS overview. Both devices display the same demo data and animate in sync. |
| 10–12.5 s | Caption **"before they break your flow."** Claude 5h gauge climbs through warning orange to critical red (~95 %), then resets and refills purple. |
| 12.5–17 s | End card: both devices side by side on the left; right side shows the dark-mode app icon, **AIQuota**, and "for Mac and iOS". Holds. The final frame is exported as the poster. |

## Look

- Palette follows the iOS brand evolution (dark appearance): base `#0B060F`, accent `#BF5AF2`, warning `#FF9F0A`, critical `#FF453A`, top purple wash `rgb(102,31,143)` fading down, radial accent glow — the same recipe as `OverviewBackground`.
- Type: SF Pro Display (system font on macOS render host), white/`#EBEBF5` at 62 % for secondary.
- Logo: dark-appearance app icon composed from `AIQuota/AppIcon.icon/Assets/*.svg` on the dark fill `display-p3(0.065, 0.05, 0.13)`.
- Device frames drawn in SVG/CSS (no third-party assets). Official Apple product bezels can be swapped in later without touching scenes.
- Motion: Apple-style ease-in-out, springs for settles, no hard cuts.

## UI

Rebuilt as React components that match the shipping apps (not screen captures), so every value change can be timed to the frame:
- **Mac:** menu bar with two AIQuota gauge icons, popover matching `PopoverView` (dual gauges, plan/credits rows, footer).
- **iOS:** overview matching `OverviewView` in dark mode (service cards with dual rings, purple wash). Reference screenshots come from each app's demo mode.
- One shared data timeline drives both devices so they stay in sync.

## Audio

Original, generated in-repo (no licensing): soft synth pad, gentle ticks as gauges move, whooshes on device moves, low swell into the end card. Delivered as a separate stem mixed into the master so a licensed track can replace it. The site version ships muted.

## Tooling & layout

- Remotion project in `marketing/launch-video/` (React, renders frames + muxes audio via ffmpeg). `node_modules/` and `out/` ignored.
- One composition parameterised by aspect so a 1:1 cut reuses the scenes.

## Deliverables

- `out/aiquota-launch-4k.mp4` — 3840×2160, H.264, with audio
- `out/aiquota-launch-1080p.mp4` — web-sized, with audio
- `out/aiquota-launch-1080p-muted.mp4` — site loop
- `out/aiquota-launch-poster.png` — final frame

## Out of scope (now)

Square cut, website integration, App Store preview videos.

## Revision 2 (after first-cut review)

Feedback: too much purple, heavy and moody; laptop screen too detailed; the Mac should show a real AI session; more dynamic camera; better audio. Decisions:

- **Framing lightens, product UI stays dark.** Light neutral stage (`#F5F5F7`), silver MacBook Air, white iPhone Air, dark ink captions. The AIQuota UIs keep their dark appearance; the Mac desktop uses a neutral graphite wallpaper so purple belongs only to AIQuota.
- **Mac at a "larger text" scaled resolution** (1180×767 pt) so UI reads bigger with less detail.
- **Opens on a generic AI coding-agent session**: prompt typed, streamed reply with tool steps, code, and a climbing token counter. The camera follows the newest line, whip-zooms out, the cursor clicks AIQuota in the menu bar, then punches into the popover.
- **Camera system** (focus point + log-space zoom) drives pushes, pans and pull-backs; the phone swings in with a 3D tilt; the camera pushes into the phone for the warning/reset beat.
- **Length ~20 s** (1200 frames). Beats shared with the soundtrack via `src/beats.json`.
- **Soundtrack rebuilt**: Karplus–Strong plucked arpeggios, warm pad, soft groove (kick, snap, shaker), chord changes on story beats, a drop and riser into the reset, typing/click foley.
