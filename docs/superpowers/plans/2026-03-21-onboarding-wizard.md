# Onboarding Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 5-step first-launch onboarding wizard (Welcome → Services → Notifications → Widgets → Done) that is re-launchable from Settings.

**Architecture:** Linear `Window` scene opened via SwiftUI's `openWindow` environment action. Each step is a standalone SwiftUI view contained by `OnboardingView`, which owns step state and slide-transition animation. `NotificationPreferences` is added to `AppSettings` to give per-service, per-threshold notification toggles (replacing the single `notificationsEnabled` bool), and `NotificationManager` is updated to gate each threshold on its individual toggle.

**Tech Stack:** SwiftUI (macOS 15+), `@Observable`, `UserNotifications`, `UserDefaults.standard`, `AIQuotaKit` shared package, XcodeGen.

---

## Prerequisite

Run from the repo root before starting. Because `.xcodeproj` is generated, adding new files to new subdirectories requires regenerating after they exist.

```bash
# After all new files are created in each task, re-run once at the end:
xcodegen generate && open AIQuota.xcodeproj
```

---

## File Map

### New files (all in main `AIQuota` target)
| Path | Responsibility |
|---|---|
| `AIQuota/Views/Onboarding/OnboardingView.swift` | Container: step enum, slide transition, progress dots, nav buttons |
| `AIQuota/Views/Onboarding/Steps/WelcomeStepView.swift` | Step 0: brand moment, logo placeholder, tagline, Continue |
| `AIQuota/Views/Onboarding/Steps/ServicesStepView.swift` | Step 1: service selection cards + inline sign-in |
| `AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift` | Step 2: per-service, per-threshold notification toggles |
| `AIQuota/Views/Onboarding/Steps/WidgetsStepView.swift` | Step 3: widget explainer + image placeholder |
| `AIQuota/Views/Onboarding/Steps/DoneStepView.swift` | Step 4: success state, links, finish |

### Modified files
| Path | Change |
|---|---|
| `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift` | Add `NotificationPreferences` struct; replace `notificationsEnabled: Bool` with `notifications: NotificationPreferences`; add custom `init(from:)` for migration |
| `Packages/AIQuotaKit/Sources/AIQuotaKit/Notifications/NotificationManager.swift` | Accept `NotificationPreferences` in `evaluate()` signatures; gate each threshold on its individual toggle |
| `AIQuota/AIQuotaApp.swift` | Add `Window("Get Started", id: "onboarding")` scene |
| `AIQuota/ViewModels/QuotaViewModel.swift` | Add `shouldShowOnboarding` computed property + `onboardingTriggered` flag; update `notificationsEnabled` reference to `notifications.enabled` |
| `AIQuota/Views/SettingsView.swift` | Replace single notifications toggle with per-threshold UI; add "Open Onboarding" button |
| `AIQuota/Views/PopoverView.swift` | Add `.task` trigger that calls `openWindow(id: "onboarding")` on first launch |

---

## Brand Constants

Defined once in `OnboardingView.swift`, referenced by all step files via `extension`:

```swift
extension Color {
    static let brand = Color(red: 0.62, green: 0.22, blue: 0.93)
}
```

---

## Task 1: Add `NotificationPreferences` to `AppSettings`

**Files:**
- Modify: `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift`

- [ ] **Step 1: Add the `NotificationPreferences` struct above `AppSettings`**

```swift
// MARK: - NotificationPreferences

public struct NotificationPreferences: Codable, Sendable, Equatable {
    // Master switch
    public var enabled: Bool = true

    // Codex — weekly window
    public var codexAt15: Bool = true           // < 15% remaining
    public var codexAt5: Bool = true            // < 5% remaining
    public var codexLimitReached: Bool = true   // 0% (limit reached)
    public var codexReset: Bool = true          // weekly reset

    // Claude — 5-hour window
    public var claude5hAt15: Bool = true
    public var claude5hAt5: Bool = true
    public var claude5hLimitReached: Bool = true
    public var claude5hReset: Bool = true

    // Claude — 7-day window
    public var claude7dAt80: Bool = true        // 80% used
    public var claude7dAt95: Bool = true        // 95% used
    public var claude7dLimitReached: Bool = true
    public var claude7dReset: Bool = true

    public init() {}
}
```

- [ ] **Step 2: Replace `notificationsEnabled` with `notifications` in `AppSettings`**

Replace the struct body (keeping `refreshIntervalMinutes` and `menuBarService`):

