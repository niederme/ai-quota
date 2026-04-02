# Settings Structural Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Widen the Settings window to 500pt, reorder sections so Accounts appears before Notifications, give per-service notification sections named headers, collapse 3 per-threshold toggles per window into a single "Threshold alerts" toggle, and normalise any existing mixed-state preferences on launch — all mirrored identically in `NotificationsStepView`.

**Architecture:** All UI changes are confined to two SwiftUI views. The consolidation is backed by computed properties and a `normalizeThresholds()` method added to `NotificationPreferences` (no new stored fields, no encoding changes). The migration fires once in `QuotaViewModel.init()` before any UI renders.

**Tech Stack:** Swift, SwiftUI, Swift Testing (`@Suite` / `@Test` / `#expect`), `xcodegen`

---

## File Map

| File | Role |
|------|------|
| `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift` | Add `normalizeThresholds()` + four aggregate computed properties to `NotificationPreferences` |
| `Packages/AIQuotaKit/Tests/AIQuotaKitTests/NotificationPreferencesNormalizationTests.swift` | New — unit tests for normalization and aggregate computed properties |
| `AIQuota/ViewModels/QuotaViewModel.swift` | Call `normalizeThresholds()` in `init()` before UI renders |
| `AIQuota/Views/SettingsView.swift` | Width → 500pt, section reorder, section titles, aggregate toggles |
| `AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift` | Same aggregate toggle consolidation as SettingsView |

---

## Task 1 — Add `normalizeThresholds()` and aggregate computed properties to `NotificationPreferences`

**Files:**
- Modify: `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift`
- Create: `Packages/AIQuotaKit/Tests/AIQuotaKitTests/NotificationPreferencesNormalizationTests.swift`

- [ ] **Step 1.1 — Write the failing tests**

Create `Packages/AIQuotaKit/Tests/AIQuotaKitTests/NotificationPreferencesNormalizationTests.swift`:

