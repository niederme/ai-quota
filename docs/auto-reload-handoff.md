# Auto-reload awareness

> **Status:** Implemented. This document records the current behavior and the
> decisions behind it. It is no longer a future implementation handoff.

## What changed

AIQuota now captures Codex auto-reload settings and uses them to keep credit
warnings proportionate. The popover also follows the shared budget-warning rule:
**bars are exception states, not routine status.**

That means:

- Normal values stay text-only.
- Caution uses text tint.
- Bars appear only when a real boundary has been crossed.

## Endpoints

### Codex (ChatGPT / OpenAI)

Read:

```text
GET https://chatgpt.com/backend-api/subscriptions/auto_top_up/settings
```

This uses the same Bearer-token auth mechanism as `OpenAIClient.fetchUsage()`.

Response shape:

```json
{
  "is_enabled": true,
  "recharge_threshold": "125",
  "recharge_target": "250",
  "recharge_monthly_limit": null,
  "immediate_top_up_status": null,
  "immediate_top_up_message": null
}
```

`recharge_threshold` and `recharge_target` are JSON strings. Decode them through
`AutoTopUpSettingsResponse` and parse to numeric credits before building
`CodexAutoReload`.

### Claude (Anthropic)

No extra fetch is needed. `ClaudeUsage.ExtraUsage.isEnabled` already carries the
auto-charge signal from Claude usage data.

The underlying endpoint is:

```text
GET https://claude.ai/api/organizations/{org_uuid}/overage_spend_limit
```

Important semantic difference: Claude auto-charge does not refill a credit
balance. It authorizes overage up to a monthly cap. Once
`usedCredits >= monthlyLimit`, the user is at the cap regardless of `isEnabled`.

## Current model

### Codex

Codex has a prepaid credit balance plus optional auto-reload settings:

- `isEnabled`: whether auto-reload is active.
- `rechargeThreshold`: the balance where reload should trigger.
- `rechargeTarget`: the balance after top-up.

When auto-reload is enabled, a low balance is not automatically a crisis. It is
usually just "refill is expected." The UI therefore never escalates active
auto-reload to a red bar by itself.

### Claude

Claude extra usage is a monthly cap. The UI treats it independently from the
5-hour and 7-day rings:

- `< 85%`: `Extra` text in primary.
- `85%...94%`: `Extra` text in amber.
- `95%...99%`: `Extra` text in red.
- `>= 100%`: `BudgetStripView` appears.

The extra-usage tint should not borrow state from the current 5-hour ring. A 93%
5-hour ring does not make `Extra` amber unless monthly extra usage itself is at
or above 85%.

## Popover behavior

### Codex credits

`PopoverView` renders Codex credits through `CodexCreditsRow`.

Rules:

- If no auto-reload settings are known, show `Credits: N` as text only.
- If auto-reload is enabled and `balance <= rechargeThreshold`, show amber text
  plus `· auto-reload`.
- If auto-reload is enabled, never show a red credit bar from low balance alone.
- If `balance <= 0`, auto-reload settings are known, and `isEnabled == false`,
  show the Codex exception bar.

When the exception bar appears, it fills by depletion from the reload target:

```swift
fractionDepleted = (rechargeTarget - currentBalance) / rechargeTarget
```

This makes the Codex bar fill in the same direction as Claude's bar: toward bad.

### Claude extra

`BudgetStripView.showThreshold` is `100`. Below that, `Extra` stays in the
compact text row and is tinted by `extraUsageTint(_:)`.

## Top-up notifications

`NotificationManager.evaluateTopUp(...)` detects Codex top-ups by diffing the
latest `creditBalance` against the previous stored balance.

Rules:

- Store the first observed balance without firing.
- Fire when `currentBalance > lastBalance + 50`.
- Always update the stored balance afterward.
- Respect notification settings, including the Codex `Top-up events` toggle.
- Use auto-reload-aware copy:
  - Auto-reload on: "Codex credits topped up" / "Auto-reload added credits. New balance: N."
  - Otherwise: "Codex credits added" / "New balance: N."

This remains Codex-only. Claude has no equivalent balance-refill concept in the
captured API.

## Demo behavior

The Demo scheme exercises both the calm and exception states:

- Claude extra usage climbs through normal/caution text states, then reaches
  `100%` and `103%` so `BudgetStripView` appears.
- Codex balance drains as text-only while no reload target is known.
- Codex hits `Credits: 0` with reload configured but off, showing the exception
  bar.
- Codex then turns auto-reload on and jumps to the target, exercising top-up
  notification detection.

## Verification

Use these checks after touching this behavior:

```sh
swift test --disable-sandbox
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -configuration Debug -destination 'platform=macOS' build
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota-Demo -configuration Demo -destination 'platform=macOS' build
git diff --check
```

Known local note: full Swift package tests can occasionally trip shared-defaults
state in auth coordinator tests; rerun once before treating that as a regression.

## Follow-ups

- Calibrate Codex's inherited low-credit text thresholds (`< 20` amber, `< 5`
  red) against real credit burn.
- Consider burn-rate runway copy once daily credit usage events are available.
- Consider formatting Claude extra values with the API's `currency` field.
