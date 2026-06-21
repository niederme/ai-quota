# AIQuota Team Auth Handoff

Last updated: June 21, 2026

## Status

Continue from `main`. The former `team-auth-field-retest` branch has been
merged and is retained only as history.

Implemented on `main`:

- Claude Code OAuth file discovery.
- Explicit `Connect` support for the Claude Code Keychain item.
- Embedded Google OAuth popup hosting for Claude and ChatGPT.
- Codex CLI OAuth discovery and Team workspace-ID extraction.
- Team/Enterprise plan parsing and Enterprise spend-limit model support.
- Redacted auth-source diagnostics.

Verified:

- Claude Pro works.
- Khoi's individual Claude Max account connects and refreshes.
- Codex works on the maintainer's account.
- Sequoia and macOS 26 popovers, widgets, and onboarding render correctly.

Not verified:

- Claude Team usage.
- Claude Enterprise OAuth usage and spend-limit currency units.
- Browser-only Team accounts without Claude Code credentials.

Jason's Team retest cannot continue because his Mac is now locked down by
corporate IT.

## Auth Boundary

App authentication is decided only by live sources:

1. Noninteractive CLI OAuth credentials during bootstrap.
2. Live WebKit session.
3. Explicit `Connect`, which may perform an interactive Claude Code Keychain
   read before opening WebKit.

`SharedAuthContextStore` is only a credential snapshot for widget background
refresh. It must not authenticate the app or revive a stale session.

The abandoned `/usr/bin/security` subprocess reader has been removed. Bootstrap
never reads Claude Code's Keychain item, and explicit `Connect` uses
Security.framework directly.

## Next Work

1. Find a new Team tester with Claude Code access.
2. Capture redacted diagnostics and a response-shape fixture.
3. Find an Enterprise tester and confirm whether OAuth spend values are cents
   or dollars.
4. Add fixtures before changing parsing or claiming support.

See:

- [`team-auth-field-test-handoff.md`](team-auth-field-test-handoff.md)
- [`claude-enterprise-main-review.md`](claude-enterprise-main-review.md)
- [`claude-enterprise-support-plan.md`](claude-enterprise-support-plan.md)
