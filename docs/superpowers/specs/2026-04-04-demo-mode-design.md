# Demo Mode Design

**Date:** 2026-04-04
**Goal:** A one-off build of AIQuota that auto-plays through all usage states as a scripted timelapse — suitable for screen-recording a marketing video. Disconnected from real data and auth.

---

## Scope

- macOS only (the app is macOS-only)
- Throwaway build — no polish, no user-facing cleanup required
- Must show both Claude and Codex gauges with all visible states: green, amber (85%), red (100%), 5h limit reached, 5h reset, 7d climbing, 7d amber, 7d limit reached, final hold
- Close and reopen popover → sequence resets from the beginning

---

## Approach: `DemoQuotaViewModel` swapped at app entry point

A standalone `DemoQuotaViewModel` with the same `@Observable` surface as `QuotaViewModel` drives the existing views with scripted keyframes. Injected via `#if DEMO_MODE` compilation flag in `AIQuotaApp`. No production code paths are altered.

---

## Changes Required

### 1. Public demo inits on model structs (AIQuotaKit package)

`ClaudeUsage` has no public memberwise init (init is implicit/internal).
`CodexUsage` has a `private init(...)` used only by its static placeholders.

Add a `public init(...)` to each so demo code outside the module can construct arbitrary values.

**Files:**
- `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/ClaudeUsage.swift` — add `public init`
- `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/CodexUsage.swift` — change `private init` to `public init`

### 2. `DemoQuotaViewModel.swift` (new file in `AIQuota/`)

`@Observable final class DemoQuotaViewModel` — same published surface as `QuotaViewModel`.

