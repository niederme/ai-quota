# Auto-Reload Awareness — Implementation Handoff

## Context

The popover already shows two warning signals when budgets are tight:

1. **Claude side** — `BudgetStripView` (in `AIQuota/Views/BudgetStripView.swift`) appears
   inside the Claude column of the stats row when `extraUsage.utilization >= 70`,
   escalating amber → red at 85%.
2. **Codex side** — the `Credits: N` row in `claudeSecondaryStats` is tinted via
   `creditTint(_:)` in `PopoverView.swift`: amber below `$20`, red below `$5`. (See
   the open question on units below.)

Both treatments assume the user will be cut off / charged unexpectedly and need to
take action. **That assumption is wrong when auto-reload is on.** A user who has
opted into auto-reload is fine with the system topping them up — hitting zero is
just a routine refill, not a crisis. Showing them a screaming red "Credits: 0" is
overstating the panic.

This task: capture each service's auto-reload state and use it to *soften* the
warning treatment when reload is on. Never alarm louder than the underlying
situation warrants.

---

## Endpoints (verified via DevTools, May 2026)

### Codex (ChatGPT / OpenAI)

**Read:** `GET https://chatgpt.com/backend-api/wham/auto_top_up/settings`
*(real path: `/backend-api/subscriptions/auto_top_up/settings`, exposed under the
chatgpt.com host through the same Bearer-token auth mechanism the existing
`OpenAIClient.fetchUsage()` uses.)*

**Response shape:**

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

Field semantics:

| Field | Type | Meaning |
|---|---|---|
| `is_enabled` | `Bool` | Master toggle. `true` = auto-reload active. |
| `recharge_threshold` | **`String`** (parses to numeric credits) | The minimum balance that triggers a refill. |
| `recharge_target` | **`String`** (parses to numeric credits) | Refill brings balance up to this number. |
| `recharge_monthly_limit` | `Int?` | Monthly cap on auto-reload spend; usually `null`. |
| `immediate_top_up_status` | `String?` | Set during an in-flight reload; usually `null`. |
| `immediate_top_up_message` | `String?` | Companion message for `immediate_top_up_status`. |

**Trap:** `recharge_threshold` and `recharge_target` come back as JSON strings, not
numbers. Parse them to `Double` (or `Int`) on decode.

**Write:** `POST /backend-api/subscriptions/auto_top_up/update` — body
`{"recharge_threshold": "125", "recharge_target": "250"}`. Not needed for this
task (read-only).

### Claude (Anthropic)

**Already captured in our existing model.** We don't need a new endpoint —
`ClaudeUsage.ExtraUsage.isEnabled` already carries the signal.

For reference, the underlying API:

**Read:** `GET https://claude.ai/api/organizations/{org_uuid}/overage_spend_limit`

**Response shape (truncated to relevant fields):**

```json
{
  "is_enabled": true,
  "monthly_credit_limit": 8000,
  "currency": "USD",
  "used_credits": 5225,
  "out_of_credits": false,
  "disabled_reason": null,
  "disabled_until": null
}
```

`is_enabled` here is the same toggle that the `/usage` endpoint surfaces in
`extra_usage.is_enabled`. **Don't add a new fetch for Claude** — keep using what's
already there.

(Bonus fields surfaced by this endpoint that may be useful for future polish:
`out_of_credits` for explicit cut-off detection, `disabled_reason`/`disabled_until`
for cases where Anthropic temporarily disables overage on an account. Not in scope
here.)

---

## Conceptual model: how auto-reload differs between services

Codex and Claude have *different* "extra usage" architectures, and the warning
softening must respect those differences:

- **Codex:** prepaid credit balance + auto-reload threshold/target. Auto-reload
  refills the balance when it drops below the threshold. Hitting zero just means
  "a refill is incoming." When `is_enabled = true`, the user will essentially
  never be cut off — they're authorizing automatic top-ups indefinitely.

- **Claude:** monthly spend cap (`monthly_credit_limit`) + auto-charge toggle
  (`is_enabled`). Auto-reload here means *"automatically charge me for overage
  up to the cap."* It does **not** refill the cap mid-month. Once
  `used_credits >= monthly_credit_limit`, the user **is** cut off until the
  monthly reset, regardless of `is_enabled`. So the existing strip behavior
  (red at 85%+) is correct and should not be softened.

This means: **only the Codex side gets softened by `is_enabled`.** Claude's
existing strip stays as-is.

---

## Implementation plan

### 1. New model: `CodexAutoReload`

Add to `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/CodexUsage.swift`
(or a dedicated `CodexAutoReload.swift` next to it):

```swift
public struct CodexAutoReload: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let rechargeThreshold: Double  // parsed from String
    public let rechargeTarget: Double     // parsed from String

    public init(isEnabled: Bool, rechargeThreshold: Double, rechargeTarget: Double) {
        self.isEnabled = isEnabled
        self.rechargeThreshold = rechargeThreshold
        self.rechargeTarget = rechargeTarget
    }
}
```

