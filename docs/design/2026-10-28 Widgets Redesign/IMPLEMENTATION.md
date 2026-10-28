# Implementation notes

Implemented on `codex/refresh-widgets-design`. `HANDOFF.md` remains the authoritative spec; supplied reference exports are unchanged.

## Decisions

- **Account** covers Home small/medium/large and Lock circular/rectangular. **Accounts** covers Home small/medium/large and Lock rectangular.
- The four legacy Lock Screen kind identifiers and their AppIntent types remain registered alongside the two complete widgets. This preserves decode paths for existing placements, but means compatibility entries still appear in the gallery. Removing these registrations before device migration is proven risks orphaning placed widgets.
- A chosen account can be from either service. Mixed-account lists preserve stable account identity, selection order, picker collision hints, and account-specific deep links. “Closest to a limit” considers the worst allowance window and monthly budget, with stable ties.
- Circular Lock Screen widgets show only the worst reading for two-window accounts, as confirmed by the updated handoff. Single-window widgets add a confirmed future reset. Curved captions use shaped Core Text runs, capped at a 160-degree sweep, with separate VoiceOver summaries.
- History is published by the app into an atomic, protected App Group file per account. Widgets do not make extra history network requests. The credential's opaque workspace scope is checked on publication and readback; disconnect clears the file. Quota refresh keeps the existing shared credential and lease path.
- Codex heatmaps use profile tokens. Weekly app/model splits use usage credits and UTC Sunday-to-today buckets. Missing dates stay unknown; incomplete coverage is labelled, and unattributed credits remain represented.
- Claude currently has no token-history feed here, so no invented heatmap is shown. Its product split appears only when a reported breakdown can fit its original percentage denominator; overlapping percentages are not normalized into a distribution. Unavailable optional history is omitted.
- Widget palette and geometry follow the current handoff and overview, including `31d`, purple spend/reset text, and label-free heatmaps. The supplied October 24 design-system JSON is an archived reference, not the implementation's source of current values.
- Full-colour widgets use the specified dark plum surface. Decorative layers live entirely inside the removable WidgetKit background. Tinted/vibrant rendering uses primary ink and an explicit warning glyph.

## Verification

Simulator review renders are exported from the widget test attachments. Tests cover mixed-account identity and ranking, budget-only accounts, reset copy, account-specific links, incomplete attribution, cache isolation, disconnect, and all registered layout sizes. Verification passed: 12 widget tests and 26 app regression tests, plus a final render check after the background correction. The app and embedded widget extension build together. The 15-image review gallery is saved at `/Users/niederme/.codex/visualizations/2026/10/28/01a184a6-0552-7a40-9355-584f62e99da5/widget-review/index.html`.

Device verification remains required for:

1. Updating an installed version with existing placements of all six old kinds; confirm both placement and account selections survive.
2. Curved text and glyph rendering in the Lock Screen's actual vibrant pipeline.
3. Home Screen tinted/clear modes, removable backgrounds, and warning glyphs.
4. The system AppIntent editor's account-list ordering and mixed-service selection.

Reproduce from this checkout:

```sh
xcodebuild -workspace AIQuota.xcodeproj/project.xcworkspace \
  -scheme AIQuotaWidget-iOS-Tests \
  -destination 'platform=iOS Simulator,id=25F98836-C7F4-4353-8E59-EF9CAF1B9949' test

xcodebuild -workspace AIQuota.xcodeproj/project.xcworkspace \
  -scheme AIQuota-iOS \
  -destination 'platform=iOS Simulator,id=25F98836-C7F4-4353-8E59-EF9CAF1B9949' \
  -only-testing:AIQuota-iOSTests/SharedQuotaStoreTests \
  -only-testing:AIQuota-iOSTests/HomeWidgetTests \
  -only-testing:AIQuota-iOSTests/LockScreenWidgetTests \
  -only-testing:AIQuota-iOSTests/WidgetReadingStatusTests test
```
