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

- Add parameter: `weeklyResetSeconds: Int` alongside the existing `resetSeconds` parameter (which remains unchanged as the 5h reset input).
- Add computed var `weeklyResetText` — returns the **full** string including prefix, e.g. `"7d Resets 3d 2h"`, mirroring the existing `resetText` pattern. Format: if days > 0 → `"7d Resets Xd Xh"`, if hours > 0 → `"7d Resets Xh Xm"`, else `"7d Resets Xm"`.
- In `caption`: when `!isLoading && (secondaryPercent >= 95 || secondaryLimitReached)`, render a second `Text` line below the existing reset line. The `!isLoading` guard is needed to protect against stale `secondaryPercent` values during a refresh cycle.

### `PopoverView`

Pass both `weeklyResetSeconds` and the corrected `secondaryLimitReached` into each `CircularGaugeView` call:

| Slot | `weeklyResetSeconds` | `secondaryLimitReached` |
|---|---|---|
| Codex (authenticated, usage loaded) | `u.weeklyResetAfterSeconds` | `u.isWeeklyExhausted` |
| Codex (loading placeholder) | `0` | `false` |
| Claude (authenticated, usage loaded) | `u.sevenDayResetAfterSeconds` | `u.sevenDayUtilization >= 100` |
| Claude (loading placeholder) | `0` | `false` |

Note: `secondaryLimitReached` was previously hardcoded `false` in both call sites — this change wires it to real data.

## Out of scope

- Widget views (not updated in this change)
- Notification triggers based on 7d status
