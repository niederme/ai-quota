# Settings Structural Pass — Design Spec

**Date:** 2026-04-02
**Status:** Approved
**Roadmap item:** Settings is cramped — too much scrolling, notifications lack hierarchy; needs a structural pass

---

## Problem

The Settings window has two interrelated issues:

1. **Too narrow and too tall.** At 400pt wide, the window is unusually cramped for a macOS desktop app. With both services enrolled, the form renders ~28 rows across 8 sections, requiring significant scrolling.

2. **Notification section lacks hierarchy.** The master toggle, permission status, per-service toggles, sub-window sub-headers, and 16 individual threshold toggles all render at the same visual depth. There is no clear parent-child relationship.

---

## Design

### Window width

Widen from **400pt → 500pt**. This is still narrower than System Settings (~668pt) but appropriate for this app's content volume. It gives segmented pickers and labeled rows room to breathe without making toggle rows look sparse.

### Section ordering

| # | Section | Change |
|---|---------|--------|
| 1 | General | No change |
| 2 | Accounts | **Moved up** from near bottom |
| 3 | Notifications | Restructured (see below) |
| 4 | Updates | No change |
| 5 | Onboarding | No change |
| 6 | About footer | No change |

Accounts moves above Notifications because it gates whether per-service notification sections appear at all. Onboarding and About stay at the bottom — they are rarely touched.

### Notification hierarchy

The master "Notifications" section is unchanged: enable toggle + `NotificationStatusRow`.

Each enrolled service gets a named section with a three-level hierarchy:

```
Section("Codex")                                    ← named section header
  [logo] Codex  ─────────────────────  [toggle]     ← service master switch

  (inline expansion when service toggle is ON)

  5-HOUR WINDOW                                     ← sub-header (footnote weight, secondary color)
    Threshold alerts               [toggle]         ← drives: at15 + at5 + limitReached
    Window reset                   [toggle]

  WEEKLY USAGE  (Codex) / 7-DAY WINDOW (Claude)    ← sub-header
    Threshold alerts               [toggle]         ← drives: weekly/7d thresholds
    [Period] reset                 [toggle]
```

Row count per service: **8 → 5** (service toggle + 2 sub-headers + 4 toggles).
Total notification rows with both services enrolled: **~18 → ~12**.

### Threshold alerts toggle — data model mapping

No new model fields are added. `NotificationPreferences` retains all existing fine-grained booleans. The consolidated "Threshold alerts" toggle in the UI:

- **Reads:** `on` if any of the underlying fields are `true` (`at15 || at5 || limitReached`)
- **Writes:** sets all three underlying fields to the new value simultaneously

This preserves stored preferences across app versions. Users who had a mixed on/off state see "on" in the consolidated toggle; their next interaction normalises all three to the same value. This is an acceptable one-time reset given how rarely these are tuned.

### Sub-header rendering

Sub-headers (`5-HOUR WINDOW`, `WEEKLY USAGE`, etc.) use `.font(.footnote.weight(.semibold))` and `.foregroundStyle(.secondary)` with `.listRowBackground(Color.clear)` — matching the existing `notifSubHeader` helper already in the view.

---

## Out of scope

- No changes to `NotificationPreferences` model fields or encoding keys
- No changes to `NotificationManager` firing logic
- No tab-based or sidebar navigation
- No changes to the About footer content or Onboarding section behaviour

---

## Files affected

| File | Change |
|------|--------|
| `AIQuota/Views/SettingsView.swift` | Width, section reorder, notification hierarchy, threshold toggle helpers |

No other files require changes.
