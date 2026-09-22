# iOS visual direction and service sheets

The overview follows the purple AIQuota brand and core dual gauges. Native SF typography, SF Symbols, toolbar controls, and regular Liquid Glass on iOS 26+ provide the interface. Older supported systems use regular material. Inactive gauge tracks use `quaternarySystemFill`; unavailable windows use ticks, and reported zero remains a solid track. Reduce Transparency removes the decorative purple wash.

Tapping anywhere in a service card opens its detail sheet. Settings and its destinations also use sheets. Account screens contain connection status, plan, and Disconnect; reconnect appears only for authentication failures. Usage is not repeated there. Settings, onboarding, and widget setup share the brand tokens. Widget extension layouts remain unchanged. The accompanying earlier work includes macOS unavailable-track refinements, plan-change notifications, persistent iOS sign-in, and release tooling for the sign-in code extension.

## Service details

Both services show positive monthly credit spending with an explanation, exact reset times, and account access. Zero spending hides the spending block; absent spending remains explicitly unavailable. Currency is shown only when provided, except Codex's existing USD conversion. Spending amounts use proportional SF digits. Supporting copy uses one footnote style.

Codex retains provider daily history with model and app/tool attribution. Two purple composition strips show shares over 7 or 30 days, with the three leading categories and remaining usage grouped as Other. The full grouped names remain visible. Usage credits include plan-covered consumption and must not be interpreted as paid overage attribution.

Claude's current iOS OAuth path does not establish a product or model breakdown. No speculative chart is shown. Its spending explanation preserves the existing combined Fable 5 and post-limit interpretation.

## Data and refresh

The daily history endpoint is documented in `docs/chatgpt-usage-api-surface.md`. Model and surface values describe the same usage and are never added together. Missing dates remain gaps; reported zero remains zero. Date-only buckets use consistent UTC query boundaries, while provider timezone semantics remain unverified. No local history collection is introduced.

Refresh displays skeleton values and chart placeholders while preserving layout. A successful overview uses one refreshed timestamp; failures identify each service and its last reading. A Claude 429 starts a five-minute cooldown shared by app and widget under the existing file lease. Suppressed attempts do not extend it. Saved readings and credentials remain intact. This fixed fallback does not guarantee the provider will accept the next request.

## Validation

Core tests cover history decoding, model/surface separation, speed aggregation, missing versus zero data, and old-cache compatibility. iOS tests exercise layout, sheet presentation/dismissal, and cooldown suppression/expiry. Visual reviews used synthetic fixtures; manual device iterations used Karin Air. The isolated PR is built and tested from its own worktree.
