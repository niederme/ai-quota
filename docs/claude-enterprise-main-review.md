# Review of `main` after the Enterprise / OAuth work

Status note: this review was written against `main` at `77f2ed7`, before the
coordinator-level OAuth fix. Issue 0 was addressed by `520734c` ("Route Claude
OAuth through auth coordinator"). The remaining issues and hypotheses are
preserved as follow-up context.

Current continuation note (June 10, 2026): Jason's first Team retest still
failed before usage loading. Claude fell through to the embedded WebKit login,
and Codex appeared signed in but remained on a spinner with a separate probe
returning HTTP 401. A newer Security.framework Claude Keychain reader and Codex
Team workspace-ID fallback are preserved on `team-auth-field-retest` and are
waiting on Jason's next retest. See
[`team-auth-field-test-handoff.md`](team-auth-field-test-handoff.md) before
continuing this work.

Handoff for the agent continuing this work. Findings are tagged with confidence
so you can tell what's grounded in the code from what's a hypothesis worth
checking.

- **Verified** — claim is directly observable in the code or tests.
- **Likely** — strong indirect evidence (e.g., commit messages, test fixtures)
  but not directly exercised.
- **Hypothesis** — plausible failure mode worth defending against, but I have
  no data confirming it. Do not treat as a known regression.

## Field context driving this work

Three reports against the current shipped build:

- **Jason** (Team plan): WebKit sign-in window fails with Anthropic's generic
  "There was an error logging you in" on the Cowork-era login page.
- **Khoi** (Individual Max plan): WebKit sign-in opens, never completes,
  AIQuota's Claude tile stays on `Connect` with a spinner.
- **Repo owner** (Pro plan): ran an archive build of `main` (containing
  77f2ed7). Claude tile showed `Connect`. Clicking it opened the WebKit login
  window — despite Claude Code being authenticated on the same machine, and
  despite being signed into claude.ai in a normal browser.

Pattern: **Pro works (cached), Max+ fails (fresh), fresh sign-in on `main`
still routes through the WebKit login window for everyone.** The bug is
sign-in, not usage parsing. The Enterprise null-window parsing work is
necessary but does not, by itself, unblock these users — none of the parser
changes ship value until they can authenticate.

## What's on `main` (relevant commits, newest first)

```
c83cea0 Add Claude Team plan test handoff
520734c Route Claude OAuth through auth coordinator
77f2ed7 Preserve provider sessions during auth bootstrap
79c60f2 Improve Claude plan and usage parsing
85fa76f Disable legacy keychain fallback in production
1db25d9 Avoid legacy keychain prompts during launch
7e74c57 Suppress keychain password prompts on reads
326dcab Add auth diagnostics surface
661993a Add Codex CLI OAuth auth support
829df79 Add Claude Code Keychain OAuth fallback
2d70484 Add Claude Enterprise OAuth support plan
```

Planning docs are `docs/claude-enterprise-support-plan.md` and
`docs/codex-cli-oauth-support-plan.md`.

## What landed cleanly (Verified)

- **`ClaudeUsage` shape matches the spec.** Optional `fiveHour*` / `sevenDay*`,
  `primaryMetric: Metric` with `kind`/`utilization`/`resetAt`, `displayLabel`
  computed from `kind` (not stored), `planLabel` enum with `pro/max/team/enterprise/ultra/unknown`,
  `SpendLimit` and `ExtraUsage` as distinct top-level optionals. No sentinel
  dates. See `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/ClaudeUsage.swift`.
- **Schema-versioned cache-bust.** `currentClaudeUsageSchemaVersion = 2`,
  cache cleared on version mismatch. `SharedDefaults.swift:7-8, 54-58`.
- **Ring buffer of last 10 source attempts.** `SharedDefaults.swift:12, 69-78`.
  Encoded record has only `source`, `httpStatus`, `errorCategory`, `timestamp`
  — no secrets. `ClaudeSourceAttempt.swift`.
- **Three-strikes policy gating.** `ClaudeClient.swift:36-49` — policy-flavored
  401/403 disables OAuth for the session immediately; generic 403 increments a
  counter and disables only after the third strike.
- **Source-mixing prevention.** OAuth and web fetches construct fully-source-
  derived snapshots; no field-level mixing. `ClaudeClient.swift:252-273`.
- **Pre-flight expiry check uses stored `expiresAt`, not JWT** (for Claude).
  `ClaudeOAuthCredentialsStore.swift:11-18, 121`.
- **File-vs-Keychain precedence: file wins.** Verified by
  `ClaudeOAuthCredentialsStoreTests.fileCredentialsWinOverKeychainCredentials`.
- **CodexBar attribution.** `ClaudePlan.swift:3-7` cites the source repo and
  MIT license. Could be tightened to a commit SHA for bulletproof compliance.
- **`AuthInstallStateTests` enforces the no-clear-WebKit invariant** —
  structural test (greps for the comment string), but it's there.

## Verified issues to address

### 0. OAuth-first is wired in at the wrong layer (addressed by `520734c`)

OAuth credentials gate the **usage fetch** path inside `ClaudeClient.fetchUsage()`,
but the **sign-in / authentication** path does not consult them. Concretely:

- `ClaudeClient.fetchUsage()` calls `ClaudeOAuthCredentialsStore.loadUsable()`
  and prefers OAuth over web cookies. Correct, per spec.
- `ClaudeAuthCoordinator.signIn()` and `bootstrap()` use only the WebKit cookie
  probe at `WKWebsiteDataStore.default().httpCookieStore`. OAuth credentials
  are never read at the coordinator level.
- `fetchUsage()` is only called once the coordinator is `.authenticated`. A
  user with valid Claude Code OAuth credentials but no AIQuota WebView
  cookies will therefore see the `Connect` button, click it, and be routed
  into the WebKit login window — the exact flow that has been failing for
  Max+ / Team users on the Cowork-era login page.

The repo owner's own test on a `main` archive build confirms this: Claude
Code authenticated on the machine, claude.ai signed in in a regular browser,
AIQuota still routes to the WebKit login window because that's the only
authentication path the coordinator knows about.

**Recommendation**: extend `ClaudeAuthCoordinator` so `signIn()` and
`bootstrap()` attempt OAuth credential discovery as a *first* path. If
`ClaudeOAuthCredentialsStore.loadUsable()` returns usable credentials, the
coordinator should be able to transition to `.authenticated` without opening
the WebKit window. The org ID needed for downstream calls can be obtained
from the OAuth usage response itself (it returns plan + identity context) or
by an authenticated call to `/api/organizations` using the OAuth bearer token
instead of cookies. The WebKit login window should remain only as a fallback
for users without Claude Code installed.

This is the single change that would unblock Khoi and Jason without requiring
us to reverse-engineer whatever Anthropic changed in the Cowork-era sign-in
page. Until this lands, the entire OAuth-first stack is invisible to users
who can't get past the WebKit door.

### 1. `isPolicyBlockedResponse` matches too broadly

`ClaudeClient.swift:319-329` triggers immediate session-disable on any 401/403
whose body contains `"policy"` or `"unsupported"`. Both words appear in benign
error responses ("password policy," "Unsupported API version"). A single
unlucky 401 short-circuits the three-strikes safety net you specifically
designed.

Mitigation: require a strong signal (`"disallowed"` / `"third party"` /
`"third-party"`) and treat `"policy"` / `"not allowed"` / `"unsupported"` as
weak signals only, *or* drop the weak signals entirely and rely on the
three-strikes counter for ambiguity. The specific disambiguation heuristic
should be verified against an actual Anthropic policy-block response body —
my prior suggestion to require `"oauth"`/`"token"` co-occurrence was invented,
not observed.

### 2. The diagnostics ring buffer has no consumer

`SharedDefaults.appendClaudeSourceAttempt(...)` is called from every fetch.
Nothing reads `loadClaudeSourceAttempts()` in the app or widget. `SettingsView.swift`
contains no reference to it. The buffer is correct, persisted, redacted — and
invisible. Either wire a debug menu / "About this fetch" surface to render the
last attempts (matches the spec's "diagnostics consumer is unspecified" item),
or accept that the data is reachable only via lldb / `defaults read` and say
so explicitly.

### 3. `shouldPreserveClaudeLastGood` has a narrow predicate

`QuotaViewModel.swift:652-658` preserves last-good only when the new
`primaryMetric.kind == .unknown` and there's no spend-limit. This catches the
"all windows nil" case but not partial cases.

**Whether this matters depends on which transient failures Anthropic actually
returns** — a question I do not have data for. The spec's phrasing ("null/missing
normal windows") would justify a broader predicate (e.g., preserve when a
cached `.fiveHour` user's new snapshot is anything other than `.fiveHour` with
no spend-limit signal), but the broader predicate has a real false-positive
risk: if Anthropic returns `null` for a *legitimately exhausted* 5h window
rather than `utilization: 100`, the broader predicate would freeze the gauge
on stale data forever.

**Action**: capture the actual response shape for a Max user at 100% 5h usage
before changing this. If Anthropic returns `utilization: 100`, broaden safely;
if they return `null`, the narrow current predicate is correct and the spec
should be revised. Do not change this code on intuition.

### 4. The OAuth-rate-limit-tier → planLabel path is not unit-tested end-to-end

`ClaudePlanTests` covers `ClaudePlan.label(...)` in isolation. `ClaudeUsageModelTests.decoderUsesModelSpecificWeeklyFallbacks`
passes `planLabel: .max` *explicitly* to `_decodeUsageForTesting` rather than
relying on the inference from a fixture's `rate_limit_tier` field. There is no
test that exercises the path "OAuth response with rate_limit_tier=X → inferred
planLabel=X" through `ClaudeClient.buildUsage`. Adding one would lock down
the user-facing plan label behavior end-to-end.

### 5. No test fixture for Enterprise on the OAuth path

`enterpriseSpendLimitDecodesCentsAsDollars` exercises Enterprise via `source: .web`.
There is no equivalent fixture for `source: .oauth`. The cents-vs-dollars
divisor at `ClaudeClient.swift:300` (`divisor = source == .web ? 100.0 : 1.0`)
is an assumption that the OAuth response uses dollars. **Verify the actual
OAuth response denomination for Enterprise before shipping** — capture one
fixture from a real account, add it as a test. If OAuth also returns cents,
the divisor logic is wrong and will silently misreport Enterprise spend.

### 6. The resolver's fallback path is not unit-tested

`ClaudeClient.fetchUsage()`'s decision logic (OAuth try, three-strikes, policy
detection, fallback to web) has no direct test. Component pieces are tested
(`buildUsage`, plan inference, credential parsing) but the orchestration that
the spec spent the most pages defining is exercised only via integration.
Worth adding tests with a stub `URLSession` to lock down: three consecutive
generic 403s disable OAuth; policy-flavored 401 disables immediately; 5xx
does not switch sources; 429 does not switch sources.

