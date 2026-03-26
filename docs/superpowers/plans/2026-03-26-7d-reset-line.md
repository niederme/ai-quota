# 7-Day Reset Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a "7d Resets X" (or "7d limit reached · 7d Resets X") line below the existing 5h reset line in the `CircularGaugeView` caption when the 7-day quota is at ≥ 95% or exhausted.

**Architecture:** Two file changes: `CircularGaugeView` gains a new `weeklyResetSeconds` parameter and renders the conditional second caption line; `PopoverView` passes that value plus a corrected `secondaryLimitReached` at its four `CircularGaugeView` call sites.

**Tech Stack:** SwiftUI, Swift Testing (`@Test`, `#expect`), `swift test` via the package at `Packages/AIQuotaKit/`

---

## File Map

| Action | File | What changes |
|--------|------|--------------|
| Modify | `AIQuota/Views/CircularGaugeView.swift` | New `weeklyResetSeconds` param, `weeklyResetText` var, second caption line |
| Modify | `AIQuota/Views/PopoverView.swift` | Pass `weeklyResetSeconds` + fix `secondaryLimitReached` at 4 call sites |
| Modify | `Packages/AIQuotaKit/Tests/AIQuotaKitTests/PopoverTypographyTests.swift` | New source-text tests for the above |

---

## Task 1: Write failing tests

**Files:**
- Modify: `Packages/AIQuotaKit/Tests/AIQuotaKitTests/PopoverTypographyTests.swift`

- [ ] **Step 1: Add a new `@Test` to `PopoverTypographyTests` for the 7d reset line**

Append this test inside the `PopoverTypographyTests` struct, before the closing `}`:

```swift
@Test("7d reset line appears in gauge caption when 7d is critical")
func sevenDayResetLineInCaption() throws {
    let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
    let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)

    // CircularGaugeView: new parameter exists
    #expect(gaugeSource.contains("weeklyResetSeconds: Int"))

    // CircularGaugeView: weeklyResetText produces full "7d Resets …" strings
    #expect(gaugeSource.contains(#""7d Resets \(days)d \(hours)h""#))
    #expect(gaugeSource.contains(#""7d Resets \(hours)h \(minutes)m""#))
    #expect(gaugeSource.contains(#""7d Resets \(minutes)m""#))

    // CircularGaugeView: 7d limit reached state
    #expect(gaugeSource.contains(#""7d limit reached · \(weeklyResetText)""#))

    // PopoverView: Codex passes real weekly reset seconds and exhaustion state
    #expect(popoverSource.contains("u.weeklyResetAfterSeconds"))
    #expect(popoverSource.contains("u.isWeeklyExhausted"))

    // PopoverView: Claude passes real 7-day reset seconds and exhaustion state
    #expect(popoverSource.contains("u.sevenDayResetAfterSeconds"))
    #expect(popoverSource.contains("u.sevenDayUtilization >= 100"))
}
```

- [ ] **Step 2: Run the tests and confirm the new test fails**

```bash
cd Packages/AIQuotaKit && swift test --filter "sevenDayResetLineInCaption"
```

Expected: FAIL — the new `#expect` calls reference strings not yet in the source files.

- [ ] **Step 3: Commit the failing test**

```bash
git add Packages/AIQuotaKit/Tests/AIQuotaKitTests/PopoverTypographyTests.swift
git commit -m "test: add failing test for 7d reset line in gauge caption"
```

---

## Task 2: Implement CircularGaugeView changes

**Files:**
- Modify: `AIQuota/Views/CircularGaugeView.swift`

The `CircularGaugeView` struct currently has these parameters (lines 12–24):
```swift
let primaryPercent: Int
let primaryLimitReached: Bool
let secondaryPercent: Int
let secondaryLimitReached: Bool
let isLoading: Bool
let icon: String
let label: String
let primaryLabel: String
let secondaryLabel: String
let resetSeconds: Int       // ← 5h reset, keep this
let isRefreshing: Bool
let onRefresh: () -> Void
```

- [ ] **Step 1: Add `weeklyResetSeconds` parameter after `resetSeconds`**

In `CircularGaugeView.swift`, after the line `let resetSeconds: Int`, add:

```swift
let weeklyResetSeconds: Int
```

