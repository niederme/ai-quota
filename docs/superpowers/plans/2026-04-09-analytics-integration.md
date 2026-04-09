# Analytics Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up GA4 Measurement Protocol event sending in the macOS app, gated on the existing `analyticsEnabled` preference.

**Architecture:** A new `AnalyticsClient` actor in the main app target reads credentials from a gitignored `Analytics.plist` bundle resource and sends events via `URLSession`. All sends are no-ops when `analyticsEnabled` is false or the plist is absent. Three call sites: app launch, onboarding completion, and first service sign-in.

**Tech Stack:** Swift 6, `URLSession.shared.data(for:)`, GA4 Measurement Protocol (app stream), `UserDefaults.standard` for per-install UUID.

---

### Task 1: Add `Analytics.plist` (gitignored credentials) and update `.gitignore`

**Files:**
- Create: `AIQuota/Resources/Analytics.plist`
- Modify: `.gitignore`

- [ ] **Step 1: Create `AIQuota/Resources/Analytics.plist`** with the real credentials:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>FirebaseAppID</key>
    <string>1:106661566945:ios:866e3fabb60b02c0cc9aa0</string>
    <key>APISecret</key>
    <string>gNE5XhiSSI-E2HhlSlQYng</string>
</dict>
</plist>
```

- [ ] **Step 2: Add `Analytics.plist` to `.gitignore`** so credentials never enter the repo. Append to `.gitignore`:

```
# Analytics credentials (never commit — contains GA4 API secret)
AIQuota/Resources/Analytics.plist
```

- [ ] **Step 3: Commit only the `.gitignore` change** (do not stage `Analytics.plist`):

```bash
git add .gitignore
git commit -m "chore: gitignore Analytics.plist credentials"
```

Expected: `.gitignore` committed; `Analytics.plist` remains untracked and unindexed.

---

### Task 2: Create `AnalyticsClient`

**Files:**
- Create: `AIQuota/Analytics/AnalyticsClient.swift`

No unit tests: this is a thin HTTP wrapper whose observable output is a network call. Correctness is validated in Task 4 via the GA4 Realtime report.

- [ ] **Step 1: Create `AIQuota/Analytics/AnalyticsClient.swift`**:

```swift
import Foundation