## Hypotheses that should be checked, not shipped on

- **Hypothesis: `security find-generic-password -w` prompts for Keychain
  password on first run.** Three commits in this stack reference suppressing
  Keychain prompts, which is strong indirect evidence the issue is real, but
  the exact mechanism (prompt vs. silent failure vs. timeout) was not
  verified. Test on a clean macOS user account before assuming current
  mitigations are complete.
- **Hypothesis: Anthropic's transient response for a Max user drops `fiveHour`
  while keeping `seven_day`.** See Issue 3. Capture real failure-mode data
  before tuning `shouldPreserveClaudeLastGood`.
- **REFUTED: 77f2ed7's probe-before-login flow fixes Khoi and Jason.** Repo
  owner ran an archive build of `main` containing 77f2ed7 and the WebKit
  login window still opened on Connect, despite Claude Code being
  authenticated on the same machine. The probe only inspects AIQuota's own
  `WKWebsiteDataStore.default()` cookie jar; it cannot use OAuth credentials
  or cookies from other browsers. The commit's value is preserving valid
  AIQuota-internal cookies across updates — not bridging users who have
  never successfully signed into AIQuota. See Issue 0 above.

## Codex side (lighter pass)

- `CodexOAuthCredentialsStore` reads `$CODEX_HOME/auth.json` then `~/.codex/auth.json`
  with snake/camel/raw-snake-case key coverage (`access_token` / `accessToken`).
  No write-back implemented — the write-back race the Codex plan flagged is
  not present because the feature isn't there yet. Spec it explicitly as "v1
  is read-only" if that's the durable decision.