- [ ] **Step 2: Add `weeklyResetText` computed var after the existing `resetText` var**

The existing `resetText` (around line 157) looks like:
```swift
private var resetText: String {
    let days    = resetSeconds / 86400
    let hours   = (resetSeconds % 86400) / 3600
    let minutes = (resetSeconds % 3600) / 60
    if days > 0  { return "5h Resets \(days)d \(hours)h" }
    if hours > 0 { return "5h Resets \(hours)h \(minutes)m" }
    return "5h Resets \(minutes)m"
}
```

Add directly below it:

```swift
private var weeklyResetText: String {
    let days    = weeklyResetSeconds / 86400
    let hours   = (weeklyResetSeconds % 86400) / 3600
    let minutes = (weeklyResetSeconds % 3600) / 60
    if days > 0  { return "7d Resets \(days)d \(hours)h" }
    if hours > 0 { return "7d Resets \(hours)h \(minutes)m" }
    return "7d Resets \(minutes)m"
}
```

- [ ] **Step 3: Add the 7d reset line to `caption`**

The existing `caption` var (around line 143) is:
```swift
private var caption: some View {
    VStack(spacing: 2) {
        Text(label)
            .font(.headline.bold())
            .foregroundStyle(primaryLimitReached ? .red : .primary)

        Text(primaryLimitReached ? "5h limit reached · \(resetText)" : resetText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(primaryLimitReached ? AnyShapeStyle(.red.opacity(0.8)) : AnyShapeStyle(.tertiary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
```

Replace the entire `caption` var with:

```swift
private var caption: some View {
    VStack(spacing: 2) {
        Text(label)
            .font(.headline.bold())
            .foregroundStyle(primaryLimitReached ? .red : .primary)

        Text(primaryLimitReached ? "5h limit reached · \(resetText)" : resetText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(primaryLimitReached ? AnyShapeStyle(.red.opacity(0.8)) : AnyShapeStyle(.tertiary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)

        if !isLoading && (secondaryPercent >= 95 || secondaryLimitReached) {
            Text(secondaryLimitReached ? "7d limit reached · \(weeklyResetText)" : weeklyResetText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryLimitReached ? AnyShapeStyle(.red.opacity(0.8)) : AnyShapeStyle(.tertiary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
```

- [ ] **Step 4: Run the full test suite — expect partial pass**

```bash
cd Packages/AIQuotaKit && swift test
```

The `sevenDayResetLineInCaption` test will still fail on the `PopoverView` expectations (`u.weeklyResetAfterSeconds`, `u.isWeeklyExhausted`, etc.). All other tests should pass.

- [ ] **Step 5: Commit**

```bash
git add AIQuota/Views/CircularGaugeView.swift
git commit -m "feat: add 7d reset line to CircularGaugeView caption"
```

---

## Task 3: Wire up PopoverView

**Files:**
- Modify: `AIQuota/Views/PopoverView.swift`

There are four `CircularGaugeView(...)` call sites in `PopoverView.swift`. Each needs two changes:
1. Add `weeklyResetSeconds:` argument
2. Fix `secondaryLimitReached:` from `false` to real data

The call sites are in `codexGaugeSlot` (lines ~94–117) and `claudeGaugeSlot` (lines ~126–158).

- [ ] **Step 1: Update the Codex authenticated call site**

Find (in `codexGaugeSlot`, the `if let u = viewModel.codexUsage` branch):
```swift
CircularGaugeView(
    primaryPercent: u.hourlyUsedPercent,
    primaryLimitReached: u.limitReached,
    secondaryPercent: u.weeklyUsedPercent,
    secondaryLimitReached: false,
    isLoading: false,
    icon: "logo-openai",
    label: "Codex",
    primaryLabel: formatWindowDuration(u.hourlyWindowSeconds),
    secondaryLabel: "7d",
    resetSeconds: u.hourlyResetAfterSeconds,
    isRefreshing: viewModel.isCodexLoading,
    onRefresh: { viewModel.manualRefresh() }
)
```