```swift
public struct AppSettings: Codable, Sendable, Equatable {
    public var refreshIntervalMinutes: Int
    public var notifications: NotificationPreferences
    public var menuBarService: ServiceType

    public static let `default` = AppSettings(
        refreshIntervalMinutes: 15,
        notifications: NotificationPreferences(),
        menuBarService: .codex
    )

    public init(
        refreshIntervalMinutes: Int,
        notifications: NotificationPreferences = NotificationPreferences(),
        menuBarService: ServiceType = .codex
    ) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.notifications = notifications
        self.menuBarService = menuBarService
    }

    /// Migration-safe decoder: unknown keys are ignored, missing keys use defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 15
        menuBarService = try c.decodeIfPresent(ServiceType.self, forKey: .menuBarService) ?? .codex
        notifications = try c.decodeIfPresent(NotificationPreferences.self, forKey: .notifications)
            ?? NotificationPreferences()
        // Legacy key `notificationsEnabled` is intentionally not migrated —
        // the default (all on) is the right starting point for all users.
    }

    public var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
}
```

- [ ] **Step 3: Build the AIQuotaKit package to confirm it compiles**

```bash
cd /Users/niederme/~Repos/ai-quota
xcodegen generate
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: compilation errors in callers of `notificationsEnabled` — that's expected, fix them in the next task.

- [ ] **Step 4: Fix ALL `notificationsEnabled` references in `QuotaViewModel.swift`**

Search for every occurrence of `notificationsEnabled` in `AIQuota/ViewModels/QuotaViewModel.swift` and replace each one:

```swift
// Before (all occurrences — there are at least 2, possibly more):
if settings.notificationsEnabled {
// After:
if settings.notifications.enabled {
```

Run a search first to confirm all sites:
```bash
grep -n "notificationsEnabled" AIQuota/ViewModels/QuotaViewModel.swift
```
Replace every match. Common locations: `init()` (~line 107) and `startAutoRefresh()` (~line 322). The two call sites in `NotificationManager.evaluate()` signatures are handled in Task 2 Step 3, not here.

- [ ] **Step 5: Build again to confirm it compiles cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift \
        AIQuota/ViewModels/QuotaViewModel.swift
git commit -m "feat: add per-service per-threshold NotificationPreferences to AppSettings"
```

---

## Task 2: Update `NotificationManager` to respect per-threshold toggles

**Files:**
- Modify: `Packages/AIQuotaKit/Sources/AIQuotaKit/Notifications/NotificationManager.swift`

The `evaluate(current:)` and `evaluate(claude:)` methods currently only gate on system permission. We add a `NotificationPreferences` parameter so each threshold can be individually suppressed.

- [ ] **Step 1: Update `evaluate(current:)` signature and add per-threshold guards**

Replace the entire `evaluate(current:)` method:

```swift
public func evaluate(current: CodexUsage, prefs: NotificationPreferences) async {
    guard prefs.enabled else { return }
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized else { return }

    let storedResetAt  = defaults.object(forKey: Key.codexLastResetAt) as? Double
    let currentResetAt = current.weeklyResetAt.timeIntervalSince1970

    if let stored = storedResetAt {
        let storedDate = Date(timeIntervalSince1970: stored)
        if storedDate < .now {
            clearThresholds(key: Key.codexThresholds)
            defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
            if prefs.codexReset {
                await send(
                    id: "codexReset",
                    title: "Codex quota reset",
                    body: "Your weekly Codex quota has reset — you're back to 100%."
                )
            }
            return
        } else if stored != currentResetAt {
            defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
        }
    } else {
        defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
        return
    }

    let notified  = loadThresholds(key: Key.codexThresholds)
    let remaining = current.weeklyRemaining

    if current.limitReached && !notified.contains("limitReached") && prefs.codexLimitReached {
        markThreshold("limitReached", key: Key.codexThresholds)
        await send(
            id: "codexLimitReached",
            title: "Codex quota reached",
            body: "Your weekly Codex quota is fully used. Resets in \(timeString(current.weeklyResetAfterSeconds))."
        )
    } else if remaining < 5 && !notified.contains("below5") && prefs.codexAt5 {
        markThreshold("below5", key: Key.codexThresholds)
        await send(
            id: "codexBelow5",
            title: "Codex quota critical",
            body: "Less than 5% of your weekly Codex quota remains."
        )
    } else if remaining < 15 && !notified.contains("below15") && prefs.codexAt15 {
        markThreshold("below15", key: Key.codexThresholds)
        await send(
            id: "codexBelow15",
            title: "Codex quota low",
            body: "Less than 15% of your weekly Codex quota remains."
        )
    }
}
```

- [ ] **Step 2: Update `evaluate(claude:)` signature and add per-threshold guards**

Replace the entire `evaluate(claude:)` method:

```swift
public func evaluate(claude: ClaudeUsage, prefs: NotificationPreferences) async {
    guard prefs.enabled else { return }
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized else { return }

    let storedResetAt  = defaults.object(forKey: Key.claudeLastResetAt) as? Double
    let currentResetAt = claude.resetAt.timeIntervalSince1970

    if let stored = storedResetAt {
        let storedDate = Date(timeIntervalSince1970: stored)
        if storedDate < .now {
            clearThresholds(key: Key.claudeThresholds)
            defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
            if prefs.claude5hReset {
                await send(
                    id: "claudeReset",
                    title: "Claude window reset",
                    body: "Your Claude 5-hour window has reset — you're back to full capacity."
                )
            }
            return
        } else if stored != currentResetAt {
            defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
        }
    } else {
        defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
        return
    }

    let notified  = loadThresholds(key: Key.claudeThresholds)
    let remaining = claude.remainingPercent

    if claude.limitReached && !notified.contains("limitReached") && prefs.claude5hLimitReached {
        markThreshold("limitReached", key: Key.claudeThresholds)
        await send(
            id: "claudeLimitReached",
            title: "Claude rate limit reached",
            body: "Your 5-hour Claude window is fully used. Resets in \(timeString(claude.resetAfterSeconds))."
        )
    } else if remaining < 5 && !notified.contains("below5") && prefs.claude5hAt5 {
        markThreshold("below5", key: Key.claudeThresholds)
        await send(
            id: "claudeBelow5",
            title: "Claude quota critical",
            body: "Less than 5% of your Claude 5-hour window capacity remains."
        )
    } else if remaining < 15 && !notified.contains("below15") && prefs.claude5hAt15 {
        markThreshold("below15", key: Key.claudeThresholds)
        await send(
            id: "claudeBelow15",
            title: "Claude quota low",
            body: "Less than 15% of your Claude 5-hour window capacity remains."
        )
    }

    // ── 7-day threshold notifications ──────────────────────────────────
    let sevenDayUsed     = Int(claude.sevenDayUtilization.rounded())
    let sevenDayNotified = loadThresholds(key: Key.claudeSevenDayThresholds)
    let sevenDayResetAt  = claude.sevenDayResetsAt.timeIntervalSince1970
    let storedSevenDay   = defaults.object(forKey: Key.claudeSevenDayLastResetAt) as? Double

    if let stored = storedSevenDay {
        let storedDate = Date(timeIntervalSince1970: stored)
        if storedDate < .now {
            clearThresholds(key: Key.claudeSevenDayThresholds)
            defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
            if prefs.claude7dReset {
                await send(
                    id: "claudeSevenDayReset",
                    title: "Claude 7-day window reset",
                    body: "Your 7-day Claude allowance has reset — you're back to full capacity."
                )
            }
        } else {
            if stored != sevenDayResetAt {
                defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
            }
            if sevenDayUsed >= 100 && !sevenDayNotified.contains("limitReached") && prefs.claude7dLimitReached {
                markThreshold("limitReached", key: Key.claudeSevenDayThresholds)
                await send(
                    id: "claudeSevenDayLimit",
                    title: "Claude 7-day limit reached",
                    body: "Your 7-day Claude allowance is fully used. Resets in \(timeString(claude.sevenDayResetAfterSeconds))."
                )
            } else if sevenDayUsed >= 95 && !sevenDayNotified.contains("above95") && prefs.claude7dAt95 {
                markThreshold("above95", key: Key.claudeSevenDayThresholds)
                await send(
                    id: "claudeSevenDay95",
                    title: "Claude 7-day limit critical",
                    body: "You've used 95% of your 7-day Claude allowance. Resets in \(timeString(claude.sevenDayResetAfterSeconds))."
                )
            } else if sevenDayUsed >= 80 && !sevenDayNotified.contains("above80") && prefs.claude7dAt80 {
                markThreshold("above80", key: Key.claudeSevenDayThresholds)
                await send(
                    id: "claudeSevenDay80",
                    title: "Claude 7-day usage high",
                    body: "You've used 80% of your 7-day Claude allowance — consider slowing down."
                )
            }
        }
    } else {
        defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
    }
}
```

- [ ] **Step 3: Fix the callers in `QuotaViewModel.swift`**

Search for `NotificationManager.shared.evaluate` in `QuotaViewModel.swift`. There will be two call sites — update them to pass `settings.notifications`:

```swift
// Before:
await NotificationManager.shared.evaluate(current: result)
// After:
await NotificationManager.shared.evaluate(current: result, prefs: settings.notifications)

// Before:
await NotificationManager.shared.evaluate(claude: result)
// After:
await NotificationManager.shared.evaluate(claude: result, prefs: settings.notifications)
```

- [ ] **Step 4: Build cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Packages/AIQuotaKit/Sources/AIQuotaKit/Notifications/NotificationManager.swift \
        AIQuota/ViewModels/QuotaViewModel.swift
git commit -m "feat: gate each notification threshold on its individual NotificationPreferences toggle"
```

---

## Task 3: First-launch detection

**Files:**
- Modify: `AIQuota/ViewModels/QuotaViewModel.swift`

We use `UserDefaults.standard` (cleared by AppZapper/reinstall — correct behavior for onboarding). Key: `"onboarding.v1.hasCompleted"`.

- [ ] **Step 1: Add onboarding state to `QuotaViewModel`**

Add these properties inside `QuotaViewModel` (near the `// MARK: - Shared state` block):

```swift
// MARK: - Onboarding

/// True if the user has never completed the onboarding wizard.
var shouldShowOnboarding: Bool {
    !UserDefaults.standard.bool(forKey: "onboarding.v1.hasCompleted")
        && !onboardingTriggeredThisSession
}

/// Set to true after the window has been opened once per session,
/// so clicking the menu bar icon repeatedly doesn't re-open it.
private(set) var onboardingTriggeredThisSession = false

func markOnboardingTriggered() {
    onboardingTriggeredThisSession = true
}

func completeOnboarding() {
    UserDefaults.standard.set(true, forKey: "onboarding.v1.hasCompleted")
    onboardingTriggeredThisSession = true
}

func resetOnboardingForReplay() {
    // Called from Settings "Open Onboarding" button.
    // Does NOT clear the completion key — just allows re-showing this session.
    onboardingTriggeredThisSession = false
}
```

- [ ] **Step 2: Build cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add AIQuota/ViewModels/QuotaViewModel.swift
git commit -m "feat: add shouldShowOnboarding + completion tracking to QuotaViewModel"
```

---

## Task 4: `OnboardingView` container + `Window` scene

**Files:**
- Create: `AIQuota/Views/Onboarding/OnboardingView.swift`
- Modify: `AIQuota/AIQuotaApp.swift`

### 4a — Create `OnboardingView.swift`

- [ ] **Step 1: Create the file**

```swift
// AIQuota/Views/Onboarding/OnboardingView.swift
import SwiftUI
import AIQuotaKit

// MARK: - Brand color

extension Color {
    static let brand = Color(red: 0.62, green: 0.22, blue: 0.93)
}

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable {
    case welcome       = 0
    case services      = 1
    case notifications = 2
    case widgets       = 3
    case done          = 4
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    @State private var step: OnboardingStep = .welcome
    @State private var direction: Int = 1   // +1 forward, -1 backward

    // Fixed window size
    static let width: CGFloat  = 520
    static let height: CGFloat = 580

    var body: some View {
        VStack(spacing: 0) {
            // Content area — fills available space
            ZStack {
                stepView(for: step)
                    .id(step)
                    .transition(slideTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)

            Divider()

            // Navigation bar
            navigationBar
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .frame(width: Self.width, height: Self.height)
        .background(.windowBackground)
    }

    // MARK: - Step content router

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:       WelcomeStepView()
        case .services:      ServicesStepView()
        case .notifications: NotificationsStepView()
        case .widgets:       WidgetsStepView()
        case .done:          DoneStepView()
        }
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            // Back button (hidden on first and last steps)
            if step != .welcome && step != .done {
                Button(action: goBack) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Progress dots
            progressDots

            Spacer()

            // Continue / finish button
            if step != .done {
                Button(action: goForward) {
                    Text(step == .services ? "Continue" : "Next")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.brand)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            }
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s == step ? Color.brand : Color.secondary.opacity(0.25))
                    .frame(
                        width:  s == step ? 8 : 6,
                        height: s == step ? 8 : 6
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
            }
        }
    }

    // MARK: - Transitions

    private var slideTransition: AnyTransition {
        direction > 0
            ? .asymmetric(
                insertion:  .move(edge: .trailing).combined(with: .opacity),
                removal:    .move(edge: .leading).combined(with: .opacity)
              )
            : .asymmetric(
                insertion:  .move(edge: .leading).combined(with: .opacity),
                removal:    .move(edge: .trailing).combined(with: .opacity)
              )
    }

    // MARK: - Navigation

    private var canAdvance: Bool {
        // Services step: require at least one authenticated service
        if step == .services {
            return viewModel.isCodexAuthenticated || viewModel.isClaudeAuthenticated
        }
        return true
    }

    private func goForward() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        direction = 1
        withAnimation { step = next }
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        direction = -1
        withAnimation { step = prev }
    }
}
```

### 4b — Add the `Window` scene to `AIQuotaApp.swift`

- [ ] **Step 2: Add `Window` scene and onboarding launcher**

In `AIQuotaApp.swift`, add the `Window` scene and a trigger view modifier. The full modified `body`:

```swift
var body: some Scene {
    MenuBarExtra {
        PopoverView()
            .environment(viewModel)
            .environment(UpdaterViewModel(updater: updaterController.updater))
            .onboardingLauncher(viewModel: viewModel)
    } label: {
        MenuBarIconView(
            usedPercent: menuBarUsedPercent,
            secondaryPercent: menuBarSecondaryPercent,
            limitReached: menuBarLimitReached,
            isLoading: viewModel.isLoading
        )
    }
    .menuBarExtraStyle(.window)

    Window("Get Started", id: "onboarding") {
        OnboardingView()
            .environment(viewModel)
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    Settings {
        SettingsView()
            .environment(viewModel)
            .environment(UpdaterViewModel(updater: updaterController.updater))
    }
}
```

Add the modifier and its implementation below `GentleSparkleDriverDelegate` in the same file:

```swift
// MARK: - Onboarding launcher modifier

private struct OnboardingLauncherModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let viewModel: QuotaViewModel

    func body(content: Content) -> some View {
        content.task {
            if viewModel.shouldShowOnboarding {
                viewModel.markOnboardingTriggered()
                openWindow(id: "onboarding")
            }
        }
    }
}