**Properties (matching the real ViewModel's surface used by views):**
```swift
var claudeUsage: ClaudeUsage?
var codexUsage: CodexUsage?
var isClaudeLoading: Bool
var isCodexLoading: Bool
var claudeState: AuthState        // hardcoded .authenticated
var codexState: AuthState         // hardcoded .authenticated
var enrolledServices: Set<ServiceType>  // hardcoded [.claude, .codex]
var activeService: ServiceType    // default .codex
var settings: AppSettings         // AppSettings.default
var lastRefreshedAt: Date?
var claudeError: NetworkError?
var codexError: NetworkError?
```

**Computed aliases (used by `AIQuotaApp` menu bar calculations):**
```swift
var isClaudeAuthenticated: Bool { true }
var isCodexAuthenticated:  Bool { true }
var isRestoringSession:    Bool { false }
var isClaudeEnrolled:      Bool { true }
var isCodexEnrolled:       Bool { true }
var isLoading:             Bool { isClaudeLoading || isCodexLoading }
var usage:                 CodexUsage? { codexUsage }   // backward-compat alias
```

**Keyframe type:**
```swift
struct DemoFrame {
    var claudeFiveH: Int
    var claudeSevenD: Int
    var claudeResetSecs: Int       // 5h window reset countdown
    var claudeWeeklyResetSecs: Int // 7d window reset countdown
    var codexFiveH: Int
    var codexSevenD: Int
    var codexResetSecs: Int
    var codexWeeklyResetSecs: Int
    var tickDuration: Double        // seconds to hold this frame
}
```

**Timeline — scripted keyframes:**

The sequence plays through ~3 full 5h cycles while 7d climbs, then ends frozen. All frames use plausible reset countdown values.

| Phase | Claude 5h | Claude 7d | Codex 5h | Codex 7d | Notes |
|---|---|---|---|---|---|
| Loading | — | — | — | — | `isLoading = true` for 1s, then data appears |
| Climb 1a | 10% | 3% | 8% | 2% | Green |
| Climb 1b | 35% | 6% | 28% | 5% | Green |
| Climb 1c | 65% | 9% | 55% | 7% | Green |
| Amber 1 | 87% | 11% | 83% | 9% | Amber (≥85%) — reset countdown visible |
| Limit 1 | 100% | 13% | 98% | 11% | Red — "5h limit reached · resets in 4h 12m" |
| Reset 1 | 0% | 15% | 0% | 13% | Snap to 0, 7d keeps value |
| Climb 2a | 20% | 22% | 15% | 19% | Green |
| Climb 2b | 55% | 27% | 45% | 24% | Green |
| Amber 2 | 88% | 31% | 82% | 28% | Amber |
| Limit 2 | 100% | 33% | 100% | 30% | Red — both hit 5h limit |
| Reset 2 | 0% | 36% | 0% | 33% | |
| Climb 3a | 30% | 50% | 22% | 46% | 7d amber approaching |
| Amber 3 | 86% | 62% | 78% | 58% | 5h amber; "7d Resets Xd Xh" now visible (≥85 not yet) |
| Limit 3 | 100% | 65% | 96% | 61% | 5h red |
| Reset 3 | 0% | 68% | 0% | 64% | |
| Climb 4a | 15% | 78% | 10% | 73% | 7d amber now (≥85 not yet on Codex, ≥85 approaching Claude) |
| Climb 4b | 40% | 88% | 30% | 80% | Claude 7d amber (≥85%); "7d Resets Xd Xh" |
| **Final** | 40% | 100% | 30% | 80% | Claude 7d limit reached (red), Codex 7d ~80% — **stop** |

Frame tick durations: most frames 0.5–0.8s. "Loading" hold is 1.0s. Reset snap frames are 0.3s. Final frame holds indefinitely (no next frame).

**Timer and reset logic:**
```swift
private var timer: Timer?
private var frameIndex = 0

func reset() {
    timer?.invalidate()
    frameIndex = 0
    claudeUsage = nil
    codexUsage  = nil
    isClaudeLoading = true
    isCodexLoading  = true
    lastRefreshedAt = nil
    advanceAfter(1.0) // loading state
}

private func advance() {
    guard frameIndex < frames.count else { return } // stop at end
    let f = frames[frameIndex]
    apply(f)
    frameIndex += 1
    if frameIndex < frames.count {
        advanceAfter(f.tickDuration)
    }
}
```

Applying a frame constructs new `ClaudeUsage` / `CodexUsage` values directly from the keyframe integers.

### 3. `QuotaViewModel.swift` — demo hooks (guarded by `#if DEMO_MODE`)

`PopoverView` uses `@Environment(QuotaViewModel.self)`, so the real ViewModel must be used. But its relevant state properties are `private(set)`, blocking external mutation.

Add a `#if DEMO_MODE`-gated extension to `QuotaViewModel` that exposes a single entry point:

```swift
#if DEMO_MODE
extension QuotaViewModel {
    /// Called once by the DemoDriver to put the ViewModel into a stable
    /// "both connected, no data yet" state without touching auth or network.
    func prepareForDemo() {
        stopAutoRefresh()
        claudeState      = .authenticated
        codexState       = .authenticated
        enrolledServices = [.claude, .codex]
        claudeUsage      = nil
        codexUsage       = nil
        claudeError      = nil
        codexError       = nil
        isClaudeLoading  = true
        isCodexLoading   = true
    }

    /// Called by DemoDriver on each keyframe tick to push fake usage values.
    func applyDemoFrame(claude: ClaudeUsage?, codex: CodexUsage?,
                        claudeLoading: Bool = false, codexLoading: Bool = false) {
        claudeUsage      = claude
        codexUsage       = codex
        isClaudeLoading  = claudeLoading
        isCodexLoading   = codexLoading
        lastRefreshedAt  = .now
    }
}
#endif
```

This requires removing `private(set)` from `claudeState`, `codexState`, and `enrolledServices` — or changing them to `internal(set)` gated behind the flag. Since this is a throwaway build the access-level relaxation is acceptable.

### 4. `AIQuotaApp.swift` — DemoDriver wiring

```swift
#if DEMO_MODE
@State private var demoDriver = DemoDriver()
#endif
```

In the `MenuBarExtra` label closure:

```swift
.task {
    #if DEMO_MODE
    viewModel.prepareForDemo()
    demoDriver.start(driving: viewModel)
    #endif
}
```

`DemoDriver` holds a weak reference to the `QuotaViewModel` and drives it via `applyDemoFrame(...)` on a timer.

### 5. Reset on popover open

`DemoDriver` observes `NSPopover.willShowNotification` at init time and calls `reset()` on itself, which restarts the frame sequence from the beginning. No changes to `PopoverView` or any other view.

### 5. Compilation flag

Add `DEMO_MODE` as a Swift Active Compilation Condition in a new Xcode build configuration called `Demo` (copy of `Debug`). Build and run with that scheme. No changes to the `Release` configuration.

---

## Files to create/modify

| File | Action |
|---|---|
| `AIQuota/Demo/DemoDriver.swift` | Create — keyframe array + timer + `NSPopover` reset observer |
| `AIQuota/AIQuotaApp.swift` | Modify — hold `DemoDriver`, wire it in `.task` under `#if DEMO_MODE` |
| `AIQuota/ViewModels/QuotaViewModel.swift` | Modify — relax access on `claudeState`/`codexState`/`enrolledServices`; add `#if DEMO_MODE` extension with `prepareForDemo()` and `applyDemoFrame()` |
| `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/ClaudeUsage.swift` | Modify — add `public init` |
| `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/CodexUsage.swift` | Modify — `private → public init` |
| Xcode project settings | Modify — add `Demo` build configuration + `DEMO_MODE` Swift flag |

---

## What does NOT change

- `PopoverView`, `CircularGaugeView`, `CountdownView` — unchanged
- `QuotaViewModel` — unchanged (except no-op `demoReset()` if needed)
- All auth coordinators, network clients — untouched
- Widget target — untouched
- Release build — unaffected

---

## Reset behaviour

Open popover → `DemoQuotaViewModel.reset()` → plays from frame 0 (loading). Close and reopen → resets again. At the final frame the timer stops and the gauge holds at Claude 7d 100%, Codex 7d ~80%.
