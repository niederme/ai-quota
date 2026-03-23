# Auth Coordinator Spec

## Motivation

The current auth implementation spreads state across WebKit cookies, URLSession cookies,
Keychain, UserDefaults, and view-model booleans. Reset, sign-out, and silent re-auth race
each other because multiple call sites infer app auth state by reading WebKit directly.

The root failure: WebKit is treated as a live oracle for app state rather than as external
I/O to be read during specific, controlled transitions.

## Framing rule

WebKit is the source of session truth, but it is not the source of app state truth.

- WebKit may be read only during coordinator-owned transitions.
- The result of any WebKit read must be recorded in coordinator state before the transition
  completes.
- No other code path may read or mutate WebKit, Keychain, or URLSession auth state.

---

## Architecture

Each service gets one `AuthCoordinator` actor. One `AppResetCoordinator` actor handles
cross-service reset.

### Responsibilities

**`AuthCoordinator` (per service)**
- Owns auth intent, in-process auth state, and all WebKit/Keychain/UserDefaults interaction
  for its service.
- Is the only code that reads or clears service-specific WebKit cookies.
- Provides a narrow public API; never exposes cookies, Keychain values, WebKit handles, or
  ad hoc auth booleans.

**`QuotaViewModel`**
- Owns refresh cadence, loading UI, widgets, onboarding, and other product behavior.
- Observes coordinator state; does not probe cookies, clear cookies, or decide whether silent
  auth is allowed.
- Starts refresh only when coordinator state is `authenticated`.
- On a 401, asks the coordinator to run `revalidateSessionAfterAuthFailure()` and uses the
  returned bool to decide whether to retry.

**`AppResetCoordinator`**
- Owns cross-service reset orchestration.
- Awaits both service coordinators reaching stable signed-out state before any product state
  is cleared.

---

## Persisted state

Persist only:
- `signedOutByUser` (per service)

Do not persist as authoritative:
- `authenticated`
- Cookie-derived session mirrors
- "Logged in" booleans in Keychain or UserDefaults

---

## Auth states

| State | Meaning |
|---|---|
| `unknown` | Process has not yet completed bootstrap evaluation. Startup-only; never re-entered. |
| `restoringSession` | Bootstrap probe is currently running. |
| `authenticated` | A coordinator transition confirmed a valid WebKit-backed session. |
| `unauthenticated` | Probe or revalidation found no usable session; user may sign in. |
| `signedOutByUser` | Explicit user intent blocks silent re-auth until a new explicit sign-in. |
| `signingIn` | Interactive login flow is in progress. |
| `signingOut` | Teardown is in progress following an explicit sign-out. |
| `resetting` | Teardown is in progress following a reset request. |

---

## Legal transitions

Any transition not listed here is illegal.

| From | To | Trigger | Notes |
|---|---|---|---|
| `unknown` | `restoringSession` | bootstrap starts | Only at process start when persisted `signedOutByUser` is absent |
| `restoringSession` | `authenticated` | probe found valid session | Probe reads WebKit once, records result |
| `restoringSession` | `unauthenticated` | probe found no session | Normal cold-start unauthenticated result |
| `restoringSession` | `unauthenticated` | probe timed out or failed | Pessimistic resolution |
| `unauthenticated` | `signingIn` | `signIn()` | Legal |
| `signedOutByUser` | `signingIn` | `signIn()` | Only legal exit from `signedOutByUser` |
| `signingIn` | `authenticated` | login succeeded | Also clears persisted `signedOutByUser` |
| `signingIn` | `unauthenticated` | login failed or user cancelled | No silent fallback |
| `authenticated` | `signingOut` | `signOut()` | Legal |
| `signingOut` | `signedOutByUser` | teardown verified | Intended success path |
| `authenticated` | `unauthenticated` | `revalidateSessionAfterAuthFailure()` found no valid session, or timed out | Coordinator publishes `unauthenticated` before returning `false` |
| `authenticated` | `resetting` | `reset()` | Legal |
| `unauthenticated` | `resetting` | `reset()` | Legal |
| `signedOutByUser` | `resetting` | `reset()` | Legal |
| `signingOut` | `signedOutByUser` | teardown timed out | Warning path, not undefined state |
| `resetting` | `signedOutByUser` | teardown verified | Intended success path |
| `resetting` | `signedOutByUser` | teardown timed out | Warning path, not undefined state |

### Edge rules

- `signIn()` from `authenticated`: throws typed `invalidTransition`; not a re-login path.
- `signOut()` from `unauthenticated`: explicit no-op.
- `signOut()` from `signedOutByUser`: explicit no-op.
- `reset()` called during `signingIn` or `signingOut`: waits for the in-flight transition to
  settle, then runs.
- `reset()` called during `resetting`: waits for the in-flight reset to finish.

---

## Public API

```
var state: AuthState { get }
func signIn() async throws
func signOut() async
func revalidateSessionAfterAuthFailure() async -> Bool
func reset() async
```

### Illegal transition handling

| Method | Illegal-state behavior |
|---|---|
| `signIn()` | Throws `invalidTransition` from any state other than `unauthenticated` or `signedOutByUser` |
| `signOut()` | No-op from `unauthenticated` and `signedOutByUser`; throws `invalidTransition` from transient states |
| `revalidateSessionAfterAuthFailure()` | Returns `false` from any non-`authenticated` state; no transition |
| `reset()` | Never throws; waits for any in-flight transition, then proceeds |

---

## Transition behavior

### Bootstrap

