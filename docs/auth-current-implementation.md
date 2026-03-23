# AIQuota Auth — Current Implementation

## Storage layer

| Store | Key | What's stored |
|---|---|---|
| Keychain (data-protection) | `claudeAuthenticated` | String `"true"` — a flag, not the cookies |
| Keychain (data-protection) | `sessionToken` | Raw value of `__Secure-next-auth.session-token` cookie |
| `UserDefaults.standard` | `claude.explicitlySignedOut` | Bool — blocks silent re-auth after explicit sign-out |
| `UserDefaults.standard` | `app.installedAt.v2` | Sentinel — absent means fresh install |
| `WKWebsiteDataStore.default()` | — | Actual claude.ai session cookies (persisted by WebKit) |
| `HTTPCookieStorage.shared` | — | URLSession cookie jar; synced from WKWebView on demand |
| In-memory (`AuthManager`) | `cachedAccessToken`, `tokenExpiresAt` | Codex JWT cache |

**Key observation:** Keychain for Claude stores only a boolean flag. The actual session cookies live in `WKWebsiteDataStore.default()`.

---

## Claude auth (`ClaudeAuthManager`)

### Initialization

Keychain access is deferred by one run loop tick (so the app window appears before any OS keychain dialog). `loadAuthFromKeychain()` sets `isAuthenticated = true` if `claudeAuthenticated` exists in Keychain. No cookies are read at init.

### `signIn()`

1. Awaits `clearWKWebViewCookies()` — deletes all claude.ai cookies from `WKWebsiteDataStore.default()` and waits for completion before proceeding. This prevents the cookie observer from firing on stale cookies the moment the login window opens.
2. Opens `ClaudeLoginWindowController`, which shows an NSWindow containing a WKWebView loaded to `https://claude.ai/login`.
3. Two detection mechanisms run simultaneously:
   - **Cookie observer** (`ClaudeCookieObserver`): fires on any cookie change → checks for `lastActiveOrg`, `sessionKey`, or `routingHint` → if found, syncs all claude.ai cookies to `HTTPCookieStorage.shared` and completes.
   - **1-second polling timer**: checks JS `document.cookie` (non-HttpOnly cookies) and then the WKWebView store (HttpOnly cookies) — if login cookies found, syncs and completes.
4. On success: saves `"true"` to Keychain `claudeAuthenticated`, removes `explicitlySignedOut` flag, sets `isAuthenticated = true`, closes window.
5. On window close without completion: throws `NetworkError.notAuthenticated`.

### `silentSignInIfPossible(forceRecheck:)`

- If `explicitlySignedOut` UserDefaults flag is set → returns `false` immediately. This flag blocks silent re-auth even when `forceRecheck: true`.
- Otherwise: reads `WKWebsiteDataStore.default().httpCookieStore.getAllCookies`.
- If any login cookie found for claude.ai: copies all cookies to `HTTPCookieStorage.shared`, saves Keychain flag, removes `explicitlySignedOut`, sets `isAuthenticated = true`, returns `true`.
- Otherwise returns `false`.

### `signOut()`

1. Sets `isAuthenticated = false`.
2. Deletes Keychain `claudeAuthenticated`.
3. Sets `UserDefaults.standard["claude.explicitlySignedOut"] = true` — synchronous.
4. Clears claude.ai cookies from `HTTPCookieStorage.shared` — synchronous.
5. Fires `Task { await clearWKWebViewCookies() }` — async, not awaited (fire-and-forget).

### `syncCookies()`

Copies all claude.ai cookies from `WKWebsiteDataStore.default()` → `HTTPCookieStorage.shared`. Called at the start of every `ClaudeClient.fetchUsage()`.

### API calls

`ClaudeClient.fetchUsage()` calls `syncCookies()`, reads `lastActiveOrg` from `HTTPCookieStorage.shared` to build the URL `/api/organizations/{orgId}/usage`. Auth is entirely cookie-based — no Bearer token. 401/403 → `NetworkError.notAuthenticated`.

---

## Codex auth (`AuthManager`)

### Initialization

Deferred by one run loop tick. `clearStateIfFreshInstall()` runs first: if `app.installedAt.v2` is absent from UserDefaults, clears Keychain entries and the entire `WKWebsiteDataStore.default()`, then sets the sentinel. `loadSessionFromKeychain()` sets `isAuthenticated = true` if `sessionToken` exists.

### `signIn()`

1. Creates `LoginWindowController`.
2. `show()` immediately checks `WKWebsiteDataStore.default()` for an existing `__Secure-next-auth.session-token` — if found, completes immediately without showing any window.
3. If not found, opens NSWindow with WKWebView loaded to `https://chatgpt.com`.
4. Detection via:
   - **Cookie observer** (`CookieObserver`): fires on any change → checks for `__Secure-next-auth.session-token` → completes with token value.
   - **`WKNavigationDelegate.didFinish()`**: on each page load, checks URL and cookies. If on `/api/auth/session`, reads JWT from page body via JS. If appears logged in but no session cookie, navigates to `/api/auth/session` to extract it.
5. On success: saves token value to Keychain `sessionToken`, calls `refreshAccessToken()` to get JWT, sets `isAuthenticated = true`.

### `silentSignInIfPossible(forceRecheck:)`

Reads `WKWebsiteDataStore.default()`. If `__Secure-next-auth.session-token` found, syncs cookies to `HTTPCookieStorage.shared`, saves to Keychain, calls `refreshAccessToken()`. No `explicitlySignedOut` guard (unlike Claude).

### JWT refresh (`accessToken` / `refreshAccessToken()`)

- `accessToken` computed property checks in-memory cache; if missing or within 60s of expiry, calls `refreshAccessToken()`.
- `refreshAccessToken()`: calls `syncWebKitCookies()` first (WKWebView → HTTPCookieStorage), then GET `https://chatgpt.com/api/auth/session`, caches the returned JWT and expiry in memory.
- On 401 or empty response: deletes Keychain `sessionToken`, sets `isAuthenticated = false`.

### `signOut()`

Clears in-memory JWT cache, deletes Keychain `sessionToken`, clears chatgpt.com/openai.com cookies from both `WKWebsiteDataStore.default()` and `HTTPCookieStorage.shared`. No `explicitlySignedOut` flag.

---

## QuotaViewModel — auth orchestration

- Holds both auth managers, observes `$isAuthenticated` via Combine. When either transitions to `true`, starts auto-refresh if not already running.
- `signInClaude()`: calls `silentSignInIfPossible()` first; if that returns `false`, calls `claudeAuthManager.signIn()`.
- `signIn()` (Codex): directly calls `codexAuthManager.signIn()`.
- `refreshClaude()`: on 401 → calls `silentSignInIfPossible(forceRecheck: true)` → if succeeds, retries fetch once; if fails, sets `claudeAuthManager.isAuthenticated = false`.
- `refreshCodex()`: same pattern for Codex.
- `resetToNewUser()`: calls `signOut()` + `signOutClaude()`, resets settings and onboarding flags.
