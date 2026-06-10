# Claude Enterprise Support Plan

> **Implementation status (June 10, 2026):** The normalized usage model and
> OAuth-first resolver described here are implemented, but Team and Enterprise
> behavior is not yet field-verified. The implementation also evolved beyond
> this plan: `ClaudeAuthCoordinator` now participates in OAuth credential
> discovery so a user can become authenticated without first establishing a
> WebKit session. The latest Team-connect patch is preserved on
> `team-auth-field-retest` and awaiting Jason's retest. See
> [`team-auth-field-test-handoff.md`](team-auth-field-test-handoff.md) for the
> current continuation state.

## Summary

Fix Claude Enterprise accounts by using the Claude Code OAuth usage path as the
primary source when available, then falling back to the existing browser-cookie
web path. This follows the working CodexBar shape without importing its full
provider framework.

The core failure to avoid is treating every Claude account as if it always has
5-hour and 7-day quota windows. Enterprise accounts may report nullable windows
and spend-limit data instead. AIQuota should show the metric Claude actually
returns, never fake reset timers.

Equally important: existing Pro/Max users must not see worse behavior. A single
transient null-window response should not turn a previously healthy Pro/Max
display into `unknown`, notification cadence should remain unchanged for normal
windowed responses, and richer plan inference must fall back to today's
extra-usage heuristic before showing `Unknown`.

## Key Changes

- Add a normalized Claude metric model with explicit primary display kind:
  `fiveHour`, `sevenDay`, `spendLimit`, or `unknown`.
- Keep Max `extraUsage` separate from Enterprise `spendLimit`; they are related
  quota concepts but not the same product signal.
- Surface the inferred plan label in the app and widgets: `Pro`, `Max`, `Team`,
  `Enterprise`, or `Unknown`.
- Add a Claude Code OAuth usage client:
  - Read `~/.claude/.credentials.json` on every fetch.
  - Optionally read the Claude Code Keychain item only with authentication UI
    disabled; if Security returns `errSecInteractionNotAllowed`, skip it.
  - Require `user:profile` scope.
  - Call `GET https://api.anthropic.com/api/oauth/usage` with
    `anthropic-beta: oauth-2025-04-20`.
  - Do not self-refresh OAuth tokens in v1; on token expiry, tell the user to
    open/run Claude Code to refresh.
- Improve web-cookie fallback:
  - Enumerate `/api/organizations` when `lastActiveOrg` is missing or suspicious.
  - Prefer a chat-capable, non-API-only organization.
  - Fetch `/api/account` when possible for plan and membership hints.
  - Parse `extra_usage` even when `five_hour` and `seven_day` are `null`.

## Data Model Decisions

- `ClaudeUsage` should keep top-level optional window fields:
  - `fiveHourUtilization: Double?`
  - `fiveHourResetsAt: Date?`
  - `sevenDayUtilization: Double?`
  - `sevenDayResetsAt: Date?`
- Add `planLabel: ClaudePlanLabel`, where the cases are `pro`, `max`, `team`,
  `enterprise`, and `unknown`.
- Add `primaryMetric: ClaudeMetric`, where `ClaudeMetric` contains:
  - `kind: ClaudeDisplayKind`
  - `utilization: Double?`
  - `resetAt: Date?`
- `ClaudeMetric` should not store a display label. Its metric-kind display label
  is computed from `kind` so it cannot drift from the enum case.
- `ClaudeDisplayKind` cases are `fiveHour`, `sevenDay`, `spendLimit`, and
  `unknown`.
- Primary metric precedence is fixed:
  1. Use 5-hour when `five_hour.utilization` exists.
  2. Otherwise use 7-day when `seven_day.utilization` exists.
  3. Otherwise use Enterprise spend limit when spend-limit utilization exists.
  4. Otherwise use `.unknown` with nil utilization and nil reset date.
- Keep Max overflow data as top-level `extraUsage: ExtraUsage?`.
- Add separate top-level Enterprise spend data as `spendLimit: SpendLimit?`.
  Do not nest Enterprise spend limit inside `extraUsage`.
- Plan label inference order:
  1. OAuth subscription/rate-limit tier, when present.
  2. Web `/api/account` membership hints, when present.
  3. Today's compatibility heuristic: `extraUsage.isEnabled == true` means
     `max`; otherwise a normal windowed Claude response means `pro`.
  4. `unknown` only when no higher-confidence signal exists.
