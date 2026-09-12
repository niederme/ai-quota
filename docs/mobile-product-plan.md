# AI Quota for iPhone and iPad

> **Current status (September 12, 2026):** iOS builds are now being tested through TestFlight. Independent Codex and Claude connections, shared session renewal, and Lock Screen widgets are implemented. Earlier feasibility and authorization notes below are historical; see the [README roadmaps](../README.md#roadmaps) for current priorities. Longer-term background reliability and distribution review remain unverified.

Working product plan · September 11, 2026 · For review

## Purpose

Know how much AI allowance is available, when it resets, and what recent usage means. Lock Screen gauges and Home Screen widgets are the primary surfaces. Opening the app adds insight and context.

## Target first-release experience

This is the product direction, not the scope of the feasibility build. The first working slice is one provider, one circular Lock Screen gauge, one small Home Screen widget, and a plain adaptive overview. Add the second provider, medium comparison widget, and compact history as their gates clear. Basic adaptation to width, orientation, and text size belongs in the initial layout; bespoke large-screen presentations can follow.

### Lock Screen

One provider, one quota arc, and a recognizable service symbol. Configure each gauge for short-term or weekly usage. Tap through to the relevant detail in the app. Pedometer++ is the usability reference: recognizable and useful at a glance. It does not establish our achievable refresh behavior.

Preserve AI Quota’s existing quota-used arc meaning. Make unavailable and stale readings distinct without relying only on color. Provider marks remain a design proposal subject to appropriate usage rights.

### Home Screen

The initial slice has a small single-provider widget. The target release adds a medium widget comparing Codex and Claude after both providers clear their gates. Both include reset context and an honest indication of freshness.

### Phone reset notifications

“Let me know when I can work again” is a first-release priority, after independent access is verified. Offer an opt-in reminder for an exhausted provider window so the user can leave the computer and return when allowance is expected to reset.

Distinguish a scheduled reminder (“Your Codex five-hour allowance is scheduled to reset now”) from confirmed availability (“Codex allowance is available again”). Only a fresh successful provider reading that checks all relevant limits can support the latter. A clock crossing a reset time is not evidence of restored capacity. If the weekly allowance remains exhausted, explain that constraint instead of inviting the user back to work. Unknown weekly availability must remain unknown.

Evaluate on-device scheduled notifications first; remote push infrastructure is not part of the access probe. Request notification permission when the user enables the feature. Replace or cancel pending reminders when fresh readings change the reset, the account disconnects, or the user disables reminders. Avoid duplicate scheduled and confirmed alerts for the same reset. Tapping an alert opens the provider status and refreshes it. A missed background refresh must not silently turn a scheduled reminder into a confirmed claim.

Validate scheduling, cancellation, changed reset times, weekly-limit conflicts, denied notification permission, and stale or failed fetches before shipping. Notification delivery and background refresh behavior still require device verification; no timely-delivery promise is established by the access probe.

### App overview and adaptive layouts

Aim for a useful overview within one viewport, adapting to available width and height rather than a fixed device size.

- A sentence surfacing the most relevant insight.
- Codex and Claude gauges with short-term and weekly allowance usage.
- Reset times and last-checked information.
- Quiet refresh and settings controls.

The initial overview adapts to available width, height, orientation, and text size. The target release validates smaller and larger phones, portrait and landscape, iPad window sizes, and iPhone Duo’s open and closed layouts. Stack content in narrow spaces; place providers side by side when space allows. Larger layouts may show history alongside the overview. Preserve context as the viewport changes.

Readability and accessibility take priority over forcing everything onscreen. Permit scrolling at larger text sizes or constrained heights.

## Insight sentence

The sentence should reveal a pattern, explain pacing, or connect limits in a way that individual gauges do not. It should not merely narrate visible percentages.

Candidate insights, conditional on sufficient evidence:

- “Mondays are usually your busiest day. You have less Claude allowance left than usual.”
- “At your recent pace, your weekly allowance may run out before Thursday’s reset.”
- “Your usage is lighter than usual this week.”
- “Your five-hour window resets tonight, but your weekly allowance stays nearly exhausted until Thursday.”

These are examples, not claims about current usage. Define “busiest” in terms of observed allowance consumption, not time worked or productivity. Pace projections must be clearly conditional.

Start with deterministic calculations and sentence rules using locally stored, timestamped quota readings. Consider a local AI model later for phrasing or richer synthesis; calculations and observed evidence must determine every claim. Local-model availability and suitability have not been investigated.

Phone-only history may be sparse and biased toward times the app or widget runs; it may never justify weekday claims. Before enabling each class of personal insight, measure coverage across comparable days, reset boundaries, and allowance changes. Several weeks of readings alone are not sufficient. Treat gaps as unknown: evenly spaced samples are not essential for every insight, but missing intervals can prevent attribution to a particular day. Start with relationships between known limits and resets, adding personal patterns only when coverage supports them. Do not infer exact messages, tokens, or working hours from percentages, or directly equate percentage consumption across providers.

A short-term reset does not replenish the weekly allowance. Do not claim a fixed number of future resets unless supported by the provider’s actual window behavior. Confirm restored capacity with a fresh reading.

Tapping the sentence reveals a compact history view. If there is insufficient evidence for an insight, show a modest learning state rather than inventing a pattern.

## Feasibility gates

### 1. Establish viable provider access

Identify permitted independent mobile authentication and quota retrieval for both OpenAI and Anthropic before committing to a two-provider release. Review each provider’s terms, supported authentication options, endpoint status, and any required permission. An endpoint working in the Mac app is not evidence of permission to distribute a mobile client.

Verified in the current repository: existing provider-centered gauges, short-term and weekly quota models, configurable desktop widgets, and widget-side network fetching. The shared package declares macOS support and links AppKit; sign-in windows use NSWindow. Models, formatters, and portions of networking are reuse candidates, but the package is not ready to import into an iOS target unchanged.

Current credential and endpoint dependencies:

- Claude reads Claude Code credentials from its local file or Mac Keychain, or reuses claude.ai web-session cookies. The OAuth route calls `api.anthropic.com/api/oauth/usage`; the web route calls claude.ai usage paths.
- Codex reads `.codex/auth.json` or reuses a ChatGPT web session, then reads quota from `chatgpt.com/backend-api/wham/usage`.

An independently installed phone app cannot borrow those Mac-local credentials. Reusing the existing web-session approach would require proving both mobile compatibility and permission; it is not an established fallback. A different supported access route may be necessary.

Unverified: independent mobile sign-in, session renewal, quota retrieval with the Mac asleep, and suitability of the access methods for mobile distribution.

Anthropic’s published guidance restricts third-party Claude.ai login and session-token collection. This directly challenges reuse of the existing Claude authentication approach. A supported third-party quota-access route for either provider was not established in the initial review. This gate may decide whether the proposed product is viable.

The authentication concern also applies to the same methods in the Mac code; it is not created by iOS. Provider-access follow-up is tracked separately from this mobile plan. This mobile plan does not authorize Mac implementation changes.

**Alternative to evaluate, not an approved fallback:** a Mac could relay timestamped quota readings to the phone through a sync service, without transferring provider credentials. CloudKit is one candidate whose delivery behavior has not been investigated. This would still require permitted provider access on the Mac and measured sync freshness. It does not cure an unsupported upstream access method, and it cannot obtain new readings while the Mac is asleep. Mac-sourced history may improve coverage only while that Mac is awake and successfully fetching.

Independent operation with the Mac asleep remains the target. If direct access fails, bring back the relay’s concrete tradeoff for a product decision; do not silently replace independence with cached Mac readings.

**Proceed when:** each included provider has an understood access method and permission basis.

**Stop or revise scope when:** access requires unavailable approval, unsupported credential sharing, or unresolved permission assumptions. Personal development distribution does not by itself resolve provider-access restrictions.

### 2. Prove independent mobile retrieval

Build a minimal personal development app with sign-in, quota values, reset times, and retrieval timestamps. No polished dashboard or history system is required for this gate.

**Pass when:** the phone signs in without imported Mac credentials, retrieves accurate readings with the Mac asleep, and retrieves fresh data after reopening. Record whether renewal works; one successful sign-in does not establish durable access.

**Stop when:** the chosen route fails and progress would require a new architecture or an extended device investigation. Bring the concrete findings back before expanding scope.

### 3. Measure widget freshness

Add one circular widget and observe it in ordinary use, including background use and a reset boundary. Record fetch times and compare displayed readings with fresh provider data.

Proposed trial, requiring agreement before device work: seven days spanning a weekly reset, with a short initial check that can end the trial early if sign-in or widget fetching fails.

Measure two things separately:

- **Data freshness:** log each fetch attempt, result, successful reading timestamp, and timeline handoff in shared App Group storage. Store diagnostics without credentials or session tokens. For each tested provider, reconstruct the age of the latest successfully persisted reading throughout a predefined daily waking-hours schedule. Proposed target: that reading is less than 30 minutes old for at least 90% of those hours. Weight by elapsed time, not number of fetches. Include failures, inactivity, and time before the first successful reading in the denominator; treat intervals whose freshness cannot be established as unknown and not passing. This measures data available to the widget, not verified onscreen freshness.
- **Display validation:** record a small set of scheduled morning and evening checks plus near-limit or reset observations. Capture the visible reading and its source timestamp before opening or refreshing the app, and compare with the stored timeline record. Fetch and timeline logs alone do not establish when iOS rendered an entry or when someone looked at it. Manual checks are a limited sample, not a measurement of every glance.

Do not count a timeline redraw as new provider data. Investigate discrepancies between fresh stored readings and stale displayed entries before calling the widget trial successful.

This is a starting hypothesis, not a promise or universal definition of useful freshness. Record misleading near-limit or reset decisions separately; a good aggregate score does not excuse those failures. A seven-day trial does not validate weekday habits or long-term authentication reliability. The existing code requests five-minute refreshes; Apple controls delivery, so that interval is not a promise.

**Pass when:** measured freshness supports useful everyday decisions, stale states are recognizable, and missing data is never presented as available capacity.

Use these observations to judge whether the data is frequent enough for meaningful daily and weekly insights as well.

### 4. Validate the focused product

Prototype the adaptive overview, widget configurations, compact history, and a small set of evidence-backed summary rules.

**Pass when:** a glance communicates allowance and reset context, the sentence adds insight beyond the gauges, and the layout remains usable across widths, orientations, and accessibility text sizes.

## Delivery sequence

Provider-access investigation → minimal personal development build → bounded widget freshness trial → focused product implementation.

Consider TestFlight after the personal build proves useful. App Store distribution is a separate decision dependent on permitted provider access and review requirements. Do not assume acceptance or begin submission.

## Later possibilities

Richer historical comparisons, StandBy-specific presentation, Apple Watch, and local-model-assisted summaries. Keep these outside the initial build unless evidence makes one necessary for the core experience.

## Current scope

The user has authorized proceeding with a personal mobile feasibility build despite unresolved distribution risk. The first technical slice is the separate [Codex mobile access probe](../prototypes/mobile-access/README.md). This does not clear provider permission, authorize a lengthy device-testing session, or authorize submission.

Competitor research is maintained separately outside this public repository.

This plan will be public source material if committed and pushed. The current site deployment script stages selected website files and directories; it does not include this Markdown plan. Keeping the plan in `docs/` therefore does not currently publish it to the marketing website.

## References checked during planning

- [Anthropic authentication and credential guidance](https://code.claude.com/docs/en/legal-and-compliance)
- [Apple App Review Guidelines: intellectual property and third-party services](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)
- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

Provider rules and platform behavior must be rechecked at the relevant feasibility gate.

## Latest feasibility evidence · September 11, 2026

Codex: the owner's recording shows successful independent phone sign-in and a fresh reading. The owner subsequently confirmed session renewal and successful fresh retrieval after force-closing and reopening the app with the Mac asleep. This clears the bounded technical access check, not distribution permission, long-term session reliability, or widget freshness.

Claude: the Safari authorization-code candidate and the limitations of the documented organization usage API are recorded in the [probe investigation](../prototypes/mobile-access/README.md#claude-access-investigation--september-11-2026). Independent supported mobile subscription-quota access remains unresolved; no Claude credentials were collected or requests made in this investigation.

The owner subsequently authorized implementing the personal Claude technical probe. Browser authorization-code exchange, separate secure storage, two-window quota parsing, and forced renewal are now implemented; live provider acceptance is still unverified. This does not resolve the permission gate or change distribution scope. See the probe README for the bounded phone check.


### Scheduled Lock Screen slice · September 12, 2026

Owner priority supersedes the initial Home Screen slice: implement the configurable Codex circular Lock Screen widget first and defer Home Screen widgets. The personal probe now includes shared reading storage, an access-only shared Keychain item, safe stale/reset states, and credential-free fetch/timeline diagnostics. Renewal remains in the app for this bounded slice; expiry displays “Open app.” See the probe README for validation and the short owner check. No extended freshness trial has begun, and simulator checks do not establish locked-device fetching or onscreen freshness.


### Refresh and widget follow-up · September 12

The owner subsequently requested slightly thicker tracks, a single widget configurable for either service, and a two-dial Lock Screen widget. These are implemented in the personal probe, together with refresh-on-foreground, five-minute widget reload requests, and shared automatic session renewal. Actual iOS delivery and physical-device renewal are still measurement gates.

Potential next experiment: sync timestamped Mac readings through a private CloudKit database and subscribe to changes on the phone. This could supplement independent phone retrieval while the Mac is awake. It requires matching provider accounts explicitly (sharing an iCloud account is insufficient), keeping credentials out of synced records, preserving source timestamps, and measuring notification-to-widget latency. CloudKit change delivery is not proof of current Mac activity or immediate widget rendering. No CloudKit implementation or extended trial is authorized by this exploratory note.
