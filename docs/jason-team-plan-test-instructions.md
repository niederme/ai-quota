# Handoff: AIQuota Claude Team Plan Test

This build is testing whether AIQuota can use an existing Claude Code login before falling back to the embedded Claude web login.

## Context

AIQuota previously opened its embedded Claude login window for some users even when they were already signed in to Claude elsewhere. That path is fragile for Claude Team and Max accounts, especially when the account uses Google login or organization-managed auth.

The build under test includes the auth coordinator change from commit `520734c` or later.

## What Changed

Previous builds could fall into AIQuota's embedded Claude web login even when Claude Code was already signed in. That was a problem for Team and Max accounts because the embedded login can fail or never complete for some account types.

This build changes Claude sign-in order:

1. AIQuota first checks whether Claude is already connected from a saved AIQuota session.
2. If not, clicking `Connect` now tries the existing Claude Code OAuth login before opening the embedded web login.
3. If Claude Code credentials work, AIQuota should connect without showing the Claude web login window.
4. The app does not read Claude Code Keychain credentials during background refresh; it only tries that path from the explicit `Connect` action.

Why this should work now:

- Claude Code already supports the account login flow for Team users.
- If the Team account uses Google login, Claude Code handles that login first.
- AIQuota can reuse that existing Claude Code OAuth credential instead of asking the embedded web view to complete a separate Claude login.
- The usage refresh endpoint is account-scoped for this OAuth path, so it does not need the web session's organization cookie to load usage.

## What This Test Proves

This test is successful if AIQuota can connect Claude through Claude Code OAuth and load Team usage without requiring the embedded Claude web login.

This test does not prove Enterprise spend-limit behavior. Enterprise still needs a separate account-specific test.

## Before Testing

1. Install the test build of AIQuota.
2. Make sure Claude Code is signed in with the same Claude Team account you want AIQuota to monitor:

   ```sh
   claude
   ```

3. If the account uses Google login, complete that login through Claude Code.
4. You do not need to log out of Claude in your browser.
5. You do not need to reset AIQuota settings unless asked.

## Test Steps

1. Launch AIQuota.
2. Open the AIQuota menu bar popover.
3. Look at the Claude section.
4. If Claude usage is already visible, note that it connected on launch.
5. If Claude shows a `Connect` button, click it.
6. Watch what happens after clicking `Connect`.
7. Wait for usage to refresh, or trigger a manual refresh if the app offers one.
8. Quit AIQuota.
9. Relaunch AIQuota.
10. Check whether Claude is still connected or reconnects cleanly after pressing `Connect`.

## Expected Results

Good:

- AIQuota signs into Claude without opening the Claude web login window.
- Claude Team usage loads after refresh.
- Relaunch either stays connected or reconnects cleanly through the `Connect` button.

Acceptable:

- macOS asks once for Keychain access.
- After choosing `Allow`, AIQuota connects and usage loads.

Bad:

- Clicking `Connect` immediately opens the Claude web login window.
- AIQuota stays stuck on `Connect` or a spinner.
- Usage never loads after the app appears connected.
- Reopening AIQuota breaks Claude auth again.

## Please Report Back

Send:

- Plan type: Team.
- Whether the account uses Google login, email login, or another organization login flow.
- Whether Claude connected on launch.
- Whether clicking `Connect` opened a web login window.
- Whether a Keychain prompt appeared.
- Whether Team usage loaded after refresh.
- Whether Claude stayed connected after quit and relaunch.
- A screenshot of the Claude tile after refresh.

## Interpreting Results

If AIQuota connects without opening the embedded Claude web login, the auth handoff is working.

If a Keychain prompt appears only after pressing `Connect`, that is acceptable for this test. It means macOS required approval to let AIQuota read Claude Code's saved credential.

If the embedded Claude web login opens immediately after pressing `Connect`, AIQuota did not find or could not use Claude Code's credential. Send the result back as a failure with screenshots.
