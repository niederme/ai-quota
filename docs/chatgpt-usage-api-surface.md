# ChatGPT/Codex Usage API — Surface Inventory

> Research notes from inspecting the live `chatgpt.com` web app (Settings →
> Usage / Analytics) via authenticated network calls, 2026-09-18. Purpose:
> give whoever designs further ChatGPT/Codex quota features in AIQuota an
> accurate picture of what data actually exists, so design doesn't outrun
> what's fetchable. None of this is documented publicly — all endpoints are
> undocumented internal `backend-api`/`wham` routes and can change without
> notice.

## Auth (already solved)

All `backend-api` calls need `Authorization: Bearer <access_token>`, not just
cookies (cookie-only requests 401). AIQuota already has two paths to this
token per [`codex-cli-oauth-support-plan.md`](codex-cli-oauth-support-plan.md):
Codex CLI OAuth (`~/.codex/auth.json`) preferred, WebKit ChatGPT session as
fallback. No new auth work needed for the endpoints below — same bearer token
works for all of them.

## Already implemented

`GET /backend-api/wham/usage` — this is the only endpoint AIQuota currently
calls (`CodexUsage.swift`, `OpenAIClient.swift`). Confirmed shape still
matches what's decoded today:

```jsonc
{
  "plan_type": "prolite",
  "rate_limit": {
    "allowed": true, "limit_reached": false,
    "primary_window": { "used_percent": 56, "limit_window_seconds": 604800,
                         "reset_after_seconds": 261856, "reset_at": 1790015277 },
    "secondary_window": null  // some accounts get weekly in primary, 5h in secondary — already normalized in CodexUsage.init
  },
  "credits": {
    "has_credits": true, "unlimited": false, "balance": "260.9493799584",
    "approx_local_messages": [65, 339], "approx_cloud_messages": [10, 65]
  },
  "model_usage": { "gpt-6-astra": { "available": true, "available_at": null, "credits_would_enable": false } },
  "spend_control": { "reached": false, "individual_limit": null },
  "rate_limit_reset_credits": { "available_count": 0, "applicable_available_count": 0 }
}
```

## Not yet used — candidates for `bonusCreditsSpentThisMonth`

`CodexUsage.bonusCreditsSpentThisMonth` is wired into `PopoverView` and
`AIQuotaWidget` but is hardcoded to `nil` in the real `init(from:)` — only the
placeholder/demo data populates it. Two live endpoints could fill this gap:

### `GET /backend-api/accounts/{account_id}/remaining_balance`

Per-grant credit balance with expiry, closest match to "bonus credits":

```jsonc
{
  "balance": "260.9493799584",
  "expiring_balance_details": [
    { "amount_granted": "252", "amount_remaining": "7.9493799584",
      "expiry_date": "2027-09-14T13:03:10.148959Z", "grant_type": "auto_recharge_credit" },
    { "amount_granted": "253", "amount_remaining": "253",
      "expiry_date": "2027-09-14T13:24:30.491108Z", "grant_type": "auto_recharge_credit" }
  ]
}
```

"Spent this month" would have to be derived (`amount_granted - amount_remaining`
per grant, filtered/summed by grant date) — the API gives balance snapshots,
not a spend delta. **Open question:** `{account_id}` in the path — on
chatgpt.com it's a UUID pulled from web app session/account state
(`WhamUsageResponse.accountId` was empty string in `/wham/usage` for this
personal account, so it's not sourced from there). Need to confirm whether
Codex CLI's `auth.json` `tokens.account_id` (already parsed per the OAuth plan
doc) is the same ID or a different one — untested from this session.

### `GET /backend-api/wham/usage/daily-token-usage-breakdown?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD&group_by=day`

Powers the Analytics tab's "Plan usage" / "Credits spent" charts. Per-day,
per-model and per-surface credit consumption:

```jsonc
{
  "data": [
    {
      "date": "2026-08-20",
      "product_surface_usage_values": {
        "cli": 0, "vscode": 0, "web": 0, "work_web": 0, "mobile": 0,
        "work_mobile": 0, "slack": 0, "linear": 0, "jetbrains": 0, "sdk": 0,
        "exec": 0, "github": 0, "desktop_app": 2.4765620431462705,
        "work_desktop": 0, "github_code_review": 0, "agent_identity": 0, "unknown": 0
      },
      "models": [
        { "model": "gpt-5.6-sol", "speed": "standard", "credits": 1.5034274468985305 },
        { "model": "gpt-5.6-terra", "speed": "standard", "credits": 0.9493152653183328 }
        // ...
      ]
    }
    // one entry per day in range
  ]
}
```

Only `group_by=day` was observed (week/month not tested). Model and surface
values are two breakdowns of the same usage, so never add their totals together.
These plan-usage credits do not establish paid overage charges by model or app.
The iOS detail retains both breakdowns for 7-day and 30-day attribution, combining
speed variants of each model. Missing breakdowns remain unavailable; older cached
history continues to decode. No local usage-history collection is introduced.

The separate `credit-usage-events` response supplies the displayed monthly
"Credits used" dollar amount. It measures credit consumption, not credit purchase
transactions. Provider day-boundary timezone and hourly history remain unverified.

### Recommendation

For just filling `bonusCreditsSpentThisMonth`, `daily-token-usage-breakdown`
summed over the current month is more self-contained (no account_id lookup
needed, same auth as the existing call). `remaining_balance` is better suited
if a future feature wants per-grant expiry display (e.g. "$7.95 expires
2027-09-14"), which `daily-token-usage-breakdown` can't provide.

## Other endpoints seen, not immediately useful

- `GET /backend-api/wham/rate-limit-reset-credits` — free "reset now" tokens
  (`available_count`, `total_earned_count`, `immediate_reset_purchase_eligible`).
  Surfaces the manual "Usage limit resets" feature in Settings → Usage; not
  quota data, would only matter if AIQuota ever exposed a manual-reset action.
- `GET /backend-api/wham/rate-limit-reset-credits/history` — paginated event
  log (`events: [{id, kind: "granted"|"used", occurred_at}]`, `next_cursor`)
  backing the "Reset used / Reset received" list on that same settings page.
- `GET /backend-api/pageConfigs/usage_limits` — just feature flags
  (`show_usage_tab`, `show_credits`, etc.), not data.

## Constraints to design around

- Everything is a snapshot/poll endpoint — no push/websocket for usage changes.
- All of this is internal/undocumented — no stability guarantee, no official
  support, could 401/shape-change without notice (same caveat already called
  out for `/wham/usage` in the OAuth plan doc).
- Bearer token is the only auth; there is no separate official "usage API" key
  for consumer ChatGPT accounts (unlike the OpenAI *platform* API, which is a
  different product and different billing/usage surface entirely — not
  explored here since AIQuota tracks consumer plan quota, not platform API spend).