```swift
import Testing
@testable import AIQuotaKit

@Suite("NotificationPreferences normalization")
struct NotificationPreferencesNormalizationTests {

    // MARK: - normalizeThresholds()

    @Test("all-on groups stay all-on")
    func allOnUnchanged() {
        var prefs = NotificationPreferences()
        // defaults are all true — should be a no-op
        prefs.normalizeThresholds()
        #expect(prefs.codex5hAt15 && prefs.codex5hAt5 && prefs.codex5hLimitReached)
        #expect(prefs.codexAt15 && prefs.codexAt5 && prefs.codexLimitReached)
        #expect(prefs.claude5hAt15 && prefs.claude5hAt5 && prefs.claude5hLimitReached)
        #expect(prefs.claude7dAt80 && prefs.claude7dAt95 && prefs.claude7dLimitReached)
    }

    @Test("all-off groups stay all-off")
    func allOffUnchanged() {
        var prefs = NotificationPreferences()
        prefs.codex5hAt15 = false; prefs.codex5hAt5 = false; prefs.codex5hLimitReached = false
        prefs.codexAt15 = false; prefs.codexAt5 = false; prefs.codexLimitReached = false
        prefs.claude5hAt15 = false; prefs.claude5hAt5 = false; prefs.claude5hLimitReached = false
        prefs.claude7dAt80 = false; prefs.claude7dAt95 = false; prefs.claude7dLimitReached = false
        prefs.normalizeThresholds()
        #expect(!prefs.codex5hAt15 && !prefs.codex5hAt5 && !prefs.codex5hLimitReached)
        #expect(!prefs.claude7dAt80 && !prefs.claude7dAt95 && !prefs.claude7dLimitReached)
    }

    @Test("mixed group where any=true normalises to all-true")
    func mixedPartialOnBecomesAllOn() {
        var prefs = NotificationPreferences()
        // Only one of three is on in the Codex 5h group
        prefs.codex5hAt15 = false
        prefs.codex5hAt5 = false
        prefs.codex5hLimitReached = true   // one left on
        prefs.normalizeThresholds()
        #expect(prefs.codex5hAt15)
        #expect(prefs.codex5hAt5)
        #expect(prefs.codex5hLimitReached)
    }

    @Test("mixed group where any=true normalises independently per group")
    func eachGroupNormalisedIndependently() {
        var prefs = NotificationPreferences()
        // Codex weekly: only limit reached is on — should become all-on
        prefs.codexAt15 = false; prefs.codexAt5 = false; prefs.codexLimitReached = true
        // Claude 7d: all off — should stay all-off
        prefs.claude7dAt80 = false; prefs.claude7dAt95 = false; prefs.claude7dLimitReached = false
        prefs.normalizeThresholds()
        #expect(prefs.codexAt15 && prefs.codexAt5 && prefs.codexLimitReached)
        #expect(!prefs.claude7dAt80 && !prefs.claude7dAt95 && !prefs.claude7dLimitReached)
    }

    // MARK: - Aggregate computed properties

    @Test("codex5hThresholdAlerts is true when all three are true")
    func aggregateAllOnIsTrue() {
        let prefs = NotificationPreferences()
        #expect(prefs.codex5hThresholdAlerts == true)
    }

    @Test("codex5hThresholdAlerts is false when all three are false")
    func aggregateAllOffIsFalse() {
        var prefs = NotificationPreferences()
        prefs.codex5hAt15 = false; prefs.codex5hAt5 = false; prefs.codex5hLimitReached = false
        #expect(prefs.codex5hThresholdAlerts == false)
    }

    @Test("setting codex5hThresholdAlerts=false clears all three fields")
    func aggregateSetFalseClearsAll() {
        var prefs = NotificationPreferences()
        prefs.codex5hThresholdAlerts = false
        #expect(!prefs.codex5hAt15 && !prefs.codex5hAt5 && !prefs.codex5hLimitReached)
    }

    @Test("setting codex5hThresholdAlerts=true sets all three fields")
    func aggregateSetTrueSetsAll() {
        var prefs = NotificationPreferences()
        prefs.codex5hAt15 = false; prefs.codex5hAt5 = false; prefs.codex5hLimitReached = false
        prefs.codex5hThresholdAlerts = true
        #expect(prefs.codex5hAt15 && prefs.codex5hAt5 && prefs.codex5hLimitReached)
    }
}
```

- [ ] **Step 1.2 — Run to confirm tests fail**

```bash
swift test --package-path Packages/AIQuotaKit --filter NotificationPreferencesNormalization 2>&1 | grep -E 'error:|passed|failed|Test run'
```

Expected: compile error — `normalizeThresholds` and `codex5hThresholdAlerts` do not exist yet.

- [ ] **Step 1.3 — Add the implementation to `NotificationPreferences`**

In `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift`, after the `init(from decoder:)` block and before the closing `}` of `NotificationPreferences`, add:

```swift
    // MARK: - Aggregate computed properties (UI consolidation)
    // Each property covers one window type's threshold alerts (at-%, limit reached).
    // Reads true if any underlying field is on; writes all three simultaneously.

    public var codex5hThresholdAlerts: Bool {
        get { codex5hAt15 || codex5hAt5 || codex5hLimitReached }
        set { codex5hAt15 = newValue; codex5hAt5 = newValue; codex5hLimitReached = newValue }
    }

    public var codexWeeklyThresholdAlerts: Bool {
        get { codexAt15 || codexAt5 || codexLimitReached }
        set { codexAt15 = newValue; codexAt5 = newValue; codexLimitReached = newValue }
    }

    public var claude5hThresholdAlerts: Bool {
        get { claude5hAt15 || claude5hAt5 || claude5hLimitReached }
        set { claude5hAt15 = newValue; claude5hAt5 = newValue; claude5hLimitReached = newValue }
    }

    public var claude7dThresholdAlerts: Bool {
        get { claude7dAt80 || claude7dAt95 || claude7dLimitReached }
        set { claude7dAt80 = newValue; claude7dAt95 = newValue; claude7dLimitReached = newValue }
    }

    // MARK: - Migration

    /// Normalises any threshold group where the three underlying booleans are not all
    /// the same value. Mixed groups are resolved to their OR result (any=true → all-true).
    /// Call once on app launch before UI renders; subsequent interactions use the
    /// aggregate computed properties above which always write all three uniformly.
    public mutating func normalizeThresholds() {
        func normalize(_ a: inout Bool, _ b: inout Bool, _ c: inout Bool) {
            let resolved = a || b || c
            if a != resolved || b != resolved || c != resolved {
                a = resolved; b = resolved; c = resolved
            }
        }
        normalize(&codex5hAt15,  &codex5hAt5,  &codex5hLimitReached)
        normalize(&codexAt15,    &codexAt5,    &codexLimitReached)
        normalize(&claude5hAt15, &claude5hAt5, &claude5hLimitReached)
        normalize(&claude7dAt80, &claude7dAt95, &claude7dLimitReached)
    }
```

