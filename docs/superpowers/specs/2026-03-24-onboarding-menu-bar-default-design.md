# Onboarding: Menu Bar Default Picker

**Date:** 2026-03-24
**Status:** Approved

---

## Problem

When a user connects both Codex and Claude Code during onboarding, they have no opportunity to choose which service appears in the menu bar. The setting exists in Settings, but first-run users will never see it. The app silently defaults to Codex.

---

## Solution

Add an inline "Which should show in your menu bar?" choice to the existing **Services step** in onboarding. It appears only when both services are authenticated, and uses two large tap cards — a deliberate first-time-choice interaction rather than a settings-style widget.

---

## Design

### Where

`ServicesStepView.swift` only. No new step, no new model, no new files.

### When it appears

Conditionally rendered when `viewModel.isCodexAuthenticated && viewModel.isClaudeAuthenticated`. Animates in with a spring transition (`.opacity` + `.move(edge: .bottom)`) when that condition becomes true.

### UI structure (within the services step, below service rows)

```
[ service row: Codex — Connected ]
[ service row: Claude Code — Connected ]

──── divider ────

"Which should show in your menu bar?"   ← small secondary label

[ card: Codex logo / name / radio ]  [ card: Claude Code logo / name / radio ]
```

### Tap cards

- Two equal-width cards, side by side
- Each shows: service logo, service name, radio indicator at bottom
- Selected state: brand-purple border + tinted background + filled radio dot
- Unselected state: subtle border + neutral background + empty radio circle
- Tapping a card sets `viewModel.settings.menuBarService` and immediately calls `viewModel.saveSettings()` to persist the choice. (`SettingsView` auto-saves via `.onChange`, but `ServicesStepView` has no such modifier — `saveSettings()` must be called explicitly in the tap action.)
- `saveSettings()` also calls `startAutoRefresh()` as a side effect; benign on repeated taps.
- Default selection reflects the current value of `menuBarService` (`.codex` by default)

### Layout

The onboarding window is fixed at 520×580pt. The existing `Spacer()` between the service rows and footer hint will absorb the tap cards section (~130pt). No window size changes or scroll views needed.

### Data binding

`viewModel.settings.menuBarService` — type `ServiceType`, already persisted via `SharedDefaults`. No new state or model changes needed.

### Existing behavior unchanged

- `canAdvance` logic (require ≥1 service) — untouched
- Progress dot count — untouched (no new step)
- `resolvedMenuBarService` fallback in `AIQuotaApp` — untouched
- Settings view picker — untouched (continues to work as before)

---

## Out of scope

- Showing this UI when only one service is connected (not needed — only one option)
- Changing the default value of `menuBarService` in `AppSettings`
- Any changes outside `ServicesStepView.swift`