private extension View {
    func onboardingLauncher(viewModel: QuotaViewModel) -> some View {
        modifier(OnboardingLauncherModifier(viewModel: viewModel))
    }
}
```

- [ ] **Step 3: Build cleanly**

```bash
xcodegen generate
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add AIQuota/Views/Onboarding/OnboardingView.swift AIQuota/AIQuotaApp.swift
git commit -m "feat: add OnboardingView container and Window scene with first-launch trigger"
```

---

## Task 5: `WelcomeStepView`

**Files:**
- Create: `AIQuota/Views/Onboarding/Steps/WelcomeStepView.swift`

- [ ] **Step 1: Create the file**

```swift
// AIQuota/Views/Onboarding/Steps/WelcomeStepView.swift
import SwiftUI

struct WelcomeStepView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo placeholder — replace with Image("AppLogo") when asset is ready
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.brand.opacity(0.85), Color.brand],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.brand.opacity(0.4), radius: 20, y: 6)

                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.white)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 28)

            // App name
            Text("AIQuota")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            Spacer().frame(height: 10)

            // Tagline placeholder — update when final copy is decided
            Text("Keep an eye on your AI limits,\nright from the menu bar.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)

            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }
}
```

- [ ] **Step 2: Build cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add AIQuota/Views/Onboarding/Steps/WelcomeStepView.swift
git commit -m "feat: add onboarding WelcomeStepView with brand animation"
```

