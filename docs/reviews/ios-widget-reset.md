# iOS widget integration

Branch: codex/ios-widget-reset, based on main c389e62. No Mac, website, account-storage, provider-fetch, notification, version, or paused service-detail redesign changes.

## Implemented

Service details Lock Screen widget keeps the approved 60-point gauge, uniform 14-point standard system typography, 2-point gap and 1-point third-row baseline adjustment. Exactly one fresh account-reported quota window with a finite future reset shows Mon–Sun plus local 12-hour time. Dual quotas show both quota rows and no reset. Missing/passed/stale/reconnect evidence omits reset. Full local date/time is spoken by VoiceOver; quota content remains available when reset is omitted. The established timeline schedules reset/30-minute freshness boundaries and requests refresh after five minutes. No sample data is added to production sources or account stores.

All Home layouts anchor content at the approved 20-point frame inset (~16-point painted-ring gap), independent of provider/quota-row count. Gauge footprint is 90 points across Home layouts; ring stroke/inset ratios are preserved. Bottom padding is 4 points so full rows also fit a 158-point small widget. Large keeps its header at normal 15/11-point fixed sizes, matching the other fixed-size widget text and preventing Accessibility3 header growth from displacing rows. Tests verify painted-ring placement across providers and quota shapes. Large's ring follows its existing header; the header/content relationship is fixed and independent of metadata height.

Existing registered widgets remain: single-service small/medium (select Codex or Claude), combined medium/large, and Service details Lock Screen rectangular (select Codex or Claude). No new widget kinds or temporary schemes are added.

## Validation

Nine iOS widget XCTest cases pass. The real production-view matrix covers both services, single/dual windows, missing/loading/stale/reconnect, light/dark, Accessibility3, small 158/170, single medium, combined medium and combined large. Full metadata includes plan, balance, spent/credits and both reset rows. Pixel checks guard ring placement. All 10,080 English weekday/time combinations fit the 98-point Lock Screen text column at 14 points.

All 59 MobileAccessCore tests pass, including real provider decoders and freshness boundaries. Signed AIQuota-iOS Debug app/widget build succeeds. Application ID remains com.niederme.AIQuota with the existing team, app-group and keychain groups; no entitlement/store migration changes.

Native production review is saved as Library libfile_b5ab075069b481918d71c5c8a094b0cb, exported from XCTest renders separately from the historical approved exploration (libfile_2f2987ebcf508191a4ebb7486167ccf9, version 4). Test values are decoder-backed regression fixtures, never substituted into the real widget on-device.

## Device and cleanup status

Authorized device identity confirmed: paired iPhone Air on iOS 27.0.1. Initial installation attempts failed while its wireless connection was unavailable. After the user unlocked it, the final production Debug build installed successfully in place. Live Lock Screen verification is recorded below; remaining Home/gallery checks and phone fixture cleanup are pending.

Only com.niederme.reset-exploration will be uninstalled after verification. It is an isolated fixture-only app with no production app groups/account code. Historical test project/schemes, preview source/assets and scratch runtime were moved to the recoverable /tmp/aiquota-reset-exploration-archive-20261006 archive. The fixture app was removed from the simulator only. Useful regression tests and Library reference/review evidence remain. The active production project contains no ResetExploration target or scheme. No production app/data deletion, merge, TestFlight upload or release is authorized by this work.

## Reviewing the real widget once installed

For one provider: long-press an AIQuota Home widget → Edit Widget → Service → Claude (or Codex). For medium size, add the one-service AIQuota widget in its medium gallery size. For large, add the combined AIQuota widget in its large gallery size (both services by design).

For Lock Screen: customize the Lock Screen, add AIQuota → Service details, then tap its placed widget and choose Service → Claude or Codex. A temporary Reset Exploration widget cannot be changed into the production widget; replace that gallery entry with AIQuota's Service details.

## Follow-up: every Lock Screen registration and physical installation

The four registrations are AI allowance (circular CodexDial), Codex and Claude
(rectangular pair of CodexDials), Allowance details (CompactQuotaView for both
services, ServiceDetailsView for one), and Service details (ServiceDetailsView).
The gauge-only variants have no extra quota/reset labels to restyle.

The combined Allowance details screenshot exposed an untouched 28-point mini-ring
above 18-point rounded text. Corrected to 32-point ring frames and uniform 12-point
standard system text, preserving complete provider names at 160×72 points. A trial
36-point ring truncated Claude and was rejected. A single window uses a local
three-letter day and unambiguous 24-hour time (e.g. Mon 20:00) to fit its narrow
column; dual windows retain both quota rows without reset. Single-service selection
uses the approved 60-point ring and 14-point Service details layout.

Home vertical dividers now have 16-point bottom padding plus the existing 4-point
container clearance, for 20-point bottom inset. Single medium previously had only
4 points; combined medium previously used 8 points at each end (28 top/12 bottom).
Both now begin at the 20-point content inset, preserving ring anchors. Large column
dividers also receive 16-point bottom padding; header spacing remains unchanged.

Ten widget tests pass after the follow-up, including combined native light/dark
renders. Signed build succeeded and was installed in place on Karin Air. The
installed bundle is com.niederme.AIQuota, local main-based Debug version 0.1.0 build
46; this is not a TestFlight release. Device Hub's native screen capture confirms
the placed Service details widget shows the user's live Codex 30% 7d and Fri 10:11
PM reset after installation. Home/gallery/Claude selection checks are pending
because the phone locked again. No account deletion or phone fixture uninstall
command has been run.

Combined native review Library IDs:
- dual: libfile_ba210a3a1d2c8191a09071ddda47775e
- single: libfile_510a24e80d7881919ecc98aa9afff35b

Live placed Lock Screen crop Library ID: libfile_466e70d58b948191bb470ec85996d9e5.

## AM/PM correction candidate (supersedes combined 24-hour proposal)

The 24-hour combined copy above was not authorized by the approved AM/PM wording.
The source now restores the same three-letter weekday + 12-hour AM/PM string used
by Service details, and removes the separate compact time formatter. At 12 points
the widest full string exceeds the 78-point combined column. The rendered candidate
uses uniform 11-point system text for provider, quotas and reset, with 32-point ring
frames. Its hierarchy is internally consistent, but deliberately smaller than the
one-service 14-point layout because two services share one rectangle. This tradeoff
needs review; it has NOT been installed on Karin Air. Five Lock Screen tests passed.
Native candidate Library ID: libfile_fdb5963ee3ec8191b9d72f5f6a490b22.
The currently installed combined variant still uses the previous 24-hour copy.