Companion raw-decode struct (`AutoTopUpSettingsResponse`) to handle the
String→Double parsing — mirror the pattern used by `WhamUsageResponse` in
`CodexUsage.swift`.

### 2. Network call: `OpenAIClient.fetchAutoReload()`

In `Packages/AIQuotaKit/Sources/AIQuotaKit/Networking/OpenAIClient.swift`,
add a method that mirrors the existing `fetchUsage()`:

- Same Bearer-token auth (use `coordinator` the same way)
- Hit `/backend-api/subscriptions/auto_top_up/settings`
- Decode `AutoTopUpSettingsResponse`
- Return `CodexAutoReload`
- Use the same `Logger` instance you'll find from the recent OSLog migration
  (subsystem `app.aiquota`, category `OpenAIClient`)
- Same error-throwing conventions (`NetworkError.decodingError`, etc.)

### 3. View model: fetch alongside usage

In `AIQuota/ViewModels/QuotaViewModel.swift`:

- Add `var codexAutoReload: CodexAutoReload?` as observable state
- In the existing Codex refresh path (around the `fetchUsage()` call site),
  fire `fetchAutoReload()` *concurrently* (use `async let`) so we don't double
  the latency. Apply the same suppression rules as the usage decode path
  (the recent fix that conditions suppression on existing data).
- On error from auto-reload only (not usage), fail open — log and leave
  `codexAutoReload` at its previous value. The credit warning treatment must
  not regress just because the auxiliary endpoint hiccupped.

### 4. PopoverView: soften the credit warning when reload is on

Update `creditTint(_:)` in `AIQuota/Views/PopoverView.swift` (currently a
free function on the view). Change its signature to accept the auto-reload
state:

```swift
private func creditTint(_ balance: Double, autoReload: CodexAutoReload?) -> Color {
    if autoReload?.isEnabled == true {
        // Auto-reload covers the user — soft amber when actually below their
        // own threshold (refill imminent), never red.
        if balance <= autoReload!.rechargeThreshold { return .orange }
        return .primary
    }
    // No auto-reload: existing absolute thresholds apply
    if balance < 5 { return .red }
    if balance < 20 { return .orange }
    return .primary
}
```

Update the call site in `codexSecondaryStats` to pass
`viewModel.codexAutoReload`.

### 5. PopoverView: add an "auto-reload" hint

When `autoReload?.isEnabled == true`, append a tertiary-color hint after the
credit number so users understand why the warning is muted. Suggested:

```
Credits: 73 · auto-reload
```

Specifically: extend the `compactRow` helper with an optional `suffix: String?`
parameter rendered in `.tertiary` after the value, OR render a custom row for
the credits case. Keep typography consistent with the rest of `compactRow`
output (caption2). Don't make the hint visually loud.

### 6. Open question: dollars vs credits

The current hardcoded thresholds (`< $5` red, `< $20` amber) were dollar-thinking.
We've since confirmed Codex credits are **abstract units, not dollars** — daily
consumption commonly reaches 100–300 credits, and the user's auto-reload threshold
is `125`. Once you have `rechargeThreshold` available, the auto-reload-on path
above uses it natively (no calibration needed). For the auto-reload-off path,
**leave the existing 5/20 thresholds alone in this PR** — they're admittedly
arbitrary, but recalibration is out of scope here and worth a separate
conversation about defaults. File a follow-up.

### 7. Demo driver

In `AIQuota/Demo/DemoDriver.swift`:

- Currently has a `codexBalance: [Int: Double]` map indexed by frame. Add a
  parallel `codexAutoReload: [Int: CodexAutoReload]` (or just toggle
  `isEnabled` per frame) so the demo cycles through both states. Suggested
  pattern: first half of the timeline shows auto-reload off (existing red/amber
  behavior), second half toggles it on (warning softens to amber + hint). This
  lets the demo loop showcase both paths.
- Wire the new value through `applyDemoFrame` in `QuotaViewModel`, mirroring how
  `claude` and `codex` are passed today.
- Within the same demo loop, include at least one frame where the Codex balance
  *jumps up* (e.g., 8 → 250) so the top-up notification path (next section)
  fires once per cycle. The notification permission prompt won't appear in
  Demo builds; the notification itself will be visible if granted.

### 8. Codex top-up notifications

When a user's Codex `creditBalance` refills (auto-reload, manual purchase —
anything that adds credit), fire a native macOS notification so the user knows
it happened without opening the popover.

**Detection — balance-jump diffing:**

- Persist `lastCodexBalance: Double?` in `UserDefaults` via `AppSettings` (or
  wherever Codex-side persisted state already lives; pattern-match the existing
  setup rather than inventing a new key system).
- After every successful Codex usage refresh in `QuotaViewModel`:
  1. Read prior `lastCodexBalance`
  2. Compare to `currentBalance = codexUsage.creditBalance`
  3. If `lastCodexBalance != nil && currentBalance > lastCodexBalance + 50`,
     it's a top-up event — fire the notification (see below). The `+ 50`
     is a noise floor; daily consumption is in 100–300 credit territory, and
     real refills are typically `recharge_target − recharge_threshold` in
     size (often ≥ 125), so 50 is comfortably above noise without missing
     real top-ups. Make this a named constant for future tuning.
  4. **Always** update `lastCodexBalance = currentBalance` afterward — both
     when a top-up fires and when it doesn't.
