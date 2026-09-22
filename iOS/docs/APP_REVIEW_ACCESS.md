# App Review access

Provide both live test-account access and the optional built-in demo. Enter actual credentials and unused Google backup codes only in App Store Connect's private review information. Do not commit credentials or codes here.

## Suggested reviewer instructions

AIQuota can be explored without signing in: choose **Try demo** on the welcome screen, or **Settings → Demo → Try demo**. The dashboard shows labeled sample Codex and Claude usage, Codex history, and provider details. Widgets also show labeled sample data while demo is enabled. Settings → Guided Setup also works in demo mode with temporary progress, sample accounts, and a Return to demo completion action. Demo notification and refresh controls are temporary and do not send alerts or change live preferences. Choose **Exit demo** to use real accounts. Existing connections and cached usage are preserved. With no live account, Exit demo returns to the existing onboarding flow. Connect at least one service to finish setup; the dashboard only shows connected services.

For live sign-in, use the dedicated provider test accounts supplied in the private review information. Provider verification emails arrive in the supplied dedicated Gmail inbox:

1. Sign into Gmail using the supplied test mailbox username and password.
2. At Google's verification step, choose **Try another way → Enter one of your 8-digit backup codes** and use an unused code from the private review notes.
3. Sign into Codex or Claude from AIQuota. Retrieve the fresh provider email code from Gmail and enter it on the provider's sign-in page. Claude may send a login link; opening it on another device displays the verification code.
4. Complete the provider authorization flow and return to AIQuota. The Google backup code is only for Gmail login; it is not the provider email code or AIQuota's Codex device-authorization code.

Before submission, verify the whole live flow in a fresh browser session, including what quota data these free accounts expose. Each Google backup code works once. Generating a new set invalidates the previous set, so keep the review notes synchronized and provide enough unused codes for retries.

## Status and limits

The demo supplements live access. No App Review submission or approval is implied by this document. If relying on demo mode instead of live account access, obtain Apple's prior approval under guideline 2.1(a).

- [Google backup-code instructions](https://support.google.com/accounts/answer/1187538)
- [Apple App Review guidelines](https://developer.apple.com/app-store/review/guidelines/#app-completeness)
