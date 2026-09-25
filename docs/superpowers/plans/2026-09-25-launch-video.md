# Launch Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a ~17 s 16:9 motion video of the AIQuota Mac and iOS apps in drawn device frames, ending on a paired end card that doubles as the poster.

**Architecture:** A Remotion project in `marketing/launch-video/`. A pure data timeline (`src/timeline.ts`) maps frame → gauge values; device/UI components render from those values; scene components place devices and captions with a shared camera. Audio is synthesised by a Node script into a WAV that the composition plays.

**Tech Stack:** Remotion 4, React 18, TypeScript, Vitest (pure-logic tests), Node (WAV synthesis), ffmpeg.

## Global Constraints

- Palette (iOS dark): base `#0B060F`, accent `#BF5AF2`, warning `#FF9F0A` at ≥85 %, critical `#FF453A` at ≥95 %, wash `rgb(102,31,143)`, secondary text `rgba(235,235,245,0.62)`.
- Gauge geometry: 270° arc starting at 135° (SwiftUI `trim(0, 0.75)` rotated 135°); outer ring = 5h, inner ring = 7d.
- Captions: "Know your limits." / "before they break your flow." End card: "AIQuota" / "for Mac and iOS".
- Output: 3840×2160 master, 1920×1080 web (with audio), 1920×1080 muted, poster PNG = last frame. 60 fps, ~17 s (1020 frames).
- No third-party image or audio assets.

---

### Task 1: Scaffold + timeline logic (TDD)

**Files:** Create `marketing/launch-video/{package.json,tsconfig.json,remotion.config.ts,.gitignore}`, `src/index.ts`, `src/Root.tsx`, `src/timeline.ts`, `src/timeline.test.ts`, `src/theme.ts`.

**Produces:** `usageAt(frame): { codex: {h5:number,d7:number}, claude: {h5:number,d7:number} }`; `gaugeColor(worst:number): string`; `theme` tokens; `FPS=60`, `DURATION=1020`, `BEATS` frame markers.

- [ ] Write tests: `gaugeColor(84)===accent`, `gaugeColor(85)===warning`, `gaugeColor(95)===critical`; `usageAt(0)` returns low values; `usageAt(BEATS.peak).claude.h5 >= 95`; `usageAt(BEATS.reset + 30).claude.h5 < 20`; values monotonic non-decreasing between `BEATS.macOpen` and `BEATS.peak`.
- [ ] Run `npx vitest run` → FAIL (module missing).
- [ ] Implement keyframe interpolation with eased segments.
- [ ] Run → PASS. Commit.

### Task 2: Gauge + Mac UI

**Files:** `src/ui/Gauge.tsx`, `src/ui/MacPopover.tsx`, `src/ui/MenuBar.tsx`, `src/devices/MacBookAir.tsx`.

**Consumes:** `usageAt`, `gaugeColor`, `theme`. **Produces:** `<Gauge h5 d7 size icon/>`, `<MacBookAir screen={ReactNode}/>`, `<MacDesktop usage popoverProgress/>`.

- [ ] Build components; add a `Still` composition `MacStill` in Root.
- [ ] Verify: `npx remotion still MacStill out/mac.png` and compare against `reference/mac-popover.png`. Commit.

### Task 3: iOS UI + iPhone Air frame

**Files:** `src/ui/IOSOverview.tsx`, `src/devices/IPhoneAir.tsx`.

- [ ] Build overview (title "AIQuota", toolbar pill, Codex card with usage bars, Claude card, purple wash) — omit demo banner.
- [ ] Verify with `IOSStill` still vs `reference/ios-overview-demo-dark.png`. Commit.

### Task 4: Logo + end card

**Files:** `src/ui/AppIcon.tsx` (inline SVG from `AIQuota/AppIcon.icon/Assets` on dark fill), `src/scenes/EndCard.tsx`.

- [ ] Build; verify still. Commit.

### Task 5: Scenes, camera, captions

**Files:** `src/LaunchVideo.tsx`, `src/scenes/Caption.tsx`, `src/Stage.tsx`.

- [ ] Compose beats per spec storyboard; devices positioned by interpolated camera/layout per frame.
- [ ] Verify stills at each beat (frames 60, 300, 500, 680, 1019). Commit.

### Task 6: Audio

**Files:** `scripts/make-audio.mjs` → `public/soundtrack.wav`; wire `<Audio>` in `LaunchVideo`.

- [ ] Synthesise pad (detuned sines, slow LFO, chord change at end card), gauge ticks, whooshes (filtered noise), end swell; peak-normalise to −1 dBFS. Cue times imported from `BEATS`-equivalent constants.
- [ ] Verify with `ffprobe` duration ≈ 17 s and listen. Commit.

### Task 7: Render outputs

**Files:** `scripts/render.sh`.

- [ ] Render 4K master, derive 1080p (+ muted, `-an`), extract poster from last frame.
- [ ] Verify with `ffprobe` sizes/durations and contact sheet. Commit (not `out/`).
