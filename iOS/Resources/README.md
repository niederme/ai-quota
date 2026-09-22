# Local Firebase configuration

Place the Firebase Apple app configuration for `com.niederme.AIQuota` here as
`GoogleService-Info.plist`, in the checkout or worktree you are building.
The file is gitignored and is not carried into a fresh clone or worktree by Git.

The iOS build copies it into the app for Debug and Release when present and
removes a stale bundled copy when absent. Builds without it do not send analytics;
including it still requires the user's explicit opt-in. Use the existing AIQuota
Firebase registration, not an unrelated project's plist or the Mac Measurement
Protocol secret.

See the [anonymous usage analytics guide](../README.md#anonymous-usage-analytics)
for DebugView checks, the `ios` / `macos` event tags, and historical-reporting
limitations.
