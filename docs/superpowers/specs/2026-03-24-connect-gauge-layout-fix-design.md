# Design: Stable Layout for Unauthenticated Gauge Slot

**Date:** 2026-03-24
**Status:** Approved

## Problem

When a service needs re-authentication, `connectGauge` in `PopoverView.swift` stacks the "Connect" button *below* the label, outside the 114×114 gauge ZStack. This makes the unauthenticated slot taller than the authenticated `CircularGaugeView`, shifting the popover height whenever one service is connected and the other isn't.

## Solution

Modify `connectGauge` so its layout is height-identical and visually consistent with `CircularGaugeView` in all states.

### 1. Arc strokes: normalize lineCap and lineWidth

The current `connectGauge` uses `lineWidth: 9` / `lineWidth: 7` and `lineCap: .round`. `CircularGaugeView` uses `lineWidth: 8` on both strokes and `lineCap: .butt`. Change `connectGauge` to match:

- Both strokes: `lineWidth: 8`, `lineCap: .butt`

### 2. Connect button: move inside the ZStack

Remove the button from the VStack below the arcs and add it as an overlay layer inside the 114×114 ZStack, positioned at the bottom of the arc gap — mirroring exactly how `RefreshButton` is placed in `CircularGaugeView`:

```swift
VStack {
    Spacer()
    Button("Connect", action: action)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.bottom, 2)
}
```

### 3. Outer VStack spacing: match CircularGaugeView

The outer `VStack` in `connectGauge` uses `spacing: 8`; `CircularGaugeView` uses `spacing: 4`. Change to `VStack(spacing: 4)`.

### 4. Caption: match CircularGaugeView.caption

Replace the current `VStack(spacing: 5) { Text(label).caption.bold.secondary + Button }` with:

```swift
VStack(spacing: 2) {
    Text(label)
        .font(.headline.bold())
        // foregroundStyle defaults to .primary — intentional change from .secondary
    Text("Not connected")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.tertiary)
}
```

Note: `CircularGaugeView.caption` conditionally changes colors to `.red` when `primaryLimitReached` is true. `connectGauge` has no equivalent error condition, so `.primary` / `.tertiary` are correct and the divergence is intentional.

## Scope

- **One file:** `AIQuota/Views/PopoverView.swift`
- **One function:** `connectGauge(icon:label:action:)`
- No changes to `CircularGaugeView`, `gaugeRow`, `statsRow`.

## Edge Cases

- **Both services unauthenticated:** both slots render `connectGauge`. Since each slot is now self-consistent, this is the degenerate case of the same fix applied twice — no separate handling needed.
- **`gaugeRow` uses `alignment: .top`:** the Divider between slots stretches to the taller slot. Once both slots are height-equal this is a non-issue; the `.top` alignment is unchanged.

## Outcome

The unauthenticated gauge slot occupies the same height as an authenticated one — same ZStack size, same arc weight, same two-line caption structure. The popover height is stable regardless of auth state for each service.