- Expiry uses **JWT `exp` claim**, not `last_refresh`. Diverges from the
  Claude approach. Defensible because Codex `auth.json` doesn't carry a
  top-level `expiresAt`. `lastRefresh` is parsed but currently unused by
  `loadUsable`.
- `accountID` is parsed and wired through to `OpenAIClient` for the
  `ChatGPT-Account-Id` header (per OpenAIClient diff). Workspace switching UX
  is implicit: whichever account the CLI is signed into wins.

## Recommended sequencing

1. **Address Issue 0** — wire OAuth credentials into the coordinator's
   sign-in / bootstrap path so users with Claude Code authenticated can
   reach `.authenticated` without going through WebKit. This is what
   actually unblocks the field bug. Everything else below assumes users can
   sign in.
2. **Address Issue 1** (policy matcher) — code-only fix, no external data
   needed, removes a real footgun in the three-strikes safety net.
3. **Capture a real Max-at-100% response and a real Enterprise OAuth
   response** to ground Issues 3 and 5. Without these, both items are
   speculation. Until they're captured, do not modify
   `shouldPreserveClaudeLastGood` or the cents-vs-dollars divisor.
4. **Wire diagnostics consumer** (Issue 2) — needed for every subsequent
   debugging cycle.
5. **Add resolver tests** (Issue 6) and the OAuth → planLabel test (Issue 4).
6. Re-evaluate `shouldPreserveClaudeLastGood` only after Step 3.

## Reviewer caveats

A prior pass at this review flagged seven issues with confident framing,
several of which (the OAuth-denomination assumption, the "most likely
transient null mode," the exact Keychain-prompt mechanism, the body-string
disambiguation heuristic) were speculation dressed as analysis. This pass
labels them as hypotheses and adds explicit verification steps. If a finding
here is unlabeled, it is grounded in code I read in this pass. If it is
labeled **Hypothesis**, do not act on it without checking.