- On first launch (no stored value), store and do not fire.
- The diff must run on the same code path as the success branch of `fetchUsage()`
  in the view model, *before* any subsequent refresh begins, so we don't miss a
  quick refill-then-consume sequence.

**Firing — use the existing `NotificationManager`:**

The project already has a `NotificationManager` (`AIQuota/...`, find via grep)
that handles the existing "threshold reached" and "window reset" notifications.
Add a third notification type alongside the existing ones, following the same
pattern (it likely uses `UNUserNotificationCenter` directly).

Copy (caption2-equivalent restraint, no exclamation marks):

- If `codexAutoReload?.isEnabled == true` at the time of the refill:
  - Title: "Codex credits topped up"
  - Body: "Auto-reload added credits. New balance: {N}."
- Otherwise (manual purchase, or auto-reload state unknown):
  - Title: "Codex credits added"
  - Body: "New balance: {N}."

Use `Int(currentBalance)` for the displayed number (no decimals; consistent
with the popover's `Credits: N` row).

**Settings — opt-out toggle:**

Add a new toggle in `SettingsView` for "Top-up events" alongside the existing
per-service notification toggles ("Threshold alerts", "Reset events" or
whatever the existing ones are named — pattern-match). Persist in `AppSettings`
with the existing notification toggles. Default **ON** (top-ups are positive,
low-frequency, low-spam — opt-out rather than opt-in is correct).

Codex-only for now: do not add a Claude version. Claude's auto-reload doesn't
refill a balance (see conceptual model section), so there's nothing to notify
on. If we ever capture Claude's separate "Current balance" pool (visible in
the UI but not in the endpoint we've reverse-engineered), we'll revisit.

**Edge cases:**

- *App launched after a top-up that happened while offline:* detection fires
  on first refresh after launch. The notification is slightly stale but
  still useful ("you got topped up while away"). Don't suppress.
- *Multiple refills in a session:* each fires its own notification. Refills
  are rare; this is fine.
- *Notifications permission denied:* `NotificationManager` should already
  short-circuit. Don't reinvent.
- *Demo build:* the notification path runs the same way as production. The
  demo cycle should include a balance jump that fires it (see the demo
  driver section above).

---

## Acceptance criteria

The PR should:

- [ ] Build cleanly with `xcodebuild -scheme AIQuota` and `xcodebuild -scheme AIQuota-Demo -configuration Demo`

**Auto-reload-aware warnings:**

- [ ] When auto-reload is **off** and balance is low, show red/amber as before (no regression)
- [ ] When auto-reload is **on**, never show red on the credits row — cap at amber below the user's `recharge_threshold`, primary color above it
- [ ] When auto-reload is **on**, show a `· auto-reload` tertiary hint after the credit number
- [ ] If the auto-reload endpoint fails or hasn't loaded yet, treat as `nil` and fall back to absolute-threshold behavior (no crash, no missing tint)
- [ ] No changes to Claude's strip behavior (the existing logic is correct)

**Top-up notifications:**

- [ ] When `creditBalance` increases by > 50 credits between refreshes, a notification fires
- [ ] Notification copy varies based on `codexAutoReload?.isEnabled` at the time of the refill
- [ ] First-launch refresh stores the balance without firing a notification
- [ ] `lastCodexBalance` is updated after every refresh, regardless of whether a notification fired
- [ ] New "Top-up events" toggle in Settings (default ON) gates the notification — if off, no notification fires even on a real top-up
- [ ] No top-up notification path for Claude (no equivalent concept)

**Demo:**

- [ ] Demo cycle exercises both auto-reload states so both code paths are visible without needing real API calls
- [ ] At least one frame in the demo cycle includes a Codex balance jump that fires the top-up notification (with notifications permission granted)

## Open the PR with a clear summary

Final commit + PR should describe:
1. The asymmetry between Codex and Claude auto-reload semantics (so future readers don't try to "fix" the asymmetry)
2. Why the absolute `<$5` / `<$20` thresholds are kept in the auto-reload-off path despite credits not being dollars (out of scope, follow-up)
3. The fail-open behavior on auto-reload fetch errors
4. The top-up notification logic — what it detects, the noise-floor constant, the auto-reload-aware copy, and why it's Codex-only

## Branch context

You're branching off `main`, which already contains:

- `BudgetStripView` for Claude extra usage (`AIQuota/Views/BudgetStripView.swift`)
- The `creditTint` helper for Codex credits (in `PopoverView.swift`)
- Demo driver scaffolding for both signals (`DemoDriver.swift`)
- A public `init` on `ClaudeUsage.ExtraUsage` (`Packages/AIQuotaKit/.../ClaudeUsage.swift`)
- The networking polish: `OpenAIClient` and `ClaudeClient` now use `OSLog.Logger`
  — use that pattern, not `print()`, for any new logging you add.

There is no special prereq branch — just check out `main` and start from there.
