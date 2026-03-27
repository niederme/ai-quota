# Aggressive Widget Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the desktop widgets fetch fresher quota data on demand and refresh themselves more aggressively so they stay as close as possible to the menu bar app.

**Architecture:** Persist the minimum auth context the widget extension needs in shared secure storage, add a shared widget refresh service in `AIQuotaKit` that can fetch fresh usage from the extension process, and move widget scheduling to a policy that prefers short heartbeat refreshes plus exact reset boundaries. Keep the existing app-driven WidgetKit reloads as a second sync path.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, App Intents, URLSession, Security/Keychain, app-group storage, XCTest

---

### Task 1: Add a testable widget refresh policy

**Files:**
- Create: `Packages/AIQuotaKit/Sources/AIQuotaKit/Widgets/WidgetRefreshPolicy.swift`
- Create: `Packages/AIQuotaKit/Tests/AIQuotaKitTests/WidgetRefreshPolicyTests.swift`

- [ ] **Step 1: Write the failing tests**
- [ ] **Step 2: Run the policy tests to verify they fail**
- [ ] **Step 3: Implement the minimal policy for stale-cache fetch decisions and next timeline dates**
- [ ] **Step 4: Run the policy tests to verify they pass**

### Task 2: Persist widget-usable auth context in shared secure storage

**Files:**
- Modify: `Packages/AIQuotaKit/Sources/AIQuotaKit/Storage/KeychainStore.swift`
- Create: `Packages/AIQuotaKit/Sources/AIQuotaKit/Storage/SharedAuthContextStore.swift`
- Modify: `Packages/AIQuotaKit/Sources/AIQuotaKit/Auth/CodexAuthCoordinator.swift`
- Modify: `Packages/AIQuotaKit/Sources/AIQuotaKit/Auth/ClaudeAuthCoordinator.swift`
- Modify: `AIQuotaWidget/Resources/AIQuotaWidget.entitlements`

- [ ] **Step 1: Add failing tests for auth-context encoding/decoding where practical**
- [ ] **Step 2: Extend the keychain helper to support shared-group data payloads**
- [ ] **Step 3: Add codex and claude shared auth-context persistence helpers**
- [ ] **Step 4: Save and clear the shared auth context inside auth coordinator transitions**
- [ ] **Step 5: Run the focused test suite**

### Task 3: Make widget refreshes fetch real data

**Files:**
- Create: `Packages/AIQuotaKit/Sources/AIQuotaKit/Widgets/WidgetRefreshService.swift`
- Modify: `AIQuotaWidget/WidgetIntent.swift`
- Modify: `AIQuotaWidget/Provider/QuotaTimelineProvider.swift`

- [ ] **Step 1: Write or extend tests around the shared refresh policy first**
- [ ] **Step 2: Implement a widget refresh service that loads shared auth, fetches available services, and updates shared cache**
- [ ] **Step 3: Update the widget refresh intent to fetch before requesting a reload**
- [ ] **Step 4: Update the timeline providers to opportunistically fetch when cache is stale and schedule the next reload aggressively**
- [ ] **Step 5: Run the focused tests again**

### Task 4: Verify end-to-end behavior

**Files:**
- Modify: `README.md` (only if behavior description needs to change)

- [ ] **Step 1: Run `swift test` for `AIQuotaKit`**
- [ ] **Step 2: Run an Xcode build for the app + widget targets**
- [ ] **Step 3: If needed, update docs to reflect that widget refresh now performs a real fetch**
- [ ] **Step 4: Summarize residual WidgetKit limits clearly**
