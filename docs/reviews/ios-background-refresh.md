# iOS opportunistic refresh and saved readings

The app registers com.niederme.AIQuota.refresh at launch and schedules its own
BGAppRefreshTaskRequest when entering the background and when a task starts. The
request's earliest date is 30 minutes later; this is eligibility, not a cadence.
iOS can defer or prevent work, including after force quit, in Low Power Mode, or
when Background App Refresh is disabled. Foreground and WidgetKit fetch paths
remain active; widget timeline requests still ask for another opportunity after
five minutes, under Apple's budget. No backend or widget push is introduced.

Each background opportunity refreshes only services with existing shared Keychain
credentials, concurrently, through SharedQuotaStore.fetch. It reuses readings under
60 seconds old, retains the existing per-service lease and renewal behavior, and
honors the shared Claude five-minute 429 cooldown. Demo mode and signed-out services
do not fetch. Expiration cancels work and completes the task once with failure;
rescheduling occurs before requests so expiration cannot skip the next opportunity.
Ordinary provider failures do not prevent another service from updating. Completion
reloads widget timelines so both successful cache updates and failure states can be
shown. No fetchedAt is fabricated or changed by scheduling, failure or cache reuse.
Existing credential-free diagnostics record background scheduling/task outcomes.

Widgets now propagate temporary failures as a saved-reading state even when their
last success is less than 30 minutes old. Reconnect remains a distinct indication.
All Lock Screen gauges mute and show a clock on saved readings; both quota rows are
retained. Single-service reset estimates disappear on failure/staleness. VoiceOver
announces saved age and the need to refresh. Home gauges also show a clock and
replace the prior generic Saved reading label with Saved · 2h ago (for example).
Ring anchors, fonts and dual-window shape are preserved; missing readings remain
sign-in/unavailable states rather than invented saved usage.

Validation includes expiration cancellation, one-time completion/rescheduling,
independent failures, no-account behavior, app configuration, unchanged cooldowns,
last-success age boundaries and native fresh/stale/error/reconnect/missing renders
for single/dual accounts. These exercise lifecycle behavior, not a claim that the
simulator proves Apple's real-world scheduling frequency. John is away; delivery
is through iOS TestFlight rather than a device Debug install.
