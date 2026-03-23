# Gauge Center Icon Tint — Design Spec

**Date:** 2026-03-23
**Status:** Approved

## Summary

Tint the icon rendered in the center of every gauge to match the gauge's status color. Currently the center icons are always neutral (white in the menubar sparkle; `.secondary` gray in the popover and widget service logos). After this change they will use the same status color as the arcs and percentage text — white/purple when healthy, amber at ≥ 85%, red at ≥ 95% or limit reached.

## Affected Files

| File | Icon | Current style | New style |
|------|------|---------------|-----------|
| `Packages/AIQuotaKit/Sources/AIQuotaKit/Drawing/GaugeImageMaker.swift` | 4-pointed sparkle (CGContext fill) | `CGColor(red:1, green:1, blue:1, alpha:0.9)` (hardcoded white) | `sharedColor.copy(alpha: 0.9) ?? sharedColor` |
| `AIQuota/Views/CircularGaugeView.swift` | Service logo (SwiftUI `Image`) | `.foregroundStyle(.secondary)` | `.foregroundStyle(statusColor)` |
| `AIQuotaWidget/Views/WidgetGaugeView.swift` | Service logo (SwiftUI `Image`) | `.foregroundStyle(.secondary)` | `.foregroundStyle(statusColor)` |

## Color Mapping

Reuses the already-computed status colors with no new logic:

| State | Menubar (`sharedColor`) | Popover/Widget (`statusColor`) |
|-------|------------------------|-------------------------------|
| Healthy (< 85%) | White `(1, 1, 1)` | Purple `(0.62, 0.22, 0.93)` |
| Warning (≥ 85%) | Amber `(1.0, 0.65, 0.0)` | Amber `(1.0, 0.65, 0.0)` |
| Critical (≥ 95% or limit reached) | Red `(1.0, 0.25, 0.25)` | Red `.red` |

Note: in the healthy state the menubar sparkle remains white (unchanged visually), while the popover/widget logo shifts from `.secondary` gray to purple — a small bonus that makes the logo match the ring color.

## Changes

### `GaugeImageMaker.swift`

Replace the hardcoded sparkle fill color with `sharedColor` (already in scope at that point):

```swift
// Before
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))

// After
ctx.setFillColor(sharedColor.copy(alpha: 0.9) ?? sharedColor)
```

### `CircularGaugeView.swift`

```swift
// Before
.foregroundStyle(.secondary)

// After
.foregroundStyle(statusColor)
```

### `WidgetGaugeView.swift`

```swift
// Before
.foregroundStyle(.secondary)

// After
.foregroundStyle(statusColor)
```

## Out of Scope

- `UsageGaugeView` (linear gauge) — has no center icon.
- No threshold logic changes.
- No animation changes.