/// Fire-and-forget GA4 Measurement Protocol client.
/// All sends are silent no-ops when `enabled` is false or `Analytics.plist` is absent.
actor AnalyticsClient {
    static let shared = AnalyticsClient()

    private let firebaseAppID: String?
    private let apiSecret: String?
    private let instanceID: String

    private init() {
        if let url = Bundle.main.url(forResource: "Analytics", withExtension: "plist"),
           let plist = NSDictionary(contentsOf: url) {
            firebaseAppID = plist["FirebaseAppID"] as? String
            apiSecret = plist["APISecret"] as? String
        } else {
            firebaseAppID = nil
            apiSecret = nil
        }

        let key = "analytics.instanceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            instanceID = existing
        } else {
            let new = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            UserDefaults.standard.set(new, forKey: key)
            instanceID = new
        }
    }

    func send(_ eventName: String, params: [String: String] = [:], enabled: Bool) async {
        guard enabled,
              let appID = firebaseAppID,
              let secret = apiSecret else { return }

        var components = URLComponents(string: "https://www.google-analytics.com/mp/collect")!
        components.queryItems = [
            URLQueryItem(name: "firebase_app_id", value: appID),
            URLQueryItem(name: "api_secret", value: secret)
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "app_instance_id": instanceID,
            "events": [["name": eventName, "params": params]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data

        _ = try? await URLSession.shared.data(for: request)
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project** so XcodeGen picks up the new file:

```bash
xcodegen generate
```

Expected: no errors; `AnalyticsClient.swift` appears in the `AIQuota` group in Xcode.

- [ ] **Step 3: Build to confirm the new file compiles**:

```bash
xcodebuild -scheme AIQuota -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**:

```bash
git add AIQuota/Analytics/AnalyticsClient.swift project.yml
git commit -m "feat: add AnalyticsClient (GA4 Measurement Protocol)"
```

---

### Task 3: Wire the three call sites

**Files:**
- Modify: `AIQuota/AIQuotaApp.swift`
- Modify: `AIQuota/ViewModels/QuotaViewModel.swift`

- [ ] **Step 1: Fire `app_launched` in `AIQuotaApp.init()`.**

In `AIQuotaApp.init()`, after `_viewModel = State(initialValue: QuotaViewModel())`, add:

```swift
let analyticsEnabled = _viewModel.wrappedValue.settings.analyticsEnabled
let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
Task {
    await AnalyticsClient.shared.send(
        "app_launched",
        params: ["app_version": appVersion],
        enabled: analyticsEnabled
    )
}
```

Full updated `init()` for reference (additions marked):

```swift
init() {
    LegacyWebKitMigration.migrateIfNeeded(bundleIdentifier: "com.niederme.AIQuota")
    LegacyDefaultsMigration.migrateIfNeeded(bundleIdentifier: "com.niederme.AIQuota")
    LaunchServicesSync.repairIfNeeded()
    _viewModel = State(initialValue: QuotaViewModel())
    #if DEMO_MODE
    _demoDriver = State(initialValue: DemoDriver())
    #endif
    updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: gentleDriverDelegate
    )
    let updater = updaterController.updater
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        updater.checkForUpdatesInBackground()
    }
    DispatchQueue.main.async {
        WidgetCenter.shared.reloadAllTimelines()
    }
    // ── Analytics ──────────────────────────────────────────────────────────
    let analyticsEnabled = _viewModel.wrappedValue.settings.analyticsEnabled
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    Task {
        await AnalyticsClient.shared.send(
            "app_launched",
            params: ["app_version": appVersion],
            enabled: analyticsEnabled
        )
    }
}
```

- [ ] **Step 2: Fire `onboarding_completed` in `QuotaViewModel.completeOnboarding()`.**

Current (line 76–79):
```swift
func completeOnboarding() {
    UserDefaults.standard.set(true, forKey: "onboarding.v1.hasCompleted")
    onboardingTriggeredThisSession = true
}
```

Replace with:
```swift
func completeOnboarding() {
    UserDefaults.standard.set(true, forKey: "onboarding.v1.hasCompleted")
    onboardingTriggeredThisSession = true
    Task {
        await AnalyticsClient.shared.send("onboarding_completed", enabled: settings.analyticsEnabled)
    }
}
```

- [ ] **Step 3: Fire `service_connected` on first Claude sign-in.**

In `signInClaude()` (around line 470), the block that guards `!enrolledServices.contains(.claude)`:

Current:
```swift
if !enrolledServices.contains(.claude) {
    enrolledServices.insert(.claude)
    SharedDefaults.enrollService(.claude)
}
```

Replace with:
```swift
if !enrolledServices.contains(.claude) {
    enrolledServices.insert(.claude)
    SharedDefaults.enrollService(.claude)
    Task {
        await AnalyticsClient.shared.send(
            "service_connected",
            params: ["service_name": "claude"],
            enabled: settings.analyticsEnabled
        )
    }
}
```

- [ ] **Step 4: Fire `service_connected` on first Codex sign-in.**

In `QuotaViewModel.init()`, the stateStream observer for Codex (around line 200):

Current:
```swift
if state == .authenticated && !self.enrolledServices.contains(.codex) {
    self.enrolledServices.insert(.codex)
    SharedDefaults.enrollService(.codex)
}
```

Replace with:
```swift
if state == .authenticated && !self.enrolledServices.contains(.codex) {
    self.enrolledServices.insert(.codex)
    SharedDefaults.enrollService(.codex)
    Task {
        await AnalyticsClient.shared.send(
            "service_connected",
            params: ["service_name": "codex"],
            enabled: self.settings.analyticsEnabled
        )
    }
}
```

- [ ] **Step 5: Build to confirm everything compiles**:

```bash
xcodebuild -scheme AIQuota -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**:

```bash
git add AIQuota/AIQuotaApp.swift AIQuota/ViewModels/QuotaViewModel.swift
git commit -m "feat: fire analytics events on launch, onboarding, and service sign-in"
```

---

### Task 4: Validate in GA4 Realtime

- [ ] **Step 1: Open the app in debug mode.** In Xcode, run the `AIQuota` scheme. The app must have `analyticsEnabled = true` — enable it in Settings → Privacy or go through onboarding and opt in.

- [ ] **Step 2: Open GA4 Realtime report.** Go to analytics.google.com → the `aiquota` property → Reports → Realtime. Events should appear within 30 seconds.

- [ ] **Step 3: Verify `app_launched` fires on each launch.** Relaunch the app from Xcode. Confirm `app_launched` with `app_version` property appears in Realtime.

- [ ] **Step 4: Verify `onboarding_completed` fires.** Reset onboarding from Settings → "Guided Setup…", complete the wizard. Confirm `onboarding_completed` appears in Realtime.

- [ ] **Step 5: Verify `service_connected` fires.** Sign out a service and sign back in. Confirm `service_connected` with `service_name` property appears in Realtime.

- [ ] **Step 6: Verify no events fire when disabled.** Set `analyticsEnabled = false` in Settings → Privacy, relaunch. Confirm no new events appear in GA4 Realtime.

---

### Task 5: Open Xcode in worktree

- [ ] **Step 1: Open Xcode from the worktree path** (per project convention):

```bash
open /Users/niederme/~Repos/ai-quota/.claude/worktrees/inspiring-bardeen/AIQuota.xcodeproj
```
