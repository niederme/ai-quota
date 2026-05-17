# Codex CLI OAuth Support Plan

## Summary

Add Codex CLI OAuth as the preferred Codex auth source. If the user already has
`codex` authenticated, AIQuota should use `~/.codex/auth.json` or
`$CODEX_HOME/auth.json` instead of requiring a separate ChatGPT WebKit login.

Keep the existing browser-backed ChatGPT login as fallback. This improves restore
reliability, avoids WebKit cookie drift, and better supports Team/Enterprise or
workspace accounts via `ChatGPT-Account-Id`.

## Target Behavior

- On app bootstrap, respect `codex.signedOutByUser`; otherwise try Codex CLI
  OAuth first, then fall back to current WebKit session restore.
- On explicit Codex connect, import usable Codex CLI OAuth credentials first; if
  unavailable, open the existing ChatGPT login window.
- On refresh, use OAuth credentials when available and fall back to the stored web
  session only when OAuth is missing or unrecoverable.
- On sign out, clear AIQuota's copied Codex auth context but preserve the user's
  `~/.codex/auth.json`.

## Key Changes

- Add a `CodexOAuthCredentialsStore` that reads `$CODEX_HOME/auth.json`, falling
  back to `~/.codex/auth.json`.
- Parse `tokens.access_token`, `tokens.refresh_token`, optional `tokens.id_token`,
  optional `tokens.account_id`, and optional `last_refresh`.
- Add a Codex OAuth usage path that calls
  `GET https://chatgpt.com/backend-api/wham/usage` with
  `Authorization: Bearer <access_token>` and `ChatGPT-Account-Id` when present.
- Extend the Codex auth/request context so `OpenAIClient` receives the access
  token, optional ChatGPT account ID, and auth source: `codexOAuth` or
  `webSession`.
- Copy the minimal OAuth context AIQuota needs into Keychain/shared context so
  widgets can refresh without reading `~/.codex` directly.
- Fix the existing web-session refresh path so it always attaches the stored
  `__Secure-next-auth.session-token` explicitly instead of depending on ambient
  URLSession cookies.

## Token Refresh Policy

- Re-read `auth.json` before each OAuth refresh attempt.
- Do not refresh or write OAuth tokens in v1. Re-read `auth.json` before OAuth
  use; if the access token is expired or rejected, fall back to WebKit auth and
  let Codex CLI remain the token writer.
- If OAuth is rejected during a refresh, disable the OAuth source for the current
  app session and retry through the existing WebKit session path.
- Do not treat `OPENAI_API_KEY` in `auth.json` as sufficient for subscription
  quota unless verified separately; this feature is for Codex CLI OAuth tokens.

## Test Plan

- Parse `auth.json` with snake_case and camelCase token keys.
- Respect `$CODEX_HOME`.
- OAuth fetch sends `ChatGPT-Account-Id` when present.
- Bootstrap prefers OAuth over WebKit when both exist.
- `signedOutByUser` blocks silent OAuth import.
- Explicit connect can import OAuth after prior sign-out.
- Web-session refresh attaches the stored session token.
- Widget refresh works from copied shared OAuth context.
- Rejected OAuth falls back cleanly and does not delete or rewrite the user's
  Codex CLI auth file.

## Assumptions

- AIQuota remains simple: no source picker in v1.
- Browser ChatGPT login remains supported.
- AIQuota does not write to `auth.json` in v1. Codex CLI remains the active
  writer for CLI OAuth credentials.
- The Codex CLI OAuth path is less policy-fragile than Claude OAuth because it
  targets OpenAI/Codex quota data and mirrors the Codex CLI credential model.
