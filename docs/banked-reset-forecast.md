# Codex banked resets in weekly forecasts

This is read-only context in the existing weekly forecast, not reset redemption.
No new request, credential scope, purchase or consume endpoint is introduced.

The existing account-scoped `/backend-api/wham/usage` response may include
`rate_limit_reset_credits.available_count` and `applicable_available_count`.
The former is the banked balance. Missing/null/malformed values stay unknown,
including old caches. Negative, fractional or contradictory counts are not shown.
The optional applicability count is preserved, but its undocumented semantics
are not used to promise that a reset can be redeemed immediately.

Only the current Codex weekly forecast can display the count, and only when
its app account and verified provider identity match the snapshot. If the usage
response explicitly names a different account from the authenticated request,
the reset count is discarded; missing/empty response identity relies on the
existing authenticated account-scoped request, without a new lookup. The count
expires as current UI evidence after five minutes (independent of the longer
weekly forecast lifetime). Unknown/stale counts retain the ordinary pace detail.
A confirmed zero explicitly says no banked resets are available. One uses
“reset”; other positive counts use “resets”. The scheduled refresh remains the
provider's weekly reset date, never a reset expiry or a locally adjusted date.
Partial responses may retain old quota windows without refreshing their timestamp,
but invalidate an older reset balance, including in the primary Mac model/cache.

The user's chosen account presentation is passed through unchanged. Provider IDs
are never printed. This change adds no banked-balance disclosure to notifications,
widgets or their general allowance accessibility summaries. The in-app forecast's
VoiceOver summary includes its visible count/time; its hint distinguishes manual
redemption from the scheduled refresh. Existing dismiss targets and responsive
wrapping are retained.

## Semantics checked 2026-11-03

- [OpenAI: How resets work in Codex](https://help.openai.com/en/articles/20001498-how-resets-work-in-codex): receiving a banked reset does not apply it, unused resets can expire, and its banked balance differs from automatic/global resets and purchased instant resets. Availability depends on the account/offer, not a public announcement.
- [Official Codex backend models, pinned source](https://github.com/openai/codex/blob/bfdbf01bfaeaa6ab23b10e2bd64ed031fd1e5619/codex-rs/backend-client/src/types.rs): optional `rate_limit_reset_credits` with integer `available_count` alongside quota data.
- [Official app-server summary](https://github.com/openai/codex/blob/bfdbf01bfaeaa6ab23b10e2bd64ed031fd1e5619/codex-rs/app-server-protocol/schema/typescript/v2/RateLimitResetCreditsSummary.ts): count may be known without per-credit details; detail rows may be capped. We do not infer expiration or count from history/detail list length.
- [Existing AIQuota response inventory](chatgpt-usage-api-surface.md): both optional WHAM count fields were previously observed. WHAM remains undocumented and can change; no new live account payload or credentials were inspected for this work.
