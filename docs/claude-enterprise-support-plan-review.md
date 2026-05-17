# Review: Claude Enterprise Support Plan

Review of [`claude-enterprise-support-plan.md`](claude-enterprise-support-plan.md).

Top-line: the diagnosis is right and the scope discipline is good (no Admin API,
no PTY, no source picker). The shape of the change is sound. But there's one
major external risk it doesn't acknowledge, and a few internal gaps worth
tightening before committing.

## Major risks

### 1. The OAuth path is policy-fragile

Anthropic has been tightening the rules: their stated position is that OAuth
credentials are for Claude Code and Claude.ai specifically, and they've already
restricted third-party use of `sk-ant-oat*` tokens for the Messages API (the
Hermes / Aperant / Auto-Claude breakages over the winter).

`/api/oauth/usage` is read-only and arguably different, but it's the same
credential class, used the same way (read-from-disk), from a "third-party tool."
That is the exact pattern Anthropic has been clamping down on. The plan should:

- Acknowledge this risk explicitly (one paragraph in *Assumptions*).
- Have a *contingency*: if `/api/oauth/usage` returns 401/403 with a
  policy-flavored error, AIQuota should degrade gracefully and surface an
  explanation — not loop into the web fallback and look broken.
- Consider whether to call this out to users in onboarding ("uses your Claude
  Code session — may break if Anthropic changes policy"), since the failure
  mode hits Enterprise users hardest.

### 2. Token refresh is unaddressed

Claude Code's CLI refreshes its OAuth tokens on its own cadence. AIQuota reading
`~/.claude/.credentials.json` gets whatever was last written. If the user hasn't
run `claude` in days, the access token may be expired. The plan needs to spec
one of:

- (a) Re-read on every fetch (probably right, and is cheap).
- (b) Refresh the token itself using the stored refresh token (risky —
  duplicates Claude Code's refresh state and may race).
- (c) Detect 401 and surface "open Claude Code to refresh."

Recommended: (a) + (c).

## Internal gaps

### 3. `displayKind` needs a "none" state

The plan lists `fiveHour | sevenDay | spendLimit`. What if an Enterprise account
has only a plan label and no quantitative data, or the OAuth response shape is
something new? The enum should probably be optional or include `.unknown`, and
the popover / widget should have a defined render path for it. Otherwise the
first unexpected response shape is another emergency.

### 4. "Preserve compatibility computed properties where practical" is too vague

Looking at `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/ClaudeUsage.swift:61`,
`usedPercent`, `limitReached`, `percentFraction`, `remainingPercent`, `resetAt`,
`resetAfterSeconds`, and `planDisplayName` all assume the 5-hour window exists.
Decide upfront: do these become optional (forcing every call site to handle
nil), or do they front a `primaryMetric` abstraction (single source of truth:
utilization + reset, regardless of which window)?

The latter is cleaner and matches how the rest of the app already treats it as
a single gauge. Pick one before implementation — "where practical" will produce
a half-migrated mess.

### 5. Cache decoding is hand-waved

The current `ClaudeUsage` decodes from non-optional `fiveHourResetsAt` /
`sevenDayResetsAt`. Making them optional is a coding-key change; old cached
blobs need either:

- a versioned envelope,
- a custom `init(from:)` that tolerates absence, or
- an explicit cache-bust on upgrade.

The plan should pick one. A cache-bust is probably fine here — usage is fetched
on launch anyway.

### 6. "Treat 401/403 as auth failure only when no fallback succeeds" can hide real problems

If OAuth returns stale data because it's expired but the web cookie works,
users silently get correct data — but the day Claude Code's session also
expires, both fail simultaneously with no warning history.

Consider logging the per-source failure into a small diagnostics surface (kept
in `UserDefaults`, exposed in the popover's About / debug menu) so when users
report "AIQuota is wrong," you can see which source has been failing.

## Smaller nits

- **Extra usage vs. spend.** The plan introduces "spend / extra-usage data" as
  if they're one thing. They aren't — `extra_usage` is the Max overflow bucket
  already modeled at
  `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/ClaudeUsage.swift:40`, and an
  Enterprise spend limit is a different concept. Pick distinct names so the
  model doesn't conflate them.
- **Codex Enterprise.** The plan is Claude-only. If Codex Enterprise has the
  same null-window pathology, callers may report "you fixed Claude but Codex
  still lies." Worth a single line: "Codex Enterprise is out of scope for v1
  and tracked separately."
- **Plan label visibility.** Nothing in the plan says where the inferred plan
  label is shown. If an Enterprise user upgrades and the popover still says
  "Pro" because of the `extraUsage?.isEnabled == true ? "Max" : "Pro"` logic at
  `Packages/AIQuotaKit/Sources/AIQuotaKit/Models/ClaudeUsage.swift:84`, they
  won't trust the fix. The plan should explicitly include surfacing the real
  label.
- **Keychain access.** "Only when accessible without disruptive prompts" —
  you can't really know without trying. The condition you probably want is
  "without triggering a `kSecUseAuthenticationUI` prompt"; spec it as "use
  `errSecInteractionNotAllowed` and skip on failure" so the implementation
  doesn't accidentally re-introduce the prompt.

## What's good

- Scope discipline (no source picker, no Admin API, no PTY) is the right call.
- Auto source selection + fallback is the right UX shape.
- Test plan covers the actual regressions that would bite (5h-threshold
  notifications firing on accounts with no 5h window).
- Decoupling `ClaudeAuthCoordinator` from OAuth credentials is correct —
  they're different lifecycles.

## References

- [Anthropic third-party OAuth restriction (Hermes #15080)](https://github.com/NousResearch/hermes-agent/issues/15080)
- [Anthropic credential-use policy debate (Aperant #1871)](https://github.com/AndyMik90/Aperant/issues/1871)
- [Claude Code OAuth token expiry context](https://daveswift.com/claude-oauth-update/)