**Launch rule:** if persisted `signedOutByUser` exists, coordinator starts there immediately
and skips bootstrap probing. Otherwise:

1. Publish `restoringSession`.
2. Perform exactly one bounded WebKit probe.
3. If probe confirms a valid session, publish `authenticated`.
4. If probe finds no session, publish `unauthenticated`.
5. If probe times out or errors, publish `unauthenticated` (pessimistic resolution).

Notes:
- No refresh may begin while state is `unknown` or `restoringSession`.
- No `authenticated` mirror is persisted from this result.

---

### `signIn()`

Legal from: `unauthenticated`, `signedOutByUser`

1. Publish `signingIn`.
2. If stale WebKit cookies need to be cleared before the interactive flow, that cleanup
   happens here, inside this transition.
3. Run the interactive login flow (WKWebView login window).
4. Read required WebKit session artifacts exactly once as part of this transition.
5. If session is valid, clear persisted `signedOutByUser`, record artifacts in coordinator
   memory, and publish `authenticated`.
6. If user cancels or login fails, publish `unauthenticated`.

---

### `signOut()`

Legal from: `authenticated`
No-op from: `unauthenticated`, `signedOutByUser`

1. Publish `signingOut`.
2. Persist `signedOutByUser` immediately — this is the primary guard; it takes effect before
   any async teardown begins.
3. Clear in-memory auth state and relevant URLSession state.
4. Clear service-specific WebKit cookies/data.
5. Re-read WebKit and verify auth artifacts are gone.
6. On success, publish `signedOutByUser`.
7. On verification timeout, still publish `signedOutByUser` and record a warning.

---

### `revalidateSessionAfterAuthFailure()`

Legal from: `authenticated`

1. Confirm current state is `authenticated`; otherwise return `false` immediately.
2. Perform one bounded WebKit revalidation probe.
3. If probe confirms a valid session, refresh coordinator-owned in-memory auth context as
   needed, remain in `authenticated`, and return `true`.
4. If probe finds no session, publish `unauthenticated` and return `false`.
5. If probe times out or errors, publish `unauthenticated` and return `false`.

Notes:
- This is the only "silent recovery after 401" path.
- The ViewModel receives only a retry decision, not raw auth details.

---

### `reset()`

Legal from: `authenticated`, `unauthenticated`, `signedOutByUser`
Concurrency: if `signingIn`, `signingOut`, or `resetting` is in progress, waits for that
transition to settle before proceeding.

1. Publish `resetting`.
2. Persist `signedOutByUser` immediately.
3. Clear coordinator-owned in-memory auth state.
4. Clear service-specific URLSession cookies/storage.
5. Clear service-specific WebKit cookies/storage.
6. Re-read WebKit and verify relevant auth artifacts are absent.
7. On success, publish `signedOutByUser`.
8. On verification timeout, still publish `signedOutByUser` and record a warning.

**Reset failure semantics:** verification timeout does not leave the coordinator in limbo.
`signedOutByUser` has already been persisted, so silent re-auth remains blocked on the next
launch regardless of whether WebKit cleanup could be fully verified.

---

## App-level reset

`AppResetCoordinator` is a separate actor called by `QuotaViewModel`.

1. Stop the ViewModel refresh loop, cancel any in-flight refresh work, and await actual
   completion of those tasks — not just cancellation requests — before proceeding.
2. Request `reset()` on both service coordinators concurrently.
3. Await both to reach terminal stable state (`signedOutByUser`).
4. Collect any warnings (e.g. teardown verification timeouts).
5. Only after both auth resets complete: clear product-level cached usage, settings,
   onboarding flags, and related UI state.
6. Notify `QuotaViewModel` that reset is complete.
7. `QuotaViewModel` presents onboarding / signed-out UI.

Auth reset and product reset are sequenced, not interleaved.

---

## Client auth context boundary

`ClaudeClient` and `OpenAIClient`:
- Do not read WebKit directly.
- Do not manipulate `HTTPCookieStorage.shared` directly.
- Do not infer auth state.
- Do not manage their own auth recovery logic.
- Consume session artifacts provided by coordinator-owned state established during
  transitions.

Specific implications:
- `ClaudeClient` does not discover `lastActiveOrg` from cookies at fetch time. The `orgId`
  and any other required request context is captured by the coordinator during bootstrap,
  sign-in, or revalidation.
- `OpenAIClient` receives a coordinator-provided auth context or token. On an auth failure,
  it reports the error and the caller asks the coordinator to run
  `revalidateSessionAfterAuthFailure()`.

Deferred to implementation: the exact shape of the coordinator-to-client interface (value-type
request context, auth provider protocol, or coordinator-owned transport).

---

## UI / presentation notes

- During `restoringSession`, show a short-lived, clearly transitional restoring state in the
  popover auth area — not a full-app spinner.
- Cached usage from `SharedDefaults` may still render during `restoringSession`.
- Empty gauges are acceptable if no cached usage exists; this state is brief.
- No refresh starts until coordinator publishes `authenticated`.
- No auth UI claims the user is signed in before bootstrap resolves.
- After an explicit sign-out or reset, do not show `restoringSession`; go directly to
  signed-out UI because user intent is already known.

---

## Deferred

- State observation mechanism: choice between `AsyncStream`, an `@MainActor`-isolated
  observable wrapper, or another publishing mechanism is deferred to implementation.
- Exact coordinator-to-client interface shape is deferred to implementation.
- Concrete bootstrap and teardown verification timeout values are deferred to implementation.
