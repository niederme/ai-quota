# Gauge Center Icon Tint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tint the center icon of every gauge (menubar sparkle, popover service logo, widget service logo) to match the gauge's status color (purple when healthy, amber at ≥ 85%, red at ≥ 95% or limit reached).

**Architecture:** Three one-line changes in three existing files. Each file already computes a status color (`sharedColor` in `GaugeImageMaker`, `statusColor` in `CircularGaugeView` and `WidgetGaugeView`) — the change is simply to pass that color to the center icon draw call instead of the current hardcoded neutral color.

**Tech Stack:** Swift, SwiftUI, AppKit/CoreGraphics, Xcode asset catalogs

---

## File Map

| File | Change |
|------|--------|
| `Packages/AIQuotaKit/Sources/AIQuotaKit/Drawing/GaugeImageMaker.swift` | Modify sparkle fill (line ~110) |
| `AIQuota/Views/CircularGaugeView.swift` | Modify icon `foregroundStyle` (line ~95) |
| `AIQuotaWidget/Views/WidgetGaugeView.swift` | Modify icon `foregroundStyle` (line ~78) |

---

### Task 1: Verify icon assets use Template Image rendering

The `.foregroundStyle` modifier in SwiftUI is silently ignored for images not set to "Template Image" rendering. Check this before making code changes to avoid a confusing no-op.

**Files:**
- Inspect: `AIQuota/Assets.xcassets` (or wherever the Claude/Codex icon assets live)

- [ ] **Step 1: Find the icon asset names**

Open `CircularGaugeView.swift` and `WidgetGaugeView.swift` and note the string value passed as `icon:` at the call sites (e.g. `"claude"`, `"codex"`). These are the xcassets image names to check.

- [ ] **Step 2: Check rendering mode in Xcode**

In Xcode's asset catalog navigator, select each icon image set. In the Attributes inspector, confirm **Render As** is set to **Template Image**. If it shows "Original Image" or "Default", change it to "Template Image" and save.

- [ ] **Step 3: Commit if any asset was changed**

```bash
git add AIQuota/Assets.xcassets
git commit -m "chore: set service icon assets to Template Image rendering"
```

Skip this step if no changes were needed.

---

### Task 2: Tint menubar sparkle in GaugeImageMaker

**Files:**
- Modify: `Packages/AIQuotaKit/Sources/AIQuotaKit/Drawing/GaugeImageMaker.swift`

- [ ] **Step 1: Locate the sparkle fill**

In `GaugeImageMaker.swift`, find the `// ── Sparkle` section (~line 97). The fill color is set just before `ctx.fillPath()`:

```swift
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
```

- [ ] **Step 2: Replace with status-colored fill**

`sharedColor` is already computed earlier in the same function (line ~65). Replace the hardcoded white with:

```swift
ctx.setFillColor(sharedColor.copy(alpha: 0.9) ?? sharedColor)
```

`sharedColor` is always an sRGB `CGColor` so `copy(alpha:)` will not return nil in practice.

- [ ] **Step 3: Build and verify**

Build the `AIQuota` scheme (Cmd+B). Run the app. With healthy usage (< 85%), the menubar sparkle should remain white. To verify amber/red, temporarily lower a threshold in `ringColor` (e.g. change `0.85` to `0.0`) to force the amber state, confirm the sparkle tints amber, then revert.

- [ ] **Step 4: Commit**

```bash
git add Packages/AIQuotaKit/Sources/AIQuotaKit/Drawing/GaugeImageMaker.swift
git commit -m "feat: tint menubar gauge sparkle to match status color"
```

---

### Task 3: Tint service logo in CircularGaugeView

**Files:**
- Modify: `AIQuota/Views/CircularGaugeView.swift`

- [ ] **Step 1: Locate the icon Image**

In the `arcs` computed property, find the centre `VStack` (~line 90). The logo is:

```swift
Image(icon)
    .resizable()
    .scaledToFit()
    .frame(width: 15, height: 15)
    .foregroundStyle(.secondary)
```

- [ ] **Step 2: Change foregroundStyle**

Replace `.foregroundStyle(.secondary)` with:

```swift
.foregroundStyle(statusColor)
```

`statusColor` is a computed property already defined on this view (lines ~27–33). In the healthy state it returns `Self.accent` (purple), matching the arc fill.

- [ ] **Step 3: Build and verify**

Build and run. Open the popover. The service logo (Claude/Codex icon) should appear purple when healthy. If assets weren't set to Template Image in Task 1, the color won't apply — revisit Task 1.

- [ ] **Step 4: Commit**

```bash
git add AIQuota/Views/CircularGaugeView.swift
git commit -m "feat: tint popover gauge service logo to match status color"
```

---

### Task 4: Tint service logo in WidgetGaugeView

**Files:**
- Modify: `AIQuotaWidget/Views/WidgetGaugeView.swift`

- [ ] **Step 1: Locate the icon Image**

In the centre `VStack` (~line 73), find:

```swift
Image(icon)
    .resizable()
    .scaledToFit()
    .frame(width: iconPt, height: iconPt)
    .foregroundStyle(.secondary)
```

- [ ] **Step 2: Change foregroundStyle**

Replace `.foregroundStyle(.secondary)` with:

```swift
.foregroundStyle(statusColor)
```

Note: `WidgetGaugeView.statusColor` only checks `primaryLimitReached` (unlike the popover which also checks `secondaryLimitReached`). This is consistent with the widget's existing ring behavior — no change needed to the status logic.

- [ ] **Step 3: Build and verify**

Build the widget target and preview it in Xcode (or run a simulator). Confirm the logo color matches the arc color.

- [ ] **Step 4: Commit**

```bash
git add AIQuotaWidget/Views/WidgetGaugeView.swift
git commit -m "feat: tint widget gauge service logo to match status color"
```