- [ ] **Step 1.4 — Run tests to confirm they pass**

```bash
swift test --package-path Packages/AIQuotaKit --filter NotificationPreferencesNormalization 2>&1 | grep -E 'passed|failed|Test run'
```

Expected: all tests pass.

- [ ] **Step 1.5 — Run full test suite to confirm no regressions**

```bash
swift test --package-path Packages/AIQuotaKit 2>&1 | tail -8
```

Expected: all existing tests pass.

- [ ] **Step 1.6 — Commit**

```bash
git add Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift \
        Packages/AIQuotaKit/Tests/AIQuotaKitTests/NotificationPreferencesNormalizationTests.swift
git commit -m "feat: add threshold normalisation and aggregate computed properties to NotificationPreferences"
```

---

## Task 2 — Call `normalizeThresholds()` in `QuotaViewModel.init()`

**Files:**
- Modify: `AIQuota/ViewModels/QuotaViewModel.swift` (around line 210, just before the notification permission request)

- [ ] **Step 2.1 — Add the normalization call in `init()`**

In `QuotaViewModel.init()`, after the `// Load cached data immediately` block (around line 162–164) and before the `// Observe coordinator state streams` comment, insert:

```swift
        // Normalise any mixed per-threshold notification state from pre-consolidation builds.
        // OR-resolves each group (any=true → all-true) so aggregate toggles always see
        // a clean on/off state from the first render.
        let preNorm = settings
        settings.notifications.normalizeThresholds()
        if settings != preNorm { SharedDefaults.saveSettings(settings) }
```

The `preNorm` comparison avoids a redundant write for users who have never had mixed state (the common case).

- [ ] **Step 2.2 — Build to confirm compilation**

```bash
xcodegen generate && xcodebuild build -scheme AIQuota -destination 'platform=macOS' 2>&1 | grep -E '^.*error:|BUILD (SUCCEEDED|FAILED)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 2.3 — Commit**

```bash
git add AIQuota/ViewModels/QuotaViewModel.swift
git commit -m "feat: normalise mixed notification threshold state on launch"
```

---

## Task 3 — Restructure `SettingsView`

**Files:**
- Modify: `AIQuota/Views/SettingsView.swift`

Three sub-changes: (a) width + section reorder, (b) section titles + aggregate toggles.

### 3a — Width and section reorder

- [ ] **Step 3a.1 — Widen to 500pt**

Find `.frame(width: 400)` (near the bottom of `body`) and change to `.frame(width: 500)`.

- [ ] **Step 3a.2 — Move Accounts section above Notifications**

Cut the entire `// MARK: Accounts` section block (lines ~124–139 in current file):

```swift
            // MARK: Accounts
            Section("Accounts") {
                LabeledContent("Codex") {
                    if viewModel.isCodexAuthenticated {
                        Button("Sign Out", role: .destructive) { viewModel.signOut() }
                    } else {
                        Button("Sign In") { Task { await viewModel.signIn() } }
                    }
                }
                LabeledContent("Claude Code") {
                    if viewModel.isClaudeAuthenticated {
                        Button("Sign Out", role: .destructive) { viewModel.signOutClaude() }
                    } else {
                        Button("Sign In") { Task { await viewModel.signInClaude() } }
                    }
                }
            }
```

