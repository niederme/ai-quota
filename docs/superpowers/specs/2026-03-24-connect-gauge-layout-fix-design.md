# Design: Stable Layout for Unauthenticated Gauge Slot

**Date:** 2026-03-24
**Status:** Approved

## Problem

When a service needs re-authentication, `connectGauge` in `PopoverView.swift` stacks the "Connect" button *below* the label, outside the 114×114 gauge ZStack. This makes the unauthenticated slot taller than the authenticated `CircularGaugeView`, shifting the popover height whenever one service is connected and the other isn't.

## Solution

Modify `connectGauge` so its layout is height-identical to `CircularGaugeView` in all states.

### Gauge area (114×114 ZStack)

Add the Connect button as an overlay layer inside the existing ZStack, positioned at the bottom of the arc gap:

```swift
VStack {
    Spacer()
    Button("Connect", action: action)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.bottom, 2)
}
```

This mirrors exactly how `RefreshButton` is positioned in `CircularGaugeView` — floating in the open gap at the bottom of the 270° arc.

### Caption (below the ZStack)

Replace the current `VStack(spacing: 5) { Text(label) + Button }` with a two-line caption that matches `CircularGaugeView.caption`:

```swift
VStack(spacing: 2) {
    Text(label)
        .font(.headline.bold())
    Text("Not connected")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.tertiary)
}
```

Font change: `.caption.bold.secondary` → `.headline.bold` for the label, matching the authenticated state.

## Scope

- **One file:** `AIQuota/Views/PopoverView.swift`
- **One function:** `connectGauge(icon:label:action:)`
- No changes to `CircularGaugeView`, `gaugeRow`, `statsRow`, or outer layout.

## Outcome

The unauthenticated gauge slot occupies the same height as an authenticated one. The popover height is stable regardless of auth state for each service.