- Compatibility fields such as `usedPercent`, `limitReached`, `percentFraction`,
  `remainingPercent`, `resetAt`, and `resetAfterSeconds` should derive from
  `primaryMetric`. Reset-based compatibility property types become optional
  where the primary metric has no reset date; do not use sentinel dates such as
  `.distantFuture` or `.distantPast`.

## Implementation Shape

- Keep `ClaudeAuthCoordinator` as the browser sign-in owner; OAuth credential
  discovery belongs to the usage fetcher/resolver, not the coordinator.
- Add a small Claude source resolver:
  - Try OAuth first when usable Claude Code credentials exist.
  - Fall back to web cookies when OAuth is missing, expired, lacks scope, or has a
    normal auth failure.
  - If OAuth returns a policy-flavored 401/403, do not loop endlessly; record a
    diagnostic and show an actionable message while still trying web fallback if
    available.
- Replace compatibility assumptions around `usedPercent`, `resetAt`, and
  countdowns with `primaryMetric`. Existing call sites should read utilization
  and reset data from the primary metric instead of assuming a 5-hour window
  exists.
- Cache-bust old Claude usage with an explicit SharedDefaults schema key, for
  example `cachedClaudeUsageSchemaVersion`. On bootstrap, if the stored version is
  older than the new Claude usage schema, clear cached Claude usage and write the
  new schema version. Keep auth/session state untouched.
- Add a small diagnostics record for the last Claude source attempts, including
  source name, status, and short error category. Store locally for debugging; do
  not expose secrets.

## Resolver Contract

- Claude OAuth credentials are usable only when all of these are true:
  - `~/.claude/.credentials.json` or the non-interactive Claude Code Keychain read
    produced parseable credentials. If both exist, prefer
    `~/.claude/.credentials.json` because Claude Code actively writes it.
  - The access token is non-empty.
  - The token is not expired according to its stored expiry, if an expiry exists.
    Use the credential file's `expiresAt`/expiry metadata for pre-flight checks;
    do not parse the JWT as the primary expiry mechanism.
  - The scopes include `user:profile`.
- OAuth error handling:
  - 401/403 for expired or ordinary auth failure may fall back to web cookies and
    records a popover status row: "Open Claude Code to refresh your session."
  - A policy-flavored 401/403 records a policy diagnostic, disables OAuth for the
    rest of the app session after the first such failure, and surfaces a one-line
    status explaining that Claude Code OAuth usage is unavailable. Policy
    detection is centralized in one helper. It may inspect the transient error
    body, but must not store it. Initial patterns are case-insensitive matches
    for explicit policy language such as `policy`, `disallowed`, `third-party`,
    `third party`, or `not allowed`.
  - If OAuth returns repeated unknown 403 responses with no explicit policy body,
    classify the first two as ordinary auth failures. On the third consecutive
    unknown OAuth 403 in the same app session, disable OAuth for the remainder of
    the session with error category `policyBlocked` and continue using web
    fallback when possible.
  - 429 is rate limiting; do not switch sources in the same refresh. Surface the
    rate-limit error and preserve last-good data.
  - 5xx and network failures are transient OAuth failures; retry according to the
    normal refresh cadence and preserve last-good data. Do not silently switch to
    web cookies for those failures.
  - Invalid/unknown JSON is a source-shape failure; record diagnostics and
    preserve last-good data. Do not silently switch sources in the same refresh.
- Pro/Max transient-null protection:
  - If the last-good Claude snapshot had plan label `pro` or `max`, and a new
    fetch returns null/missing normal windows without an Enterprise spend-limit
    signal, treat it as a transient fetch error.
  - Preserve the cached last-good snapshot, record diagnostics, and retry on the
    normal refresh cadence.
  - Do not transition to `.unknown` for a single null-window response from a
    previously healthy Pro/Max account.
- Web fallback is used only when OAuth is unavailable before the request, lacks
  required scope, is expired, or returns ordinary auth failure.
- Never mix sources inside a single `ClaudeUsage` snapshot. If OAuth succeeds,
  the snapshot is fully OAuth-derived. If OAuth is unavailable or falls back, the
  snapshot is fully web-derived.
- If OAuth and web sources disagree on plan label or identity, the source that
  produced the accepted snapshot wins. In OAuth-first mode, a successful OAuth
  response is authoritative.
- If OAuth fails auth and web fallback also fails auth in the same refresh, the
  user-facing status should be the web failure: "Sign in to Claude." The OAuth
  failure remains in diagnostics only.