---

## Task 6: `ServicesStepView`

**Files:**
- Create: `AIQuota/Views/Onboarding/Steps/ServicesStepView.swift`

This step shows two service cards. Clicking "Sign In" in a card fires the existing `viewModel.signIn()` / `viewModel.signInClaude()` auth flow (opens WKWebView window). Cards react to `viewModel.isCodexAuthenticated` / `viewModel.isClaudeAuthenticated` changes via `@Observable`.

- [ ] **Step 1: Create the file**

```swift
// AIQuota/Views/Onboarding/Steps/ServicesStepView.swift
import SwiftUI
import AIQuotaKit

struct ServicesStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Connect your services")
                    .font(.title2).fontWeight(.bold)
                Text("Sign in to the services you use.\nYou need at least one to continue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 36)

            Spacer()

            // Service cards
            HStack(spacing: 16) {
                ServiceCard(
                    name: "Codex",
                    subtitle: "ChatGPT / OpenAI",
                    icon: "brain.fill",
                    isAuthenticated: viewModel.isCodexAuthenticated,
                    signInAction: { Task { await viewModel.signIn() } },
                    signOutAction: { viewModel.signOut() }
                )

                ServiceCard(
                    name: "Claude Code",
                    subtitle: "Anthropic / claude.ai",
                    icon: "sparkles",
                    isAuthenticated: viewModel.isClaudeAuthenticated,
                    signInAction: { Task { await viewModel.signInClaude() } },
                    signOutAction: { viewModel.signOutClaude() }
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Skip hint (small text below cards)
            Text("You can add services later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Service Card

private struct ServiceCard: View {
    let name: String
    let subtitle: String
    let icon: String
    let isAuthenticated: Bool
    let signInAction: () -> Void
    let signOutAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isAuthenticated ? Color.brand.opacity(0.12) : Color.secondary.opacity(0.1))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(isAuthenticated ? Color.brand : .secondary)
            }

            VStack(spacing: 3) {
                Text(name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isAuthenticated {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))

                Button("Sign Out", role: .destructive, action: signOutAction)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Sign In", action: signInAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
                    .controlSize(.small)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isAuthenticated)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isAuthenticated ? Color.brand.opacity(0.4) : Color.secondary.opacity(0.15),
                            lineWidth: 1.5
                        )
                )
        )
    }
}
```

