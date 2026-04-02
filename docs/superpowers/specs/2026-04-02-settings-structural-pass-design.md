# Settings Structural Pass — Design Spec

**Date:** 2026-04-02
**Status:** Approved
**Roadmap item:** Settings is cramped — too much scrolling, notifications lack hierarchy; needs a structural pass

---

## Problem

The Settings window has two interrelated issues:

1. **Too narrow and too tall.** At 400pt wide, the window is unusually cramped for a macOS desktop app. With both services enrolled, the form renders many rows across 8 sections, requiring significant scrolling.

2. **Notification section lacks hierarchy.** The master toggle, permission status, per-service toggles, sub-window sub-headers, and 16 individual threshold toggles all render at the same visual depth. There is no clear parent-child relationship.

Additionally, `NotificationsStepView` (the onboarding notifications step) is a structural copy of the Settings notification section and exposes the same per-threshold individual toggles. Because "Guided Setup…" can be replayed at any time from Settings, leaving it with individual toggles creates two editors for the same data with conflicting semantics.

---

## Design

### Window width

Widen from **400pt → 500pt**. This is still narrower than System Settings (~668pt) but appropriate for this app's content volume. It gives segmented pickers and labeled rows room to breathe without making toggle rows look sparse.

### Section ordering

The full ordered list of `Section` blocks, top to bottom:

| # | Section | Change |
|---|---------|--------|
| 1 | General | No change |
| 2 | Accounts | **Moved up** from near bottom |
| 3 | Notifications (master) | Unchanged content |
| 4 | Codex notification section | Restructured — see below |
| 5 | Claude Code notification section | Restructured — see below |
| 6 | "No services enrolled" fallback | No change |
| 7 | Updates | No change |
| 8 | Onboarding | No change |
| 9 | About footer | No change |

Accounts moves above Notifications because it gates whether per-service notification sections appear at all. Onboarding and About stay at the bottom — they are rarely touched.

### Notification hierarchy

The master "Notifications" section (section 3) is unchanged: enable toggle + `NotificationStatusRow`.

Each enrolled service gets a named section. The per-service sections currently use anonymous `Section { ... }` blocks with no title. **These gain a string title matching the service display name** (`Section("Codex")`, `Section("Claude Code")`).

Within each named section:

```
Section("Codex")                                    ← new: named section header
  [logo] Codex  ─────────────────────  [toggle]     ← service master switch

  (inline expansion when service toggle is ON)

  5-hour window                                     ← sub-header (footnote weight, secondary)
    Threshold alerts               [toggle]         ← see field mapping below
    Window reset                   [toggle]

  Weekly usage                                      ← sub-header (Codex); "7-day window" for Claude
    Threshold alerts               [toggle]         ← see field mapping below
    Weekly reset                   [toggle]         ← "Period reset" for Claude
```

Sub-header text is **retained verbatim** from the current code: `"5-hour window"`, `"Weekly usage"` (Codex), `"7-day window"` (Claude).

Row count per service (when expanded): **11 → 7**
- Before: service toggle + 2 sub-headers + 8 threshold/reset toggles = 11
- After: service toggle + 2 sub-headers + 4 toggles = 7

Total notification sub-rows with both services enrolled: **22 → 14**.

The same hierarchy is applied identically in `NotificationsStepView` so both surfaces stay semantically consistent.

### Threshold alerts toggle — field mapping

No new model fields are added. `NotificationPreferences` retains all existing fine-grained booleans. The consolidated "Threshold alerts" toggle:

- **Reads:** `on` if any of the underlying fields are `true` (OR of all three)
- **Writes:** sets all three underlying fields to the new value simultaneously

Exact field mappings per service and window:

| Section | Window | Toggle | Fields driven |
|---------|--------|--------|---------------|
| Codex | 5-hour | Threshold alerts | `codex5hAt15`, `codex5hAt5`, `codex5hLimitReached` |
| Codex | 5-hour | Window reset | `codex5hReset` |
| Codex | Weekly | Threshold alerts | `codexAt15`, `codexAt5`, `codexLimitReached` |
| Codex | Weekly | Weekly reset | `codexReset` |
| Claude | 5-hour | Threshold alerts | `claude5hAt15`, `claude5hAt5`, `claude5hLimitReached` |
| Claude | 5-hour | Window reset | `claude5hReset` |
| Claude | 7-day | Threshold alerts | `claude7dAt80`, `claude7dAt95`, `claude7dLimitReached` |
| Claude | 7-day | Period reset | `claude7dReset` |

### Mixed-state migration

On app launch, before any UI renders, `QuotaViewModel` normalizes any threshold groups that have mixed values: if the three underlying booleans in a group are not all the same value, they are normalized to their OR result and saved. This is a one-time write for any user who had mixed per-threshold state.

This ensures:
- The aggregate toggle always reads a clean on/off state — no hidden partial state on first render
- Toggling off sets all three to `false`; toggling on sets all three to `true` — no silent scope widening
- A clean path exists if granular controls are ever reintroduced later, because per-group consistency is a guaranteed invariant from this version onward

### Sub-header rendering

Sub-headers use `.font(.footnote.weight(.semibold))` and `.foregroundStyle(.secondary)` with `.listRowBackground(Color.clear)` — matching the existing `notifSubHeader`/`subHeader` helpers already in both views. No changes to those helpers.

---

## Out of scope

- No changes to `NotificationPreferences` model fields or encoding keys
- No changes to `NotificationManager` firing logic
- No tab-based or sidebar navigation
- No changes to the About footer content or Onboarding section content/behaviour

---

## Files affected

| File | Change |
|------|--------|
| `AIQuota/Views/SettingsView.swift` | Width (400→500), section reorder, per-service section titles, threshold toggle consolidation |
| `AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift` | Same threshold toggle consolidation as SettingsView |
| `AIQuota/ViewModels/QuotaViewModel.swift` (or equivalent settings load path) | Mixed-state normalization on launch |
