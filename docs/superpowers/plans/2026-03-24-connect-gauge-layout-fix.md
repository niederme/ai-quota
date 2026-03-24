# Connect Gauge Layout Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the unauthenticated gauge slot in the popover height-identical to the authenticated `CircularGaugeView` so the popover never shifts height when a service needs re-auth.

**Architecture:** All changes are confined to the `connectGauge(icon:label:action:)` function in `PopoverView.swift`. No new files, no new types. The fix normalizes four things: outer VStack spacing, arc stroke weights, button placement, and caption structure — all to match what `CircularGaugeView` already does.

**Tech Stack:** SwiftUI (macOS), no external dependencies.

---

## File Map

| File | Change |
|------|--------|
| `AIQuota/Views/PopoverView.swift` | Modify `connectGauge` only |
| `Packages/AIQuotaKit/Tests/AIQuotaKitTests/PopoverTypographyTests.swift` | Add snapshot/layout test if pattern exists; otherwise skip (see Task 1) |

---

### Task 1: Understand the existing test baseline

**Files:**
- Read: `Packages/AIQuotaKit/Tests/AIQuotaKitTests/PopoverTypographyTests.swift`
- Read: `AIQuota/Views/PopoverView.swift:236-269` (the current `connectGauge` function)
- Read: `AIQuota/Views/CircularGaugeView.swift:47-53` (the `body` VStack)

- [ ] **Step 1: Read the existing test file**

Open `Packages/AIQuotaKit/Tests/AIQuotaKitTests/PopoverTypographyTests.swift` and understand what it tests. Note whether it exercises `connectGauge` or measures layout heights.

- [ ] **Step 2: Read the current connectGauge implementation**

Open `PopoverView.swift` lines 236–269. Confirm the four things that need changing:
1. Outer `VStack(spacing: 8)` — should be `4`
2. Outer arc: `lineWidth: 9, lineCap: .round` — should be `8, .butt`
3. Inner arc: `lineWidth: 7, lineCap: .round` — should be `8, .butt`
4. Caption: `Text(label).caption.bold.secondary + Button(below ZStack)` — should be `headline.bold + "Not connected" subtitle`, with button moved inside ZStack

- [ ] **Step 3: Read CircularGaugeView body**

Confirm `VStack(spacing: 4)` at line 48 and the `RefreshButton` pattern at lines 124–136 (the `VStack { Spacer(); button.padding(.bottom, 2) }` inside the arcs ZStack).

---

### Task 2: Implement the fix

**Files:**
- Modify: `AIQuota/Views/PopoverView.swift:236-269`

- [ ] **Step 1: Replace `connectGauge` with the corrected version**

Replace the entire `connectGauge` function body. The result should be:

```swift
private func connectGauge(icon: String, label: String, action: @escaping () -> Void) -> some View {
    VStack(spacing: 4) {                                         // was spacing: 8
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 8, lineCap: .butt))  // was 9, .round
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 8, lineCap: .butt))  // was 7, .round
                .rotationEffect(.degrees(135))
                .padding(8)
            VStack(spacing: 2) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(CircularGaugeView.accent.opacity(0.35))
                Text("—")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.quaternary)
            }
            // Connect button in arc gap — mirrors RefreshButton placement in CircularGaugeView
            VStack {
                Spacer()
                Button("Connect", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.bottom, 2)
            }
        }
        .frame(width: 114, height: 114)

        VStack(spacing: 2) {                                     // was VStack(spacing: 5) + Button below
            Text(label)
                .font(.headline.bold())                          // was .caption.bold / .secondary
            Text("Not connected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
    .multilineTextAlignment(.center)
}
```

- [ ] **Step 2: Build the project**

```bash
cd /path/to/repo && xcodegen generate && xcodebuild build -scheme AIQuota -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

If it fails, read the error output and fix before continuing.

- [ ] **Step 3: Run existing tests**

```bash
xcodebuild test -scheme AIQuota -destination 'platform=macOS' 2>&1 | grep -E 'Test Suite|passed|failed|error'
```

Expected: all previously passing tests still pass. No new failures.

- [ ] **Step 4: Commit**

```bash
git add AIQuota/Views/PopoverView.swift
git commit -m "fix: stable layout for unauthenticated gauge slot

Move Connect button inside arc ZStack (mirrors RefreshButton pattern),
normalize arc lineWidth/lineCap to match CircularGaugeView, change outer
VStack spacing from 8 to 4, and update caption to headline.bold + 'Not
connected' subtitle — making connectGauge height-identical to
CircularGaugeView in all auth states."
```

---

### Task 3: Manual visual verification

No automated snapshot tests exist for this layout. Verify visually.

- [ ] **Step 1: Build and run AIQuota**

Open `AIQuota.xcodeproj` in Xcode, run the `AIQuota` scheme on Mac.

- [ ] **Step 2: Trigger the unauthenticated state**

In Settings, disconnect one service (sign out). The popover should show one authenticated gauge and one unauthenticated slot.

Verify:
- The two columns are the same height — the Divider between them is straight
- The Connect button sits in the arc's bottom gap (same position as the refresh button in the authenticated gauge)
- The label uses the same bold headline font as the authenticated side
- "Not connected" appears as a dim subtitle below the label
- The popover height does not change when toggling auth state

- [ ] **Step 3: Check both-unauthenticated state**

Sign out of both services. Both slots should render `connectGauge`. Verify the popover shows a symmetric layout with no unexpected height or spacing differences.