- OAuth-first upgrade behavior:
  - Do not clear WebKit cookies or call any sign-out/reset path when bootstrap
    succeeds via OAuth.
  - Existing web cookies remain available as fallback if OAuth later expires or is
    unavailable.
  - Pro/Max users may see OAuth-derived values after upgrade; add parity tests
    against web fixtures and accept small rounding differences only.

## UI And Notification Semantics

- Popover:
  - Normal `fiveHour` primary shows the existing Claude gauge and reset text.
  - `sevenDay` primary shows a weekly Claude gauge and 7-day reset text.
  - `spendLimit` primary shows spend-limit utilization and plan label; it does
    not show a reset countdown unless the API provides an actual reset date.
  - `unknown` primary shows the Claude tile with plan label when known, a dash
    for utilization, and a short status row from diagnostics when available.
- Widgets:
  - Small widget uses the primary metric. For `unknown`, render the Claude logo,
    plan label when known, and `--` in place of the percent.
  - Medium widget uses the primary metric for the main percent and displays the
    secondary window only when that window exists.
  - Widgets must not render synthetic reset countdowns for missing windows.
- Notifications:
  - 5-hour threshold/reset alerts fire only when the 5-hour window exists.
  - 7-day threshold/reset alerts fire only when the 7-day window exists.
  - Enterprise spend-limit threshold notifications are out of scope for v1; show
    spend-limit status in UI only.
  - `unknown` primary never fires threshold or reset notifications.
- User-facing OAuth expiry/policy messages appear in the popover/status surface,
  not as system notifications.

## Diagnostics Contract

- Store only a bounded, redacted diagnostics ring buffer of the last 10 source
  attempts. Each record contains:
  - `source: oauth | web`
  - `httpStatus: Int?`
  - `errorCategory: unavailable | expired | missingScope | policyBlocked |
    rateLimited | serverError | network | invalidResponse | transientNull |
    success`
  - `timestamp: Date`
- Never store or log request headers, response bodies, cookies, access tokens,
  refresh tokens, token prefixes/suffixes, or account identifiers in this
  diagnostics record.

## Test Plan

- Unit test OAuth parsing for Pro/Max, Team/Enterprise, nullable windows,
  spend-limit-only responses, model-specific weekly windows, missing
  `user:profile`, expired token behavior, and policy-flavored 401/403 behavior.
- Unit test web parsing for existing Pro/Max shape, Enterprise null-window shape,
  spend-limit parsing, account membership plan labels, and organization selection
  that ignores API-only orgs when a chat-capable org exists.
- Regression test notifications:
  - No 5-hour threshold or reset alerts when the 5-hour window is absent.
  - No fake 7-day reset alerts when the 7-day window is absent.
  - Spend-limit usage may display status but does not trigger window-reset alerts.
  - For unchanged Pro/Max windowed responses, the same threshold/reset alerts fire
    at the same cadence as before this change.
- Smoke test app and widget rendering for normal Claude Code usage, weekly-only
  usage, spend-limit Enterprise usage, and unknown/no-quantitative-data usage.
- Smoke test upgrade behavior:
  - With valid cached Pro/Max `ClaudeUsage`, first launch after schema upgrade
    clears stale cache, shows a brief loading state, fetches fresh data, and does
    not prompt for re-auth.
  - OAuth-first bootstrap does not clear existing WebKit cookies.
- Add source parity tests for Pro/Max fixtures where OAuth and web responses for
  the same account produce matching primary/secondary utilization, plan label,
  and extra-usage values. Tolerance is `±0.5%` for utilization, exact match for
  plan label, exact match for `extraUsage.monthlyLimit`, and `±1` credit for
  `extraUsage.usedCredits`.
- Run package tests and targeted app/widget tests after implementation.

## Assumptions

- AIQuota remains a focused menu bar quota app, not a CodexBar-style
  multi-source/provider console.
- No user-facing source picker in v1; source choice is automatic.
- No Anthropic Admin API support in v1 because it is account/admin-key oriented
  and does not match the current consumer sign-in flow.
- No Claude CLI PTY fallback in v1; OAuth credentials plus web cookies are enough
  to address the Enterprise failure without terminal automation.
- Claude Code OAuth use is a fragile upstream dependency. AIQuota should degrade
  gracefully if Anthropic blocks this read-only usage endpoint for third-party
  tools.
- Codex Enterprise behavior is out of scope for this plan and should be tracked
  separately if it shows the same nullable-window pathology.