Replace with:
```swift
CircularGaugeView(
    primaryPercent: u.hourlyUsedPercent,
    primaryLimitReached: u.limitReached,
    secondaryPercent: u.weeklyUsedPercent,
    secondaryLimitReached: u.isWeeklyExhausted,
    isLoading: false,
    icon: "logo-openai",
    label: "Codex",
    primaryLabel: formatWindowDuration(u.hourlyWindowSeconds),
    secondaryLabel: "7d",
    resetSeconds: u.hourlyResetAfterSeconds,
    weeklyResetSeconds: u.weeklyResetAfterSeconds,
    isRefreshing: viewModel.isCodexLoading,
    onRefresh: { viewModel.manualRefresh() }
)
```

- [ ] **Step 2: Update the Codex loading placeholder call site**

Find (in `codexGaugeSlot`, the `else` branch with `isLoading: true`):
```swift
CircularGaugeView(
    primaryPercent: 0, primaryLimitReached: false,
    secondaryPercent: 0, secondaryLimitReached: false,
    isLoading: true, icon: "logo-openai",
    label: "Codex", primaryLabel: "5h", secondaryLabel: "7d",
    resetSeconds: 0, isRefreshing: true, onRefresh: {}
)
```

Replace with:
```swift
CircularGaugeView(
    primaryPercent: 0, primaryLimitReached: false,
    secondaryPercent: 0, secondaryLimitReached: false,
    isLoading: true, icon: "logo-openai",
    label: "Codex", primaryLabel: "5h", secondaryLabel: "7d",
    resetSeconds: 0, weeklyResetSeconds: 0, isRefreshing: true, onRefresh: {}
)
```

- [ ] **Step 3: Update the Claude authenticated call site**

Find (in `claudeGaugeSlot`, the `if let u = viewModel.claudeUsage` branch):
```swift
CircularGaugeView(
    primaryPercent: u.usedPercent,
    primaryLimitReached: u.limitReached,
    secondaryPercent: Int(u.sevenDayUtilization.rounded()),
    secondaryLimitReached: false,
    isLoading: false,
    icon: "logo-claude",
    label: "Claude Code",
    primaryLabel: "5h",
    secondaryLabel: "7d",
    resetSeconds: u.resetAfterSeconds,
    isRefreshing: viewModel.isClaudeLoading,
    onRefresh: { viewModel.manualRefresh() }
)
```

Replace with:
```swift
CircularGaugeView(
    primaryPercent: u.usedPercent,
    primaryLimitReached: u.limitReached,
    secondaryPercent: Int(u.sevenDayUtilization.rounded()),
    secondaryLimitReached: u.sevenDayUtilization >= 100,
    isLoading: false,
    icon: "logo-claude",
    label: "Claude Code",
    primaryLabel: "5h",
    secondaryLabel: "7d",
    resetSeconds: u.resetAfterSeconds,
    weeklyResetSeconds: u.sevenDayResetAfterSeconds,
    isRefreshing: viewModel.isClaudeLoading,
    onRefresh: { viewModel.manualRefresh() }
)
```

- [ ] **Step 4: Update the Claude loading placeholder call site**

Find (in `claudeGaugeSlot`, the `else` branch with `isLoading: true`):
```swift
CircularGaugeView(
    primaryPercent: 0, primaryLimitReached: false,
    secondaryPercent: 0, secondaryLimitReached: false,
    isLoading: true, icon: "logo-claude",
    label: "Claude Code", primaryLabel: "5h", secondaryLabel: "7d",
    resetSeconds: 0, isRefreshing: true, onRefresh: {}
)
```

Replace with:
```swift
CircularGaugeView(
    primaryPercent: 0, primaryLimitReached: false,
    secondaryPercent: 0, secondaryLimitReached: false,
    isLoading: true, icon: "logo-claude",
    label: "Claude Code", primaryLabel: "5h", secondaryLabel: "7d",
    resetSeconds: 0, weeklyResetSeconds: 0, isRefreshing: true, onRefresh: {}
)
```

- [ ] **Step 5: Run the full test suite — expect all tests pass**

```bash
cd Packages/AIQuotaKit && swift test
```

Expected: all 36 tests pass (35 existing + 1 new).

- [ ] **Step 6: Commit**

```bash
git add AIQuota/Views/PopoverView.swift
git commit -m "feat: wire 7d reset seconds and limit state into CircularGaugeView"
```
