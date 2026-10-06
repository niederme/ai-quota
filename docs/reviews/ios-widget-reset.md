# iOS widget reset and layout review

Service details uses a 60-point ring frame, 14-point standard system typography,
and a local reset line such as `Fri 5:18 PM` only for fresh single-window readings.
The third row has a one-point baseline offset. Dual-window accounts retain both
quota rows and no reset. Missing, stale, reconnect, past and invalid reset evidence
omits gracefully. VoiceOver announces the full local date/time and freshness.

Allowance details uses the same view for one service. Its two-service rectangle
uses 32-point rings, uniform 11-point system text and a 2-point center gap. Every
three-letter weekday, hour, minute and AM/PM combination fits its 79-point columns
without scaling. A rejected 24-hour proposal was replaced with the approved AM/PM
convention. The circular AI allowance and gauge-only Codex and Claude registrations
retain their gauge geometry; there is no quota/reset text to restyle in those views.

Home widgets keep 90-point ring frames anchored at the selected 20-point top inset,
independent of metadata rows. Registered families are single small/medium and both
services medium/large. Large retains its header above the aligned columns. Vertical
dividers have 16-point bottom padding plus 4-point container clearance. Single
medium previously had only 4-point clearance; combined medium had 28-point top and
12-point bottom insets. The final shared content inset is 20 points at each end.

John approved the physical iPhone Air screenshots on October 5, 2026:
- libfile_8f5e7bea0e5881919d8aea4c33e026b8: Codex/Claude small and single medium.
- libfile_a61484f93bd081918d6abfbb1822c110: combined medium and large.
These show live account readings and revised dividers. They do not establish
combined Lock Screen gallery or provider-editor coverage. Earlier native capture
confirmed the placed Service details view with live Codex usage and account reset.

Review artifacts:
- live placed Lock Screen: libfile_466e70d58b948191bb470ec85996d9e5
- final combined AM/PM native render: libfile_fdb5963ee3ec8191b9d72f5f6a490b22, version 1
- production Home/Lock state matrix: libfile_b5ab075069b481918d71c5c8a094b0cb

Tests retain production-view light/dark and accessibility-size matrices, native
Home-family renders, quota shape/freshness boundaries, DST/local-time behavior and
10,080 copy-width cases. Test fixtures are confined to the test target.

The standalone fixture project, schemes, source and scratch binaries were archived
recoverably under /tmp/aiquota-reset-exploration-archive-20261006. The fixture-only
com.niederme.reset-exploration app was uninstalled from both simulator and Karin Air.
No production account or app-data deletion occurred. Useful tests remain in the
normal iOS test target; the production project has no temporary preview targets.

John authorized merge and App Store Connect upload for internal TestFlight only.
iOS version remains 0.1.0; build 50 was selected against authoritative App Store
Connect inventory. Mac release and public App Store submission remain out of scope.
