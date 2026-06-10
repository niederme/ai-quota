# Handoff: Team Auth Field Test Continuation

Last updated: June 10, 2026

## Read This First

The latest Jason retest code is preserved on a dedicated branch:

- Checkout: `/Users/niederme/~Repos/ai-quota`
- Branch: `team-auth-field-retest`
- Base commit: `4ec4724`
- Remote branch: `origin/team-auth-field-retest`

A new clone or agent should check out `origin/team-auth-field-retest`. The
changes are intentionally not merged into `main` while Jason's field validation
is pending.

Source and test patch:

```text
Packages/AIQuotaKit/Sources/AIQuotaKit/Auth/ClaudeAuthCoordinator.swift
Packages/AIQuotaKit/Sources/AIQuotaKit/Auth/ClaudeOAuthCredentialsStore.swift
Packages/AIQuotaKit/Sources/AIQuotaKit/Auth/CodexOAuthCredentialsStore.swift
Packages/AIQuotaKit/Tests/AIQuotaKitTests/ClaudeOAuthCredentialsStoreTests.swift
Packages/AIQuotaKit/Tests/AIQuotaKitTests/CodexOAuthCredentialsStoreTests.swift
```

Related documentation updates:

```text
README.md
docs/auth-coordinator-spec.md
docs/auth-current-implementation.md
docs/claude-enterprise-main-review.md
docs/claude-enterprise-support-plan.md
docs/codex-cli-oauth-support-plan.md
docs/jason-team-plan-test-instructions.md
docs/team-auth-field-test-handoff.md
```

A fresh agent running in this workspace can continue directly from the checkout
above. In another clone or worktree:

```sh
git fetch origin
git switch --track origin/team-auth-field-retest
```

## Current Field Status

The latest patch is waiting on Jason's Team-plan retest.

Earlier Team-plan test results from Jason:

- Claude opened AIQuota's embedded WebKit login.
- Anthropic's Google login failed with a generic "There was an error logging
  you in" response.
- Claude remained disconnected.
- Codex appeared signed in but remained on a spinner and showed "Unexpected
  response format from server."
- A separate Codex response probe returned HTTP 401.

Related reports:

- Khoi's individual Max account also failed to connect through the embedded
  Claude login.
- The repo owner's Pro account works, but an earlier fresh archive also opened
  the embedded Claude login despite Claude Code already being authenticated.

These reports indicate that the embedded Claude login is not a reliable Team /
Max recovery path. They do **not** yet prove that Claude Team usage parsing or
Enterprise spend-limit parsing is wrong, because those accounts did not reach a
successful usage fetch.

## Latest Retest Patch

### Claude Team / Max Connect

Previous explicit `Connect` behavior asked `ClaudeAuthCoordinator` to discover
Claude Code credentials through `/usr/bin/security` with a short timeout. On a
machine where the Claude Code Keychain item requires approval, that lookup can
time out or fail before the user can authorize it. AIQuota then silently falls
through to the embedded WebKit login.

The latest patch:

- Adds a direct Security.framework Keychain reader for the Claude Code service
  `Claude Code-credentials`.
- Performs a non-interactive metadata query first and selects the newest
  matching item.
- Allows the actual credential read to display macOS's Keychain approval UI,
  but only after the user explicitly presses `Connect`.
- Keeps bootstrap and background refresh non-interactive.
- Changes `ClaudeAuthCoordinator` explicit Connect from
  `.claudeCodeSecurityCLI` to `.claudeCodeInteractive`.

Expected retest behavior:

1. Jason signs into Claude Code with the Team account.
2. Jason presses Claude `Connect` in AIQuota.
3. macOS may show one AIQuota Keychain approval prompt.
4. After approval, AIQuota should connect without opening the embedded Claude
   web login.
5. Claude Team usage should load.

### Codex Team Spinner / 401

Some Codex CLI Team credentials omit the workspace account ID at the top level
of `auth.json`. AIQuota was then sending usage requests without the required
`ChatGPT-Account-Id` header, which can produce a 401 even though the token is
valid and the UI considers Codex signed in.

The latest patch:

- Preserves explicit top-level account ID precedence.
- Falls back to `chatgpt_account_id` in the ID-token claims.
- Then falls back to the access-token claims.
- Supports both a direct `chatgpt_account_id` claim and nested
  `https://api.openai.com/auth` claims.

Expected retest behavior: Codex Team usage replaces the persistent spinner.

## Verification Already Run

Passed:

```text
swift test --filter ClaudeOAuthCredentialsStoreTests
swift test --filter CodexOAuthCredentialsStoreTests
xcodebuild -project AIQuota.xcodeproj -scheme AIQuota -configuration Debug -destination 'platform=macOS' build
git diff --check
```

Known unrelated failure:

```text
swift test --filter ClaudeAuthCoordinatorTests
```

The existing failing test is:

```text
bootstrap falls back to shared auth context when probe misses the live session
```

Do not attribute that pre-existing failure to the latest Jason patch without
reproducing and tracing it.

## Retest Package

A Release build `1.9.17 (372)` was packaged with
`docs/jason-team-plan-test-instructions.md`. It is a universal
Intel / Apple Silicon build signed with an Apple Development certificate, not a
notarized distribution build.

The intended package name is:

```text
AIQuota-Jason-Team-Test-2026-06-08.zip
```

If rebuilding the package, build from `team-auth-field-retest` so the latest
patch is included.

## Decisions and Boundaries

- Reuse existing Claude Code / Codex CLI credentials before hosting a separate
  web login.
- Do not access Claude Code Keychain credentials interactively during launch or
  background refresh.
- An explicit Claude `Connect` action may show a Keychain approval prompt.
- Claude OAuth credentials remain file-first; the coordinator's in-memory
  credential cache handles a Keychain-derived credential during the process.
- Do not mix OAuth and web fields in one Claude usage snapshot.
- API-only Claude accounts are not the target of this quota feature.
- Enterprise spend-limit behavior still needs a real Enterprise account test.
- Team and Enterprise support must not be described as field-verified until
  those account tests pass.

## What To Do Next

1. Continue from `team-auth-field-retest`; do not merge it into `main` before
   field results are understood.
2. Wait for Jason's latest Team retest, or reproduce with another Team account.
3. Record separately whether:
   - a Keychain prompt appears after Claude `Connect`;
   - the embedded Claude login opens;
   - Claude Team usage loads;
   - Codex Team usage replaces the spinner;
   - exact banners or HTTP statuses remain.
4. If Claude still falls through to WebKit, inspect the Security.framework
   status and Claude Code Keychain item shape before changing usage parsing.
5. If Codex still returns 401, capture whether the parsed account ID is present
   and whether `ChatGPT-Account-Id` is sent, without logging tokens.
6. Once the field result is understood, revise with a focused regression test
   if needed, then merge the branch only after review.

## Related Docs

- [`jason-team-plan-test-instructions.md`](jason-team-plan-test-instructions.md)
- [`claude-enterprise-main-review.md`](claude-enterprise-main-review.md)
- [`claude-enterprise-support-plan.md`](claude-enterprise-support-plan.md)
- [`codex-cli-oauth-support-plan.md`](codex-cli-oauth-support-plan.md)
- [`auth-coordinator-spec.md`](auth-coordinator-spec.md)
