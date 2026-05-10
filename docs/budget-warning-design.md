# Budget warning design — open conversation

> **Status:** Open design discussion, not a build spec. Everything below is the
> shape of a thought, not a decision. Pick this up before building anything new
> on top of `BudgetStripView` or `creditTint`.

## Where we are today

Two warning treatments live in the popover, both shipped:

- **Claude — `BudgetStripView`** (`AIQuota/Views/BudgetStripView.swift`)
  - Renders inside the Claude column of the stats row when
    `extraUsage.utilization >= 70`
  - Bar **fills up** as utilization grows: amber from 70%, red at 85%
  - Fraction is honest: `usedCredits / monthlyLimit`, both real values from the
    `/overage_spend_limit` endpoint
  - Hides entirely below 70% (option-3 "only when actionable" pattern)

- **Codex — value tint** (`creditTint(_:autoReload:)` in `PopoverView.swift`)
  - Just a colored number, no bar. `Credits: 230` in primary; amber below
    the user's `rechargeThreshold` (or `$20` if no auto-reload configured);
    red below `$5`
  - When auto-reload is on, urgency is capped at amber + a `· auto-reload`
    tertiary hint
  - Always visible (so long as `creditBalance` is known)

The asymmetry was deliberate — Codex's API doesn't return a denominator the
way Claude's does. We picked tint-without-bar to be honest about that.

## The question that opened this conversation

**Codex genuinely could now have a bar**, since the auto-reload endpoint gives
us `rechargeTarget` and `rechargeThreshold`. So:

- Should it?
- If yes, should the bar fill the same direction as Claude's (toward "bad")
  or invert (deplete toward zero)?
- What threshold gates visibility?
- Does Claude's existing 70% threshold still feel right once we re-examine
  the bigger picture?

## Harmonized direction — both bars fill toward "bad"

Original instinct was to invert (Claude fills up; Codex empties down). But
that puts two bars in the same popover that read opposite directions, which
fights itself visually.

If we instead define Codex's bar as "**fraction depleted from full**":

```
fractionDepleted = (rechargeTarget - currentBalance) / rechargeTarget
```

Then for a user with `threshold: 125 / target: 250`:

| Balance | Fraction depleted | Bar reads |
|---|---|---|
| 250 (target, just refilled) | 0% | empty |
| 125 (threshold, refill imminent) | 50% | half full |
| 0 (cut off / refill failed) | 100% | full |

Both Claude's strip and a Codex strip would fill in the same direction
(toward red as things get worse). That's worth doing.

## Wrinkle 1: reference availability for Codex

A bar needs a "100% full" reference point. For Claude that's
`monthly_credit_limit` — always present, always meaningful. For Codex, the
candidates are:

- **`rechargeTarget`** from `auto_top_up/settings`. Persisted even when
  `is_enabled = false`. Honest.
- **Last manual purchase amount.** We'd have to track this ourselves. Magic;
  opaque.
- **Highest balance seen recently.** Heuristic; opaque.
- **A hardcoded constant.** Lying.

`rechargeTarget` is the only honest option. Implication: **Codex bar requires
the user to have at some point configured auto-reload**, even if it's
currently disabled. If they haven't, fall back to the existing tint-only
treatment.

## Wrinkle 2: per-user thresholds vs a single global rule

Claude's "show the bar at 70% utilization" is a number we picked. It's the
same for everyone.

Codex's natural threshold isn't a constant — it's the **user's own**
`rechargeThreshold / rechargeTarget` ratio. For one user that's 50%
(125/250); for another it might be 30% (75/250). So there's no single
"show at X%" rule for Codex; it's "show when **below the user's own
threshold**."

That actually feels more honest. The user has already told the system
what counts as "low" for them — we should use it.

## Wrinkle 3: auto-reload state changes the meaning, not the visual

Same Codex bar reads differently depending on `is_enabled`:

- **Auto-reload ON:** "approaching next refill." Mild interest. Refill is
  imminent. Don't escalate to red — refill is the resolution.
- **Auto-reload OFF:** "approaching empty without a safety net." Escalate
  to red as the bar fills further.

This is exactly the logic the existing `creditTint` already does — just
expressed visually as a bar instead of as text color. No new logic, just
a different presentation surface.

## The bigger question this surfaces

> **When do we show *either* bar?**

Right now Claude's strip uses a hand-picked global threshold (70%). If we
add a Codex bar with a per-user threshold, the popover has two different
"when to show" rules. That's worth unifying.

Candidate unified rule (sketch — not a decision):

> Show the bar when the user is below their own actionable threshold for
> that service. For Claude, "actionable" means utilization above 70% (we
> still pick this number — Anthropic's API doesn't give us a per-user
> threshold setting). For Codex, "actionable" means balance below the
> user's `rechargeThreshold`.

Or alternatively:

> Always show the bar once it has data; let color carry urgency. Below
> threshold = neutral; near threshold = amber; past threshold = red.

The first hides chrome until it matters (matches our existing
"only-when-actionable" instinct on the strip). The second normalizes the
visual layout regardless of state. Both are defensible. **Discuss before
building.**

## Adjacent issues worth flagging in the same pass

- **Currency formatting for Claude.** The strip currently renders
  `Extra: 6342 / 8k` for a user whose `monthly_credit_limit` is 8000 in
  USD. The API response includes `"currency": "USD"`, so we should be
  rendering as `$6,342 / $8k`. Pure visual polish; small change in
  `BudgetStripView.swift`.

- **Codex credit-unit recalibration.** The `<$5` red / `<$20` amber
  thresholds in the auto-reload-OFF path were dollar-thinking; Codex
  credits are abstract units. Daily burn is in 100–300 credit territory,
  so 20 is comfortably "running on fumes" for most users — but it's still
  arbitrary. Not urgent, but we should pick numbers that feel reasoned
  rather than inherited.

- **Burn-rate runway** ("≈ 3 days remaining at current pace"). The
  `/wham/usage/credit-usage-events` endpoint returns daily consumption —
  enough to compute a rolling rate. Could appear inline next to the
  Codex credit number when balance is low. More information than just
  a tint, more honest than a fake-denominator bar. Worth considering as
  an alternative to (or in addition to) the Codex bar idea.

## Suggested next conversation

Before any code change, agree on:

1. **Do we want a Codex bar at all?** If runway-text is more useful than a
   bar, the bar conversation collapses.
2. **If we do want a Codex bar — unified "when to show" rule for both
   services.**
3. **Currency formatting for Claude** can ship anytime; it's small and
   independent.

Implementation only after these are settled.
