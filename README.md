# AIQuota

Native apps for monitoring AI coding quota on Mac, iPhone, and iPad. Track
[OpenAI Codex](https://openai.com/codex) and [Claude Code](https://claude.ai)
with paired gauges for five-hour and seven-day allowances.

This README describes AIQuota 2.0, which is in TestFlight on Mac, iPhone, and
iPad. The current direct-download Mac release is 1.9.28, which does not yet
include multiple accounts or the redesigned Settings.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

![AIQuota on Mac](https://github.com/user-attachments/assets/78428686-f724-4d02-8cae-24621e227675)

## Features

- See Codex and Claude usage together, or connect just the service you use.
- Connect more than one account per service, rename them, and reorder their cards.
  Signing in to an account that is already connected adds nothing.
- Follow six months of Codex activity in a daily heatmap on each Codex account.
- Get a dismissible notice when Codex announces or hints at a usage reset.
- Check reset times, plan information, and available spending or credit details.
- Keep usage visible with widgets and alerts at a usage threshold you choose
  (90% by default).
- Get started with guided onboarding and choose how often usage refreshes.
- See when a reading was last updated and when an account needs attention.

Available quota windows and account details depend on what each provider reports.
Background widget updates are scheduled by the operating system.

## Mac

AIQuota lives in the menu bar, with a sheet of account cards, desktop widgets,
and automatic updates. Requires macOS 15 (Sequoia) or later and an account with access to Codex
or Claude Code. Claude Pro and Max support has been verified; Team and Enterprise
support still needs field testing.

1. Download `AIQuota.zip` from the [latest release](https://github.com/niederme/ai-quota/releases/latest).
2. Unzip and move **AIQuota** to Applications.
3. Launch AIQuota and follow guided setup to connect your accounts.

The menu-bar sheet shows a card for each connected account, with its dial,
reset times, and (for Codex) the six-month activity graph. The sheet is
translucent plum glass that lets the desktop show through, with a purple glow
and a bright rim on its edge, and adapts to light and dark appearance. Captions
on it are near-white in dark and deep plum in light so they stay readable over
any desktop; purple stays on the rings. The menu
bar itself shows gauges for the first two accounts by default; open an account
in Settings to choose whether its gauge appears there. Drag accounts in
**Settings → Accounts** to reorder their cards. Opening a Codex card shows its
daily, by-model and by-app usage charts, for every connected Codex account.

Settings has four panes: **General** (launch at login, refresh interval, updates,
privacy, troubleshooting, and reset), **Accounts**, **Notifications**, and
**About**. On Mac, usage alerts follow the original connection for each service.

On Mac, the Claude account's **Reuse Claude Code Keychain credentials** toggle in
**Settings → Accounts** is an
optional, default-off shortcut to Claude Code's saved sign-in. AIQuota only reads
it when access is available without a macOS permission prompt. If access is
unavailable, use Claude sign-in in AIQuota. Turning reuse off prevents subsequent
use of credentials cached from that Keychain item. Existing file-based credentials
and web sessions are unaffected. This setting does not change iPhone/iPad sign-in.

Desktop widgets include small single-service gauges, medium single-service or
paired layouts, and a large two-service overview. If a widget stays stale after
an update, removing and re-adding it can clear its cached state.

## iOS

**iPhone and iPad are in beta via TestFlight.** Public enrollment is not currently
listed here.

The app includes independent Codex and Claude sign-in, multiple accounts per
service, guided onboarding, Home Screen and Lock Screen widgets, refresh
controls, and per-account alerts. In **Settings → Accounts** you can add, rename,
and remove accounts and pick the widget default; drag cards on the overview to
reorder them. Each Codex card includes a full-width six-month activity heatmap
that matches the Mac palette.
Codex sign-in uses one **Copy code and continue** action and retains the browser
when you close and reopen the same attempt. **Reset All Settings** clears local
connections, cached usage, and preferences so setup starts fresh.

A dismissible notice highlights current Codex reset announcements and hints,
with details from [Codex Resets](https://codex-resets.com/) opening in the app.
These notices are separate from your account's actual quota and do not send
notifications. Cards share the same Liquid Glass treatment and show skeletons
while refreshing.

Connections are stored on the device. Device testing continues for session
recovery, background refresh, accessibility, and notification delivery.
The native launch screen places the icon’s standalone artwork on a light/dark purple gradient.
See the [iOS v1 handoff](iOS/docs/IOS_V1_HANDOFF.md) for the saved next steps.

## Understanding usage

The outer gauge shows the five-hour window when reported; the inner gauge shows
the weekly window. Unreported values remain unavailable rather than appearing as
zero usage.

Claude usage credits are shown separately from plan allowances. AIQuota displays
the reported monthly spending total without inventing a breakdown by model or
usage type. Account details vary by provider and plan.

## Development

The apps share an Xcode project with separate Mac and iOS schemes.

- [Build from source and release the Mac app](docs/development.md)
- [iOS development, testing, and TestFlight releases](iOS/README.md)
- [Website previews and deployment](docs/website-development.md)
- [Roadmap and validation priorities](docs/roadmap.md)
- [Design references and HTML prototypes](prototypes/README.md)

## Anonymous usage analytics

Optional usage sharing is off by default. **Share anonymous usage data** appears
in Settings (General → Privacy on Mac, Privacy on iOS) and guided setup, with matching consent copy on Mac and
iOS. It reports app activity and setup events without sending prompts,
credentials, account identifiers, or quota readings. iOS demo activity is excluded,
and Reset All Settings revokes consent.

The iOS integration and shared `ios` / `macos` event tags were merged in
[PR #67](https://github.com/niederme/ai-quota/pull/67). iOS delivery was verified
in Firebase DebugView on September 22, 2026; this verification did not ship an
app release. Users receive these changes when updated Mac and iOS builds ship.

Historical Mac events remain intact but are not retroactively platform-tagged.
A combined historical and newly tagged Mac report remains unresolved. See the
[analytics setup and reporting notes](iOS/README.md#anonymous-usage-analytics)
for configuration, validation, and reporting limitations.

## Support

Report problems or request features in [GitHub Issues](https://github.com/niederme/ai-quota/issues).
For downloads and release notes, visit [aiquota.app](https://aiquota.app).

## License

MIT with [Commons Clause](https://commonsclause.com). Free to use, modify, and
distribute. Commercial or proprietary use is not permitted.
