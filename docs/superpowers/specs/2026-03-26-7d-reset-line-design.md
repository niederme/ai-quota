# 7-Day Reset Line in Caption

**Date:** 2026-03-26

## Problem

When the 7-day usage ring turns red, the user has no indication of when the 7-day window resets. The caption below each gauge only shows the 5-hour reset time, leaving the user without actionable context when the longer-term quota is nearly or fully exhausted.

## Design

### Trigger condition

Show the 7d reset line when `secondaryPercent >= 95 || secondaryLimitReached`.

### Display text

| State | Second caption line |
|---|---|
| 7d ≥ 95%, not exhausted | `7d Resets 3d 2h` |
| 7d limit reached | `7d limit reached · 7d Resets 1h 33m` |

Time format: same `Xd Xh` / `Xh Xm` / `Xm` pattern used by the existing 5h reset line.

### Styling

- "7d Resets …" — `.tertiary` foreground, same as the 5h reset line
- "7d limit reached · …" — red foreground (`.red.opacity(0.8)`), same as the 5h limit reached prefix

## Changes

### `CircularGaugeView`

- Add parameter: `weeklyResetSeconds: Int`
- Add computed var `weeklyResetText` — formats `weeklyResetSeconds` into `Xd Xh` / `Xh Xm` / `Xm`
- In `caption`: when `secondaryPercent >= 95 || secondaryLimitReached`, render a second `Text` line below the existing reset line

### `PopoverView`

Pass the weekly reset seconds into each `CircularGaugeView` call:

| Slot | Value |
|---|---|
| Codex (authenticated, usage loaded) | `u.weeklyResetAfterSeconds` |
| Codex (loading placeholder) | `0` |
| Claude (authenticated, usage loaded) | `u.sevenDayResetAfterSeconds` |
| Claude (loading placeholder) | `0` |

## Out of scope

- Widget views (not updated in this change)
- Notification triggers based on 7d status