- [ ] **Step 2: Build cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add AIQuota/Views/Onboarding/Steps/ServicesStepView.swift
git commit -m "feat: add onboarding ServicesStepView with inline auth cards"
```

---

## Task 7: `NotificationsStepView`

**Files:**
- Create: `AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift`

Shows per-service, per-threshold toggles only for authenticated services. Binds directly to `viewModel.settings.notifications`. On toggle of the master switch, requests system permission if enabling.

- [ ] **Step 1: Create the file**

```swift
// AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
import SwiftUI
import UserNotifications
import AIQuotaKit

struct NotificationsStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications")
                        .font(.title2).fontWeight(.bold)
                    Text("Choose which alerts you'd like to receive.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)

                // Master toggle
                Toggle(isOn: $vm.settings.notifications.enabled) {
                    Label("Enable notifications", systemImage: "bell.badge")
                        .fontWeight(.medium)
                }
                .onChange(of: vm.settings.notifications.enabled) { _, enabled in
                    if enabled {
                        Task { await NotificationManager.shared.requestPermission() }
                    }
                }

                if viewModel.settings.notifications.enabled {
                    Divider()

                    // Codex section (only if authenticated)
                    if viewModel.isCodexAuthenticated {
                        NotificationServiceSection(
                            title: "Codex",
                            icon: "brain.fill"
                        ) {
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                            Toggle("Less than 5% remaining", isOn: $vm.settings.notifications.codexAt5)
                            Toggle("Limit reached", isOn: $vm.settings.notifications.codexLimitReached)
                            Toggle("Weekly reset", isOn: $vm.settings.notifications.codexReset)
                        }
                    }

                    // Claude section (only if authenticated)
                    if viewModel.isClaudeAuthenticated {
                        NotificationServiceSection(
                            title: "Claude Code",
                            icon: "sparkles"
                        ) {
                            // 5-hour window
                            Text("5-hour window")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)

                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.claude5hAt15)
                            Toggle("Less than 5% remaining", isOn: $vm.settings.notifications.claude5hAt5)
                            Toggle("Limit reached", isOn: $vm.settings.notifications.claude5hLimitReached)
                            Toggle("Window reset", isOn: $vm.settings.notifications.claude5hReset)

                            // 7-day window
                            Text("7-day window")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)

                            Toggle("80% used (high)", isOn: $vm.settings.notifications.claude7dAt80)
                            Toggle("95% used (critical)", isOn: $vm.settings.notifications.claude7dAt95)
                            Toggle("Limit reached", isOn: $vm.settings.notifications.claude7dLimitReached)
                            Toggle("Period reset", isOn: $vm.settings.notifications.claude7dReset)
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 36)
        }
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
    }
}

