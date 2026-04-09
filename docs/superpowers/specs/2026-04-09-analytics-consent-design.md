# Analytics Consent Design

**Goal:** Add an explicit opt-in surface for future anonymous app analytics without shipping telemetry yet.

**Scope:** This pass adds a persisted user preference, onboarding step, Settings toggle, and matching public-site copy. It does not integrate Firebase or any analytics SDK.

## Design

- Add `analyticsEnabled` to `AppSettings`, defaulting to `false`.
- Insert a dedicated onboarding step between `Widgets` and `Done`.
- Use the primary copy:
  - Toggle label: `Help John improve AIQuota with anonymous usage analytics`
  - Supporting copy: `Share simple anonymous metrics with John, like installs, active use, app version, and setup completion. No prompts, tokens, or personal info.`
- Mirror the toggle in Settings so users can change the choice later.
- Link to the Privacy Policy from both onboarding and Settings.

## UX Notes

- Consent is optional and unchecked by default.
- The step is informative, not blocking; users can continue with the toggle off.
- The Settings copy should feel consistent with the onboarding copy, but can be slightly more compact.

## Public Copy

- Update the Privacy Policy to describe optional anonymous analytics, the kinds of data planned, and the opt-in control.
- Update the homepage FAQ to clarify that app analytics are optional, anonymous, and disabled by default unless the user turns them on.
