# Development and releases

For website work, see [website development](website-development.md).

## Building from Source

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/niederme/ai-quota.git
cd ai-quota
xcodegen generate
open AIQuota.xcodeproj
```

Choose a scheme in the shared `AIQuota.xcodeproj`:

| Scheme | Platform and distribution |
| --- | --- |
| `AIQuota-macOS` | macOS, direct distribution |
| `AIQuota-macOS-TestFlight` | macOS, App Store / TestFlight |
| `AIQuota-macOS-Demo` | macOS, demo data |
| `AIQuota-iOS` | iPhone/iPad, including widgets and hosted tests |

The root `project.yml` includes `iOS/project.yml`. Run `xcodegen generate` from
this directory to regenerate the project for both platforms. iOS keeps its own
version and build numbers. iOS Debug and TestFlight share app and widget identifiers,
so Command+R replaces the TestFlight installation. Remove any old prototype copy
separately. See [iOS development and testing](../iOS/README.md).

If you are iterating on widgets, launching the built app once after install helps WidgetKit pick up new timelines and layouts.

---

## Dummy account lifecycle regressions

Run `python3 scripts/test-claude-account-lifecycle.py` for the bounded Mac Claude
reconnect and stale-response checks. The runner compiles the two local packages
with the installed Xcode toolchain, without dependency resolution or signing.
Coordinator persistence is injected in memory; widget HTTP uses an intercept-all
in-process `URLProtocol`. The primary refresh and additional-card sign-in methods
are copied verbatim into memory-only app adapters. The app is never launched.

`--app-source-ref HEAD` runs those app-method checks against the committed source
and intentionally fails when reproducing the old regressions. `--skip-build` reuses
libraries already compiled from the working tree. Logs, exact commands and evidence
are written under `output/claude-lifecycle-verification/`.

This is a reviewed dummy-only runner, **not an OS-enforced sandbox**. It does not
exercise live accounts, Keychain, WebKit, app-group locks, signed entitlements or
rendered UI, and does not run the older credential-writing test suites. Do not use
it to run unreviewed code or real credentials. Full app build/manual verification
is a separate step.

---

## Manual Test Handoffs

- [Settings and onboarding UI handoff](settings-onboarding-ui-handoff.md) — current hierarchy, menu bar display rules, popover material/color choices, and verification commands.
- [Team auth field-test history](team-auth-field-test-handoff.md) — failed attempts, fixes retained on `main`, and the remaining unverified account paths.
- [Claude Team test instructions](jason-team-plan-test-instructions.md) — archived test procedure for a future tester with an accessible Team account.

---

## Project Structure

```
ai-quota/
├── Packages/
│   ├── MobileAccessCore/    # iOS models, networking, and alert rules
│   └── AIQuotaKit/          # Shared Swift Package (models, networking, storage)
│       └── Sources/AIQuotaKit/
│           ├── Models/      # CodexUsage, ClaudeUsage, AppSettings
│           ├── Networking/  # OpenAIClient, ClaudeClient, AuthManagers, NetworkError
│           ├── Notifications/ # NotificationManager
│           └── Storage/     # KeychainStore, SharedDefaults
├── iOS/                     # iPhone/iPad app, widgets, shared UI, and hosted tests
├── AIQuota/                 # macOS app target (MenuBarExtra)
│   ├── Views/               # PopoverView, MenuBarIconView, SettingsView
│   └── ViewModels/          # QuotaViewModel
└── AIQuotaWidget/           # WidgetKit extension
    ├── Provider/            # QuotaTimelineProvider
    ├── WidgetIntent.swift   # AppIntent for per-widget service selection
    └── Views/               # WidgetSmallView, WidgetMediumView, WidgetGaugeView
```

---

## Releasing

For iOS TestFlight builds, use the [iOS release workflow](../iOS/README.md#testflight-release-workflow). The following steps are for direct Mac releases.

See the pre-release checklist at the top of [`scripts/release.sh`](../scripts/release.sh). The short version:

1. Update release notes and any documentation affected by the changes
2. Bump `MARKETING_VERSION` in `project.yml`
3. Run `./scripts/bump-build.sh` to increment `CURRENT_PROJECT_VERSION` and regenerate the Xcode project
4. Archive in Xcode (`Product → Archive`) and export the notarized `.app` to `~/Desktop/AIQuota.app`
5. Run `./scripts/release.sh <version>`
6. Verify `docs/releases/index.html` matches the GitHub releases list, run `./scripts/check-site-pages.sh`, then push the site/appcast updates to `main`
