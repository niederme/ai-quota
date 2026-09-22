# Claude Usage API — Surface Inventory

> Companion to [`chatgpt-usage-api-surface.md`](chatgpt-usage-api-surface.md).
> Research notes from inspecting the live `claude.ai` web app (Settings →
> Usage / Billing) via authenticated network calls, 2026-09-18. Purpose: same
> as the ChatGPT doc — an accurate picture of what's fetchable, cross-checked
> against what `ClaudeClient.swift` / `ClaudeUsage.swift` already implement,
> so design work doesn't chase data that isn't there (or miss data that is).

## Headline: Claude support is already much further along

Unlike ChatGPT, this isn't a from-scratch inventory — AIQuota already has two
auth paths (Claude Code OAuth via `api.anthropic.com/api/oauth/usage`,
web session fallback via `claude.ai/api/organizations/{orgId}/usage`) and
decodes five-hour window, seven-day window, extra usage, bonus usage, spend
limit (enterprise), and usage credits, all with plan-label-aware branching.
The three items below are genuine gaps found by diffing the live response
against `ClaudeUsageResponse` in `ClaudeClient.swift` — not a "here's how
auth works" writeup, since that's already solved.

## Gap 1: `seven_day_breakdown` — per-surface split of the weekly window, unused

The `/api/organizations/{org_id}/usage` response (the one endpoint that
powers Settings → Usage) includes this field, which is not in
`ClaudeUsageResponse` at all today:

```jsonc
"seven_day_breakdown": {
  "as_of": "2026-09-18T17:48:57.074605+00:00",
  "window_started_at": "2026-09-16T18:00:00.015546+00:00",
  "rows": [
    { "key": "claude_code", "display_name": "Claude Code", "percent": 89 },
    { "key": "chat",        "display_name": "Chats",       "percent": 12 },
    { "key": "cowork",      "display_name": "Cowork",      "percent": 0 },
    { "key": "other",       "display_name": "Other",       "percent": 0 }
  ]
}
```

This is exactly the "which surface ate my weekly quota" breakdown the
Analytics tab shows on the ChatGPT side (product_surface_usage_values) — for
Claude it's simpler (percent of the window, not a credits figure) and comes
free on the same call AIQuota already makes. No new request needed, just
decoding. Given AIQuota's own audience is disproportionately Claude Code
users, "88% of your weekly limit was Claude Code" is a strong candidate for
the popover/widget.

## Gap 2: `limits[]` — a newer generalized array, unused

Same response also carries a `limits` array that looks like it's meant to
eventually replace the named `five_hour` / `seven_day` fields with a generic
shape:

```jsonc
"limits": [
  { "kind": "session", "group": "session", "percent": 46, "severity": "normal",
    "resets_at": "2026-09-18T19:40:00.015522+00:00", "scope": null, "is_active": true },
  { "kind": "weekly_all", "group": "weekly", "percent": 6, "severity": "normal",
    "resets_at": "2026-09-23T18:00:00.015546+00:00", "scope": null, "is_active": false }
]
```

Nothing actionable here yet since it's redundant with `five_hour`/`seven_day`
for this account (same percents, same reset times) — but it's worth knowing
this shape exists, in case Anthropic drops the named fields in favor of it
later. `is_active` on the weekly entry being `false` while session's is `true`
is interesting (`is_active` may mean "this is the binding/limiting one right
now" rather than "this window is in effect") — untested since I couldn't
trigger a state where a non-session window was the active one.

Also present but null for this Pro account, worth flagging as unexplored
rather than ignoring: `seven_day_oauth_apps`, `seven_day_opus`,
`seven_day_sonnet`, `seven_day_cowork`, `seven_day_omelette`, `tangelo`,
`iguana_necktie`, `omelette_promotional`, `nimbus_quill`, `cinder_cove`,
`copper_kite`, `harbor_lantern`, `amber_ladder`, `juniper_tide`,
`cedar_ember`, `amber_gauge`. Most look like internal codenames for
experiments or other plan tiers' windows — `seven_day_opus`/`seven_day_sonnet`
are already handled by `preferredSevenDayWindow`'s fallback chain, the rest
are unknowns that showed up as `null` and weren't investigated further.

## Gap 3: credit balance doesn't come from `/usage` at all

The Settings → Usage page shows "$197.86 Current balance · Auto-reload On"
under Usage credits — but `spend.balance` in the `/usage` response is `null`.
AIQuota has no balance concept for Claude credits today (only
`usageCredits.spent` / `monthlyLimit`, i.e. spend against a cap, no running
balance). The actual source, confirmed by watching the Billing tab's network
calls, is a separate endpoint:

`GET /api/organizations/{org_id}/prepaid/credits`

```jsonc
{
  "amount": 19786,              // total balance, minor units (i.e. $197.86)
  "currency": "USD",
  "balance": { "money": null, "credits": { "amount_minor": 19786, "exponent": 2 } },
  "balance_credits": 197,
  "auto_reload_settings": { "enabled": true, "threshold_in_minor_units": 500, "reload_to_in_minor_units": 1500 },
  "tranches": [
    {
      "remaining_amount_minor_units": 412, "granted_amount_minor_units": 1019,
      "granted_at": "2026-05-11T14:52:54.731000Z", "expires_at": null,
      "program_id": "auto_recharge_additional_usage_individual",
      "id": "f0161fa9-e027-5bcc-999b-23b4828369f8",
      "scope": { "kind": "unscoped", "applies_to": [] }
    }
    // one entry per grant — same shape as ChatGPT's expiring_balance_details
  ]
}
```

Structurally this is the Claude-side twin of ChatGPT's
`/backend-api/accounts/{account_id}/remaining_balance` (see the companion
doc) — running balance plus a per-grant/tranche breakdown with expiry. Same
`{org_id}` as the existing `/usage` call (`ctx.orgId}` from
`ClaudeAuthCoordinator`), so no new ID-resolution problem like ChatGPT's
unresolved `account_id`.

## Endpoints seen but not pursued

- `GET /api/stripe/{org_id}/balance` — Stripe payment-method info for the
  Billing page, not quota data.
- `POST /api/organizations/{org_id}/subscription/refund/eligibility` —
  billing/refund flow, irrelevant to usage tracking.

## Constraints to design around

- Both new fields (`seven_day_breakdown`, `limits[]`) ride the existing
  `/usage` call — zero new network round-trips for Gap 1 and 2.
- The credit-balance endpoint (Gap 3) is a second call, same auth/org-id
  already in hand — same cost profile as adding one more field fetch.
- Same fragility caveat as ChatGPT: undocumented internal API, codenamed
  fields suggest active internal churn on this response shape, no stability
  guarantee.
