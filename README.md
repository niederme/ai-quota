# AIQuota

Native apps for monitoring AI coding quota on Mac, iPhone, and iPad. Track
[OpenAI Codex](https://openai.com/codex) and [Claude Code](https://claude.ai)
with paired gauges for five-hour and seven-day allowances.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

![AIQuota on Mac](https://github.com/user-attachments/assets/78428686-f724-4d02-8cae-24621e227675)

## Features

- See Codex and Claude usage together, or connect just the service you use.
- Check reset times, plan information, and available spending or credit details.
- Keep usage visible with widgets and configurable alerts.
- Get started with guided onboarding and choose how often usage refreshes.
- See when a reading was last updated and when an account needs attention.

Available quota windows and account details depend on what each provider reports.
Background widget updates are scheduled by the operating system.

## Mac

AIQuota lives in the menu bar, with a dashboard, desktop widgets, and automatic
updates. Requires macOS 15 (Sequoia) or later and an account with access to Codex
or Claude Code. Claude Pro and Max support has been verified; Team and Enterprise
support still needs field testing.

1. Download `AIQuota.zip` from the [latest release](https://github.com/niederme/ai-quota/releases/latest).
2. Unzip and move **AIQuota** to Applications.
3. Launch AIQuota and follow guided setup to connect your accounts.

Desktop widgets include small single-service gauges, medium single-service or
paired layouts, and a large two-service overview. If a widget stays stale after
an update, removing and re-adding it can clear its cached state.

## iOS

**iPhone and iPad are in beta via TestFlight.** Public enrollment is not currently
listed here.

The app includes independent Codex and Claude sign-in, guided onboarding,
Home Screen and Lock Screen widgets, refresh controls, and per-service alerts.
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
The native launch screen uses light/dark artwork exported from Icon Composer.
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

## Anonymous usage analytics

Optional usage sharing is off by default. **Share anonymous usage data** appears
in Settings → Privacy and guided setup, with matching consent copy on Mac and
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
