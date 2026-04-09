# Analytics Integration Design

**Date:** 2026-04-09
**Goal:** Wire up GA4 Measurement Protocol event sending in the macOS app, gated on the existing `analyticsEnabled` preference.

---

## Architecture

A new `AnalyticsClient` actor lives in the main app target (`AIQuota/Analytics/AnalyticsClient.swift`). It is a fire-and-forget HTTP client — no SDK, no external dependencies. All calls are gated on `analyticsEnabled`; if the flag is false or credentials are missing, calls return immediately without network activity.

Credentials (`firebase_app_id` and `api_secret`) are stored in `AIQuota/Resources/Analytics.plist`, which is gitignored. If the file is absent from the bundle (e.g., open-source builds), all analytics calls become silent no-ops.

A per-install UUID (`analytics.instanceId`) is generated on first launch and persisted in `UserDefaults.standard`. This is the `app_instance_id` GA4 requires to correlate events to an install.

---

## Endpoint

GA4 Measurement Protocol for app streams:

```
POST https://www.google-analytics.com/mp/collect
  ?firebase_app_id={FIREBASE_APP_ID}
  &api_secret={API_SECRET}
```

Body (JSON):
```json
{
  "app_instance_id": "<per-install UUID>",
  "events": [{ "name": "event_name", "params": { "key": "value" } }]
}
```

---

## Events

| Event | Fired from | Properties |
|---|---|---|
| `app_launched` | `AIQuotaApp.init()` | `app_version` (marketing version string from Bundle) |
| `onboarding_completed` | `QuotaViewModel.completeOnboarding()` | — |
| `service_connected` | `QuotaViewModel.enroll(_:)` | `service_name` ("claude" or "codex") |

These match exactly what the onboarding consent copy promised: installs, active use, app version, and setup completion.

---

## Components

### `Analytics.plist` (gitignored)
Keys: `FirebaseAppID` (String), `APISecret` (String).

### `AnalyticsClient` (actor)
- `static let shared` singleton
- `init()` — reads plist from bundle; sets `isConfigured = false` if missing
- `func send(_ eventName: String, params: [String: String] = [:], enabled: Bool)` — checks `isConfigured && enabled` before POSTing; errors are silently discarded
- Uses `URLSession.shared.data(for:)` (async, Task-cancellation-safe)

### Call sites
- `AIQuotaApp.init()` — `Task { await AnalyticsClient.shared.send("app_launched", ...) }`
- `QuotaViewModel.completeOnboarding()` — same pattern
- `QuotaViewModel.enroll(_:)` — same pattern, passes service name

---

## Testing

No unit tests for `AnalyticsClient` itself (it is a thin HTTP wrapper and its output is the network call). The existing `AnalyticsConsentSettingsTests` already cover the `analyticsEnabled` persistence layer. Manual validation via GA4 DebugView (`-FIRAnalyticsDebugEnabled` launch argument is not applicable here; use GA4 Realtime report instead).

---

## Security / Privacy

- `Analytics.plist` is gitignored — credentials never enter the public repo
- The API secret is readable from the app binary (unavoidable for client-side analytics); this is accepted — the secret can only send events to this GA4 property, not read from it
- No PII is collected: no user ID, no tokens, no prompt content
- All sending is gated on the user's explicit opt-in (`analyticsEnabled = false` by default)
