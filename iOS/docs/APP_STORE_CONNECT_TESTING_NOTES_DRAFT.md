# AIQuota — App Store Connect testing notes (iOS / iPadOS draft)

Replace the placeholders in App Store Connect’s private review information. Keep actual passwords and backup codes out of this repository. The reviewer-facing draft begins below.

---

AIQuota displays usage allowances and reset times for OpenAI Codex and Claude, with Home Screen and Lock Screen widgets. Live usage is requested directly from each provider. Sign-in credentials are stored in this device’s Keychain and shared with the app’s widgets.

## Review accounts

Google / Gmail (for receiving provider verification emails)
- Email: [REVIEW GOOGLE EMAIL]
- Password: [REVIEW GOOGLE PASSWORD]

Codex / ChatGPT
- Email: [REVIEW CHATGPT EMAIL]
- Password: [REVIEW CHATGPT PASSWORD]

Claude
- Email: [REVIEW CLAUDE EMAIL]
- Sign in using the verification email delivered to the review Gmail inbox. A password is not required for this email sign-in flow.

## Recommended review flow: demo

1. Launch AIQuota and tap Try Demo at the bottom left of the welcome screen. If already set up, open Settings → Demo → Try demo.
2. Explore the Codex and Claude cards, provider details, and sample Codex usage history.
3. Add an AIQuota widget to the Home Screen or Lock Screen to see labeled sample usage.
4. Optionally open Settings → Guided Setup to explore onboarding. Demo notification controls are temporary and do not send notifications.
5. Tap Exit demo to test live sign-in. With no connected account, the app returns to onboarding; existing live connections are preserved.

## Live sign-in: access to verification emails

1. Open Gmail in Safari and sign in with the review Google account above. You may also use a separate browser or device to read the inbox.
2. If Google requests 2-Step Verification, choose Try another way → Enter one of your 8-digit backup codes, and use the next unused code below.
3. Keep the inbox available. OpenAI and Claude may send a new verification email during sign-in, even if an account has a password.

## Live sign-in: Codex

1. In AIQuota onboarding, tap Continue, then Sign In beside Codex. If already set up, open Settings → Accounts → Codex.
2. Tap Open security settings and sign in with the review ChatGPT account. Ensure Device Code Authorization is enabled, then return to AIQuota.
3. Tap Copy code and continue. Complete OpenAI’s sign-in flow, using the Gmail inbox for any email verification code.
4. When asked for the device authorization code, paste the code copied by AIQuota and complete authorization.
5. Return to AIQuota. After the usage check completes, continue through setup.

## Live sign-in: Claude

1. In onboarding, tap Sign In beside Claude Code, then Sign In on the account screen. If already set up, open Settings → Accounts → Claude Code.
2. Sign in with the review Claude email address. Retrieve the verification email from the supplied Gmail inbox and follow Claude’s instructions.
3. Complete authorization and copy the authorization code shown by Claude.
4. Return to AIQuota, paste that code into Authorization code, and tap Connect Claude. After the usage check completes, continue through setup.

## Expected behavior and important notes

- Live setup requires at least one connected service. The other service can be added later in Settings.
- The dashboard shows connected services. Available quota fields and history depend on the provider and account; the demo provides representative sample data for both services.
- If an update fails, the last successful reading remains visible. If sign-in must be renewed, use Reconnect.
- Widget refresh timing is controlled by iOS; updates may not appear immediately.
- Google backup codes are only for Gmail’s 2-Step Verification. Provider email verification codes, the Codex device code, and Claude’s final authorization code are separate codes.
- Each Google backup code is single-use. If one has already been used, try the next.
- Please use only the supplied review accounts.

## Google backup codes

1. [XXXX XXXX]
2. [XXXX XXXX]
3. [XXXX XXXX]
4. [XXXX XXXX]
5. [XXXX XXXX]

---

## Before pasting (not part of the reviewer notes)

- Fill the credentials and current unused backup codes in App Store Connect only.
- Verify both provider accounts’ actual authorization and quota retrieval on the submission build. Their free-account status and the working demo do not establish that live access succeeds.
- The tested free Claude account is blocked by the provider's Pro/Max requirement. Supply a verified compatible Claude review account or resolve demo-only review access with Apple before submission; a free Claude account does not complete these instructions.
- Confirm both providers’ verification emails reach the supplied Gmail inbox.
- Paste only the reviewer-facing section, from the app description through the backup codes.