// MARK: - Service section container

private struct NotificationServiceSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color.brand)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.leading, 4)
        }
    }
}
```

- [ ] **Step 2: Build cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
git commit -m "feat: add onboarding NotificationsStepView with per-threshold toggles"
```

---

## Task 8: `WidgetsStepView`

**Files:**
- Create: `AIQuota/Views/Onboarding/Steps/WidgetsStepView.swift`

Static explainer. Image placeholder at top — a real asset can be dropped in later without code changes (the view checks for `"WidgetPromo"` in the asset catalog and falls back to the placeholder).

- [ ] **Step 1: Create the file**

```swift
// AIQuota/Views/Onboarding/Steps/WidgetsStepView.swift
import SwiftUI

struct WidgetsStepView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Image: use asset "WidgetPromo" if available, else show placeholder
            Group {
                if let img = NSImage(named: "WidgetPromo") {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    WidgetImagePlaceholder()
                }
            }
            .frame(height: 200)
            .padding(.horizontal, 36)
            .padding(.top, 28)

            Spacer().frame(height: 24)

            // Instructions
            VStack(alignment: .leading, spacing: 14) {
                Text("Add the AIQuota widget")
                    .font(.title2).fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("See your quota at a glance on your desktop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 4)

                ForEach(instructions, id: \.step) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(item.step)")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.brand)
                            .clipShape(Circle())

                        Text(item.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 36)

            Spacer()
        }
    }

    private struct Instruction {
        let step: Int
        let text: String
    }

    private let instructions: [Instruction] = [
        Instruction(step: 1, text: "Right-click on your desktop and choose **Edit Widgets…**"),
        Instruction(step: 2, text: "Search for **AIQuota** in the widget gallery"),
        Instruction(step: 3, text: "Drag a widget onto your desktop and click **Done**"),
    ]
}

// MARK: - Placeholder

private struct WidgetImagePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Widget screenshot")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            )
    }
}
```

