# Budget warning design

> **Status:** Decided and implemented. Bars are exception states, not routine
> status. Keep this rule in mind before adding new warning chrome to the popover.

## Final rule

The popover should stay quiet during normal and caution states. Text color is
enough for caution. A bar earns space only when the user has crossed into an
exception state.

- **Normal:** text only, primary color.
- **Caution:** text only, amber or red as appropriate for that metric.
- **Exception:** show the bar.

This keeps the popover from turning into an accounting dashboard and gives bars
a clear meaning: "look here now."

## Claude extra usage

Claude's extra usage has a real denominator: `usedCredits / monthlyLimit`.
That makes `BudgetStripView` honest, but it should still appear only once the
monthly extra cap has been reached.

Current rules:

| Monthly extra utilization | Treatment |
|---|---|
| `< 85%` | `Extra` row in primary / secondary |
| `85%...99%` | `Extra` label and value both in amber |
| `>= 100%` | `BudgetStripView` |

There is intentionally no red text tier between amber and the bar. The bar is
the cliff signal; pairing it with a red text tier just below it would mean two
"imminent" indicators back-to-back, which overstates the urgency and makes the
popover feel noisier than the situation actually is. At 95% utilization the
user still has real headroom — amber is the right "heads up" level until the
bar actually appears.

Important: this tinting is based only on the monthly extra cap. It should not
inherit the 5-hour or 7-day gauge state. For example, if the Claude 5-hour ring
is amber at 93% but monthly extra is 79%, `Extra` should remain primary.

## Codex credits

Codex does not have a routine denominator comparable to Claude's monthly cap.
The auto-reload endpoint can provide an honest reference (`rechargeTarget`), but
that does not mean the popover should always draw a bar.

Current rules:

- If no auto-reload settings are known, show text only.
- If auto-reload is enabled and the balance is below `rechargeThreshold`, show
  amber text plus the quiet `· auto-reload` hint. Do not show a bar; the refill
  is expected.
- If credits are low with no active safety net, use text color first.
- If credits are exhausted (`0`) while auto-reload settings are known but
  disabled, show the Codex exception bar.

The Codex bar uses depletion from target:

```swift
fractionDepleted = (rechargeTarget - currentBalance) / rechargeTarget
```

So, with `threshold: 125` and `target: 250`:

| Balance | Fraction depleted | Bar reads |
|---|---|---|
| `250` | `0%` | empty |
| `125` | `50%` | half full |
| `0` | `100%` | full |

Both Claude and Codex bars therefore fill toward "bad," but Codex only draws the
bar in the exhausted/no-active-reload exception state.

## Demo coverage

The Demo scheme should demonstrate both exception bars:

- Claude reaches and exceeds monthly extra cap (`100%`, then `103%`) so
  `BudgetStripView` appears.
- Codex reaches `Credits: 0` with reload configured but off, so the Codex
  exception bar appears, then auto-reload turns on and the balance jumps to the
  target.

## Follow-ups

- Claude currency formatting is still worth a separate polish pass. The API
  includes `currency`, but the UI currently renders compact credit-style values.
- Codex low-credit thresholds (`< 20` amber, `< 5` red) are still inherited from
  earlier dollar-thinking. They are intentionally left alone here, but deserve
  a separate calibration pass against real credit burn.
- Burn-rate runway text may become more useful than additional bars once daily
  credit consumption is available from `credit-usage-events`.