Paste it immediately after the closing `}` of the `// MARK: General` section (after line ~41).

### 3b — Named section titles + aggregate toggles

- [ ] **Step 3b.1 — Add a string title to the Codex notification section**

The Codex section currently opens with an anonymous `Section {`. Change it to `Section("Codex") {`.

- [ ] **Step 3b.2 — Replace per-threshold Codex toggles with aggregate bindings**

Inside the Codex section's expanded block, replace:

```swift
                        notifSubHeader("5-hour window")
                        Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codex5hAt15)
                        Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codex5hAt5)
                        Toggle("Limit reached",           isOn: $vm.settings.notifications.codex5hLimitReached)
                        Toggle("Window reset",            isOn: $vm.settings.notifications.codex5hReset)

                        notifSubHeader("Weekly usage")
                        Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                        Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codexAt5)
                        Toggle("Limit reached",           isOn: $vm.settings.notifications.codexLimitReached)
                        Toggle("Weekly reset",            isOn: $vm.settings.notifications.codexReset)
```

With:

```swift
                        notifSubHeader("5-hour window")
                        Toggle("Threshold alerts", isOn: $vm.settings.notifications.codex5hThresholdAlerts)
                        Toggle("Window reset",     isOn: $vm.settings.notifications.codex5hReset)

                        notifSubHeader("Weekly usage")
                        Toggle("Threshold alerts", isOn: $vm.settings.notifications.codexWeeklyThresholdAlerts)
                        Toggle("Weekly reset",     isOn: $vm.settings.notifications.codexReset)
```

- [ ] **Step 3b.3 — Add a string title to the Claude notification section**

Change the Claude section's `Section {` to `Section("Claude Code") {`.

- [ ] **Step 3b.4 — Replace per-threshold Claude toggles with aggregate bindings**

Inside the Claude section's expanded block, replace:

```swift
                        notifSubHeader("5-hour window")
                        Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.claude5hAt15)
                        Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.claude5hAt5)
                        Toggle("Limit reached",           isOn: $vm.settings.notifications.claude5hLimitReached)
                        Toggle("Window reset",            isOn: $vm.settings.notifications.claude5hReset)

                        notifSubHeader("7-day window")
                        Toggle("80% used (high)",         isOn: $vm.settings.notifications.claude7dAt80)
                        Toggle("95% used (critical)",     isOn: $vm.settings.notifications.claude7dAt95)
                        Toggle("Limit reached",           isOn: $vm.settings.notifications.claude7dLimitReached)
                        Toggle("Period reset",            isOn: $vm.settings.notifications.claude7dReset)
```

With:

```swift
                        notifSubHeader("5-hour window")
                        Toggle("Threshold alerts", isOn: $vm.settings.notifications.claude5hThresholdAlerts)
                        Toggle("Window reset",     isOn: $vm.settings.notifications.claude5hReset)

                        notifSubHeader("7-day window")
                        Toggle("Threshold alerts", isOn: $vm.settings.notifications.claude7dThresholdAlerts)
                        Toggle("Period reset",     isOn: $vm.settings.notifications.claude7dReset)
```

- [ ] **Step 3b.5 — Remove the stale per-service animation modifiers**

The following two `.animation` modifiers on the `Form` are no longer needed (they animated the expansion of the individual toggles, which are now gone). Remove them:

```swift
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.settings.notifications.codexEnabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.settings.notifications.claudeEnabled)
```

The master `.animation` keyed on `notifSectionsEnabled` stays — it still animates the section disable/fade.

> **Note:** The `@Bindable` binding path `$vm.settings.notifications.codex5hThresholdAlerts` works because `NotificationPreferences` is a struct nested inside `AppSettings` which is `@Observable`-tracked through `@Bindable var vm`. The computed property setter mutates the struct in place, which triggers observation. No additional binding wrappers needed.

- [ ] **Step 3b.6 — Build to confirm compilation**

