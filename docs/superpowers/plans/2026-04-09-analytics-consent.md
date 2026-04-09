# Analytics Consent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in analytics consent preference to onboarding, Settings, and public docs without integrating telemetry yet.

**Architecture:** Persist a new `analyticsEnabled` flag inside `AppSettings`, expose it through a new onboarding step and a mirrored Settings section, and update the privacy/FAQ copy so the app and website describe the same behavior. Keep this pass UI-only so the eventual analytics integration can simply honor the stored preference.

**Tech Stack:** SwiftUI, Swift 6, AIQuotaKit model persistence, static HTML docs, Swift Testing

---

### Task 1: Add the persisted analytics-consent setting

**Files:**
- Modify: `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/AppSettings.swift`
- Test: `Packages/AIQuotaKit/Tests/AIQuotaKitTests/AnalyticsConsentSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**
- [ ] **Step 2: Run `swift test --package-path Packages/AIQuotaKit --filter AnalyticsConsentSettingsTests` and verify the new setting is missing**
- [ ] **Step 3: Add `analyticsEnabled` to `AppSettings`, defaulting to `false` and decoding safely for legacy settings**
- [ ] **Step 4: Re-run `swift test --package-path Packages/AIQuotaKit --filter AnalyticsConsentSettingsTests` and verify the model-level tests pass**

### Task 2: Add onboarding and Settings consent UI

**Files:**
- Modify: `AIQuota/Views/Onboarding/OnboardingView.swift`
- Create: `AIQuota/Views/Onboarding/Steps/AnalyticsConsentStepView.swift`
- Modify: `AIQuota/Views/SettingsView.swift`
- Test: `Packages/AIQuotaKit/Tests/AIQuotaKitTests/AnalyticsConsentSettingsTests.swift`

- [ ] **Step 1: Keep the source-based regression test failing for the missing onboarding/settings wiring**
- [ ] **Step 2: Insert the analytics step before Done and wire in the approved copy**
- [ ] **Step 3: Add the mirrored Settings toggle and Privacy Policy link**
- [ ] **Step 4: Re-run `swift test --package-path Packages/AIQuotaKit --filter AnalyticsConsentSettingsTests` and verify the source-level checks now pass**

### Task 3: Update public privacy and FAQ copy

**Files:**
- Modify: `docs/privacy/index.html`
- Modify: `docs/index.html`

- [ ] **Step 1: Update the privacy policy to describe optional anonymous analytics and the in-app opt-in**
- [ ] **Step 2: Update the homepage FAQ to clarify analytics are anonymous and off by default**
- [ ] **Step 3: Smoke-read the edited sections to confirm the copy matches the app UI**

### Task 4: Verify the end state

**Files:**
- Verify: `Packages/AIQuotaKit/Tests/AIQuotaKitTests/AnalyticsConsentSettingsTests.swift`
- Verify: `AIQuota/Views/Onboarding/Steps/AnalyticsConsentStepView.swift`
- Verify: `AIQuota/Views/SettingsView.swift`
- Verify: `docs/privacy/index.html`
- Verify: `docs/index.html`

- [ ] **Step 1: Run `swift test --package-path Packages/AIQuotaKit --filter AnalyticsConsentSettingsTests`**
- [ ] **Step 2: Run `swift test --package-path Packages/AIQuotaKit`**
- [ ] **Step 3: Summarize any remaining gaps, especially that telemetry is not integrated yet**
