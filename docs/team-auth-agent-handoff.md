# AIQuota Team Auth Field-Retest Handoff

Continue from the dedicated remote branch:

```sh
git fetch origin
git switch --track origin/team-auth-field-retest
```

- Branch: `team-auth-field-retest`
- Starting commit: `bd7b2d17db4aeea4405523c1f60658561a8e3b51`
- Detailed context: `docs/team-auth-field-test-handoff.md`
- Status: waiting for Jason's Team-account retest
- Do not merge into `main` until the field results are understood

## Previous Field Results

Jason's Claude and Codex Team-account test showed:

- Claude fell through to AIQuota's embedded WebKit login.
- Anthropic Google login failed with a generic login error.
- Claude remained disconnected.
- Codex appeared signed in but remained on a spinner.
- A separate Codex usage probe returned HTTP 401.

Khoi's individual Claude Max account also failed through the embedded login.

## Changes On This Branch

### Claude Team / Max Connect

Explicit Claude `Connect` now reads Claude Code's existing Keychain credential
through Security.framework.

Expected behavior:

1. The user signs into Claude Code.
2. The user presses Claude `Connect` in AIQuota.
3. macOS may show an AIQuota Keychain approval prompt.
4. After approval, the embedded Claude web login should not open.
5. Claude Team usage should load.

Launch and background refresh remain non-interactive.

### Codex Team Spinner / 401

When Codex CLI credentials omit a top-level Team workspace ID, AIQuota now
derives `chatgpt_account_id` from ID-token or access-token claims.

Expected behavior: AIQuota sends `ChatGPT-Account-Id`, and Codex Team usage
replaces the persistent spinner.

## Verification Completed

Passed:

- `swift test --filter ClaudeOAuthCredentialsStoreTests` - 6 tests
- `swift test --filter CodexOAuthCredentialsStoreTests` - 4 tests
- Debug macOS Xcode build
- `git diff --check`

Known pre-existing failure:

- `swift test --filter ClaudeAuthCoordinatorTests`
- Failing test:
  `bootstrap falls back to shared auth context when probe misses the live session`

## Next Steps

1. Read `docs/team-auth-field-test-handoff.md`.
2. Review the branch independently.
3. Wait for Jason's retest or reproduce with another Team account.
4. If Claude still opens WebKit, inspect the Security.framework status and
   Claude Code Keychain item shape.
5. If Codex still returns HTTP 401, verify the parsed workspace account ID and
   outgoing `ChatGPT-Account-Id` header without logging tokens.
6. Enterprise spend-limit behavior still requires a real Enterprise-account
   test.
7. Merge only after the field results are understood.