> **Note for widget image:** When you have a screenshot ready, add it to `AIQuota/Resources/Assets.xcassets` with the name `WidgetPromo`. The view automatically picks it up.

- [ ] **Step 2: Build cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add AIQuota/Views/Onboarding/Steps/WidgetsStepView.swift
git commit -m "feat: add onboarding WidgetsStepView with image placeholder"
```

---

## Task 9: `DoneStepView`

**Files:**
- Create: `AIQuota/Views/Onboarding/Steps/DoneStepView.swift`

Marks onboarding complete, closes the window, and shows the @niederme on X + GitHub links. The "Start using AIQuota" button closes the window via `dismissWindow`.

- [ ] **Step 1: Create the file**

```swift
// AIQuota/Views/Onboarding/Steps/DoneStepView.swift
import SwiftUI

struct DoneStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.green)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)
            }

            Spacer().frame(height: 24)

            Text("You're all set!")
                .font(.title).fontWeight(.bold)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            Spacer().frame(height: 10)

            Text("AIQuota is watching your limits\nfrom the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 32)

            // CTA button
            Button(action: finish) {
                Text("Start using AIQuota")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.brand)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(appeared ? 1 : 0)

            Spacer()

            // Footer links
            HStack(spacing: 16) {
                Link("@niederme on X", destination: URL(string: "https://x.com/niederme")!)
                    .foregroundColor(Color.brand)
                Text("·").foregroundStyle(.quaternary)
                Link("GitHub", destination: URL(string: "https://github.com/niederme/ai-quota")!)
                    .foregroundColor(Color.brand)
                Text("·").foregroundStyle(.quaternary)
                Link("Issues", destination: URL(string: "https://github.com/niederme/ai-quota/issues")!)
                    .foregroundColor(Color.brand)
            }
            .font(.footnote)
            .padding(.bottom, 20)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }

    private func finish() {
        viewModel.completeOnboarding()
        dismissWindow(id: "onboarding")
    }
}
```

- [ ] **Step 2: Build cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add AIQuota/Views/Onboarding/Steps/DoneStepView.swift
git commit -m "feat: add onboarding DoneStepView with completion and social links"
```

---

## Task 10: Update `SettingsView`

**Files:**
- Modify: `AIQuota/Views/SettingsView.swift`

Two changes:
1. Replace the single `notificationsEnabled` toggle with per-threshold groups.
2. Add "Open Onboarding" button in the About section.

- [ ] **Step 1: Replace the `Notifications` section in `SettingsView`**

Replace the existing `Section("Notifications")` block with:

