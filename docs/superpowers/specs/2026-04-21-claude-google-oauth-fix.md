# Claude Google OAuth Fix

**Date:** 2026-04-21  
**Status:** Spec / needs decision

---

## Root Cause

When the user clicks "Continue with Google" inside `CoordLoginWindowController`'s WKWebView, Google detects that the OAuth flow is running in an embedded user-agent and blocks the login with "This browser or app may not be secure" / `disallowed_useragent`.

Google's current guidance is broader than "bad User-Agent string": embedded WebViews, including `WKWebView` on iOS and macOS, do not comply with Google's secure-browser policy for OAuth. User-Agent is one likely signal, but it should not be treated as the whole enforcement mechanism.

The default WKWebView user agent looks like:
```
Mozilla/5.0 (Macintosh; ...) AppleWebKit/605.1.15 (KHTML, like Gecko) AIQuota/1.0.0 Safari/605.1.15
```
The app name (`AIQuota/1.0.0`) and absent `Version/X.Y` segment are visible embedded-WebView tells, but Google may also use request metadata, browser capability checks, policy state, account type, and risk signals.

---

## Why ASWebAuthenticationSession Doesn't Fit Here

`ASWebAuthenticationSession` is designed for OAuth redirect flows — on macOS it opens the user's default browser when supported, or Safari otherwise, the user authenticates, and a custom URL scheme (e.g. `aiquota://callback`) brings them back. We have `aiquota://` registered already, but **claude.ai never redirects to it** — after login, it just lands on `https://claude.ai/` and sets cookies.

The deeper problem: `ASWebAuthenticationSession` runs outside our app's `WKWebView` process. The cookies end up in the browser/authentication-session storage, not in our app's `WKWebsiteDataStore` or `HTTPCookieStorage`. Our entire post-login mechanism — `CoordCookieObserver`, the poll timer, `tryAPIorgDetection` JS fetch — would need to be rearchitected around a store we can't read.

---

## Option A — User-Agent Override Experiment

Set a clean Safari-like user agent on the WKWebView before loading the login page. This removes one obvious embedded-WebView signal while preserving the existing cookie capture, org detection, and persistence flow.

This is the smallest experiment, but it is not a durable standards-compliant OAuth fix. Google explicitly says browsers must not use another browser's User-Agent on `accounts.google.com`, and `WKWebView` itself is listed as unsupported for OAuth. Treat this as a tactical test, not the final corporate-auth architecture.

**One change, one line, in `CoordLoginWindowController.show()`:**

```swift
// after: let webView = WKWebView(...)
webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
```

**File:** `Packages/AIQuotaKit/Sources/AIQuotaKit/Auth/ClaudeAuthCoordinator.swift`  
**Location:** `CoordLoginWindowController.show()`, after the WKWebView init (currently line 405)

### Result

Tested on branch `codex/test-corporate-oauth-ua` with version `1.9.15` build `371`.

Outcome: **failed for the affected corporate Claude Google account.**

The flow did not show Google's classic "This browser or app may not be secure" block. It reached the Google account prompt, then returned to Claude with:

> There was an error logging you in. If the problem persists contact support for assistance.

Interpretation: the UA override may bypass the first visible Google embedded-browser warning, but it does not make the full Claude corporate Google sign-in succeed. The remaining failure is likely in Claude's OAuth/session handoff, cookie/state handling, or corporate-account policy. Do not ship Option A as the fix.

### Acceptance criteria

- Claude login with a personal Google account still works.
- Claude login with the affected corporate Google account reaches Claude and sets usable `claude.ai` cookies in `WKWebsiteDataStore.default()`.
- The app captures `lastActiveOrg` or successfully completes `tryAPIorgDetection`.
- Refresh after restart still reads the saved Claude context and fetches usage.
- Failure mode is understandable to the user if Google still blocks the flow.

### Test matrix

| Account / Flow | Expected |
|---|---|
| Personal Claude password login | Still works |
| Personal Claude Google login | Works or fails with clear error |
| Corporate Claude Google login | Primary target |
| Corporate Claude SSO other than Google | Unknown / likely separate issue |
| Corporate Codex Google login | Separate but related issue |

---

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Google/Claude blocks or fails despite UA override | Confirmed | Move to external-browser/session-import design |
| Google changes enforcement or account risk scoring | Medium | Do not rely on UA override as the only path |
| UA spoofing conflicts with Google's policy | High | Keep this out of long-term architecture; document as tactical only |
| claude.ai serves different content to spoofed UA | Low | Same WebKit engine, same cookies; verify login and usage refresh |
| UA string goes stale | Medium | Prefer generating or centralizing the UA if this ships; update when Safari/WebKit changes |

---

## Option B — External Browser + Manual Session Import

Use the system browser for the corporate login, then give the user a guided way to bring the resulting session into AIQuota.

Potential approaches:

1. Open Claude in the default browser and ask the user to complete login there.
2. Provide a "Paste session export" or "Import from browser" path that stores only the minimum cookies AIQuota needs (`lastActiveOrg`, `sessionKey`, `routingHint`, plus any required Claude session cookies).
3. Persist through the existing `SharedAuthContextStore.saveClaude(orgId:cookies:)` path so refresh and widgets keep working.

This is less elegant than the embedded login window, but it aligns with Google's secure-browser expectation and avoids fighting WebView detection.

Open questions:

- Can we build a user-safe cookie import UX without asking users to handle sensitive values in a scary way?
- Which Claude cookies are truly required for corporate accounts?
- Does Claude bind sessions to browser/device signals that would make copied cookies fail?
- Would a browser extension companion be a cleaner bridge for exporting the needed Claude session context?

---

## Option C — Proper OAuth Redirect

This would require Claude to provide a redirect-based OAuth flow we can own or integrate with. Today, `claude.ai/login` is a website login that lands on `https://claude.ai/`, not an app callback. Unless Anthropic exposes a supported app-auth flow for this use case, this is not currently implementable inside AIQuota.

---

## What It Doesn't Fix

- Claude Team accounts that use **SSO other than Google** (Okta, SAML, etc.) — those may have their own WKWebView restrictions.
- Corporate Codex / ChatGPT auth. `CodexLoginWindowController` also uses WKWebView and may hit the same class of Google Workspace or SSO restrictions.
- Any policy that forbids copying browser sessions into a different app context.

---

## Recommendation

Option A has now been tested against an affected corporate Claude Google account and should be considered failed for this problem. Keep the branch only as evidence; do not merge it as a product fix.

For a durable fix, design Option B: an external-browser login flow plus a careful session-import path, with clear user copy and minimal cookie persistence. The spec should expand that path before this is considered ready.

Recommended next steps:

1. Stop layering WebView bypasses for Claude corporate Google login.
2. Start the external-browser/session-import design.
3. In parallel, reproduce the corporate Codex failure and confirm whether it is the same WebView/OAuth class of problem or a separate ChatGPT/Workspace policy.

---

## References

- Google OAuth installed-app docs: `disallowed_useragent` occurs when the authorization endpoint is displayed inside an embedded user-agent; iOS/macOS developers using `WKWebView` should use supported browser/app-auth flows instead.
- Google embedded-webview OAuth policy: `WKWebView` and `UIWebView` do not comply with Google's secure-browser policy for OAuth.
- Google secure-browser guidance: browsers connecting to `accounts.google.com` must identify themselves clearly and must not use another browser's User-Agent string.
