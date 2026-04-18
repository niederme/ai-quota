# Firebase Analytics Event Plan

Date: April 17, 2026

## Questions This Should Answer

- How many new instrumented installs are we getting?
- How many active users do we have daily and monthly?
- How many installs become activated users?
- Which connected services are people actually using?
- How often do people come back and manually refresh or open the popover?
- How many users opt into anonymous analytics?

## Source Of Truth

Built-in Firebase/GA4 events answer:

- `first_open`: new instrumented installs
- `session_start`: active sessions
- `user_engagement`: engagement and stickiness
- `app_update`: version adoption

Custom AIQuota events answer product-specific questions:

| Event | Purpose | Key params |
| --- | --- | --- |
| `app_launched` | app-open context | `app_version`, `services`, `service_count`, `menu_bar_service`, `notifications_enabled`, `onboarding_completed` |
| `app_active` | daily active product use | `surface`, `services`, `service_count`, `active_service`, `menu_bar_service` |
| `popover_opened` | core product interaction | `services`, `service_count`, `active_service`, `menu_bar_service`, `notifications_enabled` |
| `manual_refresh` | high-intent usage | `services`, `service_count`, `active_service`, `menu_bar_service` |
| `service_connected` | activation milestone | `service`, `services_after_connect`, `service_count` |
| `service_disconnected` | churn / service mix changes | `service`, `services_after_disconnect`, `service_count` |
| `onboarding_completed` | setup completion | `completed_from`, `has_connected_service`, `services`, `service_count` |
| `analytics_enabled` | opt-in rate | `consent_surface`, `has_connected_service`, `services`, `service_count` |
| `menubar_service_changed` | preference / multi-service usage | `service`, `services`, `service_count`, `menu_bar_service` |

## Working Metric Definitions

- `Installs`: GA4 `first_open`
- `DAU`: GA4 Active Users, optionally cross-checked against custom `app_active`
- `MAU`: GA4 Active Users over 30 days
- `Activated installs`: users with either `service_connected` or `onboarding_completed` where `has_connected_service = true`
- `Analytics opt-in rate`: users with `analytics_enabled`

## Intentional Non-Goals

- No prompts, tokens, cookies, or personal data
- No `user_id`
- No ATT / IDFA path
- No attempt to reconstruct pre-consent onboarding steps

## Notes

- Because analytics consent comes late in onboarding, pre-consent steps are intentionally not tracked.
- For opt-in users who already connected a service before enabling analytics, `analytics_enabled` plus the `services` params preserves activation context without backfilling hidden events.