```swift
// MARK: Notifications
Section("Notifications") {
    @Bindable var vm = viewModel

    Toggle("Enable notifications", isOn: $vm.settings.notifications.enabled)
        .onChange(of: vm.settings.notifications.enabled) { _, enabled in
            if enabled {
                Task { await NotificationManager.shared.requestPermission() }
            }
        }

    if viewModel.settings.notifications.enabled {
        NotificationStatusRow()

        Divider().padding(.vertical, 2)

        // Codex thresholds
        if viewModel.isCodexAuthenticated {
            Group {
                Text("Codex — Weekly")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("< 15% remaining",   isOn: $vm.settings.notifications.codexAt15)
                Toggle("< 5% remaining",    isOn: $vm.settings.notifications.codexAt5)
                Toggle("Limit reached",     isOn: $vm.settings.notifications.codexLimitReached)
                Toggle("Weekly reset",      isOn: $vm.settings.notifications.codexReset)
            }
        }

        // Claude thresholds
        if viewModel.isClaudeAuthenticated {
            Group {
                Text("Claude Code — 5-hour window")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("< 15% remaining",   isOn: $vm.settings.notifications.claude5hAt15)
                Toggle("< 5% remaining",    isOn: $vm.settings.notifications.claude5hAt5)
                Toggle("Limit reached",     isOn: $vm.settings.notifications.claude5hLimitReached)
                Toggle("Window reset",      isOn: $vm.settings.notifications.claude5hReset)

                Text("Claude Code — 7-day window")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("80% used",          isOn: $vm.settings.notifications.claude7dAt80)
                Toggle("95% used",          isOn: $vm.settings.notifications.claude7dAt95)
                Toggle("Limit reached",     isOn: $vm.settings.notifications.claude7dLimitReached)
                Toggle("Period reset",      isOn: $vm.settings.notifications.claude7dReset)
            }
        }

        if !viewModel.isCodexAuthenticated && !viewModel.isClaudeAuthenticated {
            Text("Sign in to a service to configure thresholds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

Note: the existing `@Bindable var vm = viewModel` at the top of `body` is already present. The one in the Section block above is a local rebind needed inside the closure — use the outer binding `$vm.settings.notifications...` directly.

> **Implementation note:** The `@Bindable var vm = viewModel` is already declared at the top of `body`. In the section closure, just use `$vm.settings.notifications.enabled` etc. directly — no re-declaration needed.

- [ ] **Step 2: Add "Open Onboarding" button to the About section footer**

In the About `Section`, add this button after the links row:

```swift
Button("Open Onboarding Wizard…") {
    viewModel.resetOnboardingForReplay()
    openWindow(id: "onboarding")
}
.buttonStyle(.borderless)
.foregroundColor(Color(red: 0.62, green: 0.22, blue: 0.93))
.padding(.top, 4)
```

Add `@Environment(\.openWindow) private var openWindow` to `SettingsView`'s property list.

- [ ] **Step 3: Build cleanly**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add AIQuota/Views/SettingsView.swift
git commit -m "feat: expand notification settings to per-threshold toggles; add onboarding replay button"
```

---

## Task 11: Regenerate project + end-to-end verification

- [ ] **Step 1: Regenerate the Xcode project (picks up new subdirectories)**

```bash
cd /Users/niederme/~Repos/ai-quota
xcodegen generate
```

- [ ] **Step 2: Final build**

```bash
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED` with zero errors.

- [ ] **Step 3: Manual smoke-test checklist**

Open the app in Xcode (Cmd+R). Verify:

1. **First launch**: click the menu bar icon → popover appears → onboarding window opens automatically
2. **Welcome step**: logo animation plays, Continue button is present
3. **Services step**: both service cards shown, Continue disabled until at least one signed in; sign in to one → card shows "Connected ✓", Continue enables
4. **Notifications step**: master toggle works; per-threshold groups appear for authenticated services only; toggle a threshold off, advance and come back — state persists
5. **Widgets step**: placeholder image shown (or asset if added), instructions readable
6. **Done step**: checkmark animates in, "Start using AIQuota" closes the window
7. **Second launch**: popover opens normally, onboarding does NOT re-appear
8. **Settings → Open Onboarding Wizard…**: onboarding window opens again at Welcome step
9. **Settings notifications section**: per-threshold toggles visible for authenticated services

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "chore: regenerate xcodeproj after adding onboarding views"
```

---

## Notes for the implementing agent

- **Brand color**: always use `Color(red: 0.62, green: 0.22, blue: 0.93)` or `Color.brand` (the extension defined in `OnboardingView.swift`). Do NOT use `.foregroundStyle(.accent)` or `.foregroundStyle(.accentColor)` — they fail to compile per project conventions.
- **`@Bindable var vm = viewModel`**: this pattern is already established in `SettingsView`. Use it in any view that needs two-way bindings into `QuotaViewModel`.
- **`dismissWindow`**: available as `@Environment(\.dismissWindow) private var dismissWindow` in macOS 15+ SwiftUI. Takes `id:` matching the `Window` scene identifier (`"onboarding"`).
- **Auth managers**: `viewModel.signIn()` / `viewModel.signInClaude()` are async and open a WKWebView window. The onboarding doesn't need to manage this — it just calls them and the `@Observable` properties update automatically when auth completes.
- **Settings save**: `viewModel.saveSettings()` is already called via `.onChange(of: viewModel.settings)` in `SettingsView`. In `NotificationsStepView`, add the same `.onChange` to persist changes made during onboarding.
- **XcodeGen**: new Swift files in new subdirectories are picked up automatically by directory-level source rules in `project.yml`, but you must run `xcodegen generate` for Xcode to see them. Do this in Task 11, or earlier if you need IDE assistance mid-way.