```bash
xcodebuild build -scheme AIQuota -destination 'platform=macOS' 2>&1 | grep -E '^.*error:|BUILD (SUCCEEDED|FAILED)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3b.7 — Commit**

```bash
git add AIQuota/Views/SettingsView.swift
git commit -m "feat: settings structural pass — 500pt width, reorder sections, named notif sections, aggregate threshold toggles"
```

---

## Task 4 — Mirror consolidation in `NotificationsStepView`

**Files:**
- Modify: `AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift`

- [ ] **Step 4.1 — Add a string title to the Codex section**

Change `Section {` (Codex block, around line 51) to `Section("Codex") {`.

- [ ] **Step 4.2 — Replace per-threshold Codex toggles with aggregate bindings**

Replace:

```swift
                            subHeader("5-hour window")
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codex5hAt15)
                            Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codex5hAt5)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.codex5hLimitReached)
                            Toggle("Window reset",            isOn: $vm.settings.notifications.codex5hReset)

                            subHeader("Weekly usage")
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                            Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codexAt5)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.codexLimitReached)
                            Toggle("Weekly reset",            isOn: $vm.settings.notifications.codexReset)
```

With:

```swift
                            subHeader("5-hour window")
                            Toggle("Threshold alerts", isOn: $vm.settings.notifications.codex5hThresholdAlerts)
                            Toggle("Window reset",     isOn: $vm.settings.notifications.codex5hReset)

                            subHeader("Weekly usage")
                            Toggle("Threshold alerts", isOn: $vm.settings.notifications.codexWeeklyThresholdAlerts)
                            Toggle("Weekly reset",     isOn: $vm.settings.notifications.codexReset)
```

- [ ] **Step 4.3 — Add a string title to the Claude section**

Change `Section {` (Claude block, around line 75) to `Section("Claude Code") {`.

- [ ] **Step 4.4 — Replace per-threshold Claude toggles with aggregate bindings**

Replace:

```swift
                            subHeader("5-hour window")
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.claude5hAt15)
                            Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.claude5hAt5)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.claude5hLimitReached)
                            Toggle("Window reset",            isOn: $vm.settings.notifications.claude5hReset)

                            subHeader("7-day window")
                            Toggle("80% used (high)",         isOn: $vm.settings.notifications.claude7dAt80)
                            Toggle("95% used (critical)",     isOn: $vm.settings.notifications.claude7dAt95)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.claude7dLimitReached)
                            Toggle("Period reset",            isOn: $vm.settings.notifications.claude7dReset)
```

With:

```swift
                            subHeader("5-hour window")
                            Toggle("Threshold alerts", isOn: $vm.settings.notifications.claude5hThresholdAlerts)
                            Toggle("Window reset",     isOn: $vm.settings.notifications.claude5hReset)

                            subHeader("7-day window")
                            Toggle("Threshold alerts", isOn: $vm.settings.notifications.claude7dThresholdAlerts)
                            Toggle("Period reset",     isOn: $vm.settings.notifications.claude7dReset)
```

- [ ] **Step 4.5 — Remove the stale per-service animation modifiers**

Remove from the `Form`:

```swift
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.settings.notifications.codexEnabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.settings.notifications.claudeEnabled)
```

- [ ] **Step 4.6 — Build to confirm compilation**

```bash
xcodebuild build -scheme AIQuota -destination 'platform=macOS' 2>&1 | grep -E '^.*error:|BUILD (SUCCEEDED|FAILED)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4.7 — Commit**

```bash
git add AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
git commit -m "feat: mirror aggregate threshold toggles in NotificationsStepView"
```

---

## Manual Smoke Test

After all tasks are complete, launch the app and verify:

1. Settings window opens at ~500pt wide (visibly wider than before)
2. Accounts section appears second, before Notifications
3. With a service enrolled and notifications enabled, the per-service section shows a named header ("Codex" or "Claude Code")
4. Expanding a service shows 2 sub-headers × 2 rows each (not 2 sub-headers × 4 rows)
5. Toggling "Threshold alerts" off and back on sets all three underlying fields correctly — verify by checking that notifications actually fire/suppress appropriately, or inspect via a breakpoint in `normalizeThresholds`
6. Open "Guided Setup…" → advance to the Notifications step — confirm the same consolidated layout appears there
