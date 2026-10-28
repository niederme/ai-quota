# Handoff: iOS overview cards, Mac row treatment

Repo: `niederme/ai-quota` (main). Target: the iOS overview, `iOS/App/OverviewView.swift`.

## Overview
Bring the Mac account row's card design, dial geometry and vertical rhythm to the iPhone/iPad overview. On iOS the Mac row's **hover/highlighted surface is the resting card**. The nav bar, the toolbar (refresh and settings), the iOS reset strings and the chevron are unchanged.

## About the design files
`iPhone Overview Refined.dc.html` is a **design reference built in HTML**, not code to port. Open it in a browser (keep `support.js` and `_ds/` next to it). Rebuild it in SwiftUI using the patterns that already exist in the repo. Most of the values below come straight from the Mac views, so **reuse those views and constants**; don't re-derive them from the HTML.

Turns in the file (the newest is at the top):
- **3a–3e**: the final design with 0, 1, 2, 3 and 4 accounts, a fixed 852pt screen and scroll edge fades. **Build this.**
- **2a / 2b**: the final card in dark and light, with the notice banner.
- 1a: as shipped (the baseline). 1b and 1c are superseded; ignore them.

## Fidelity
High fidelity. Match the values exactly.

## Source of truth in the repo
| Element | Mac source to reuse or mirror |
|---|---|
| Card surface | `MacAccountRowSurface` in `AIQuota/Views/MacAccountOverviewItem.swift` |
| Card layout | `MacAccountCard.body` / `details` (same file) |
| Dial | `MacAccountDial` in `AIQuota/Views/MacAccountDial.swift` |
| Empty rows | `MacAccountPlaceholderRow` (same file as the card) |
| Notice | `MacResetNoticeBanner` in `AIQuota/Views/MacResetNoticeBanner.swift` |
| List padding and edge fades | `MacAccountGridView` in `AIQuota/Views/MacAccountGridView.swift` |
| Colors | `AdaptiveColors.swift` (`overviewGlass`, `overviewGlassHighlight`, `overviewTrack`) |

Consider moving `MacAccountDial` and `MacAccountRowSurface` into shared code, or duplicating them as iOS views with identical constants.

## Screen: Overview (`OverviewView.dashboard`)

### Scroll content
- `VStack(alignment: .leading, spacing: 8)` (it was 24). The Mac stacks rows at 0 because they're clear at rest. iOS cards show their surface, so they use **8**.
- Padding: horizontal 16, **top 8** (was 20), bottom 16. Max width 780, unchanged.
- Order: demo banner, reset notice, cards, freshness footer.
- **Edge fade**: mask the scroll view exactly as `MacAccountGridView` does. Fade the top edge only when scrolled away from the top, and the bottom edge only when content is hidden below. Fade length `min(0.5, 24 / height)` of the viewport. With no overflow, there is no fade. Keep `.refreshable`.

### Service card (replaces `ProviderDialCardContent` layout and `OverviewCardMaterial`)
- Whole card is one `Button` (`.buttonStyle(.plain)` with a custom style). The tap opens the service sheet, unchanged.
- **Surface (resting = Mac highlighted):**
  - `RoundedRectangle(cornerRadius: 24)` filled with `accent.opacity(0.06)` (`overviewGlass`)
  - plus a 1pt top line, `accent.opacity(0.10)` (`overviewGlassHighlight`), clipped to the shape
  - **Pressed:** overlay `accent.opacity(0.05)`, `.easeOut(duration: 0.12)`. Reduce Motion removes the animation.
  - No border, no shadow, no `glassEffect` / material (the design shows no blur; it was tested and rejected).
  - Radius **24** (was 28).
  - Dark accent `#BF5AF2`, light `#AF52DE`.
- **Padding:** horizontal 16, top **21**, bottom **21**. When the Codex heatmap closes the card, the bottom is **16**.
- **Summary row:** `HStack(alignment: .top, spacing: 20)`, dial then details (was 24).
- **Stacked layout** at accessibility sizes, or when narrower than the dial plus 180: keep the existing behaviour (`VStack` spacing 12).

### Dial (use `MacAccountDial` geometry)
- Layout frame 108×108, `.padding(.top, 5)`, then `.frame(height: 103, alignment: .top)`. The unused lower quarter takes no space.
- Two windows: both rings 7pt; the inner ring has 9pt padding. One window: a single 10pt ring.
- Arcs: `trim(0, 0.75)` rotated 135°, butt caps. Track `overviewTrack` (white 10% in dark, black 10% in light). The secondary ring is at opacity 0.7.
- Contents: `VStack(spacing: 5)` holding the glyph (18×18), then readouts `VStack(spacing: 2)`: `16pt semibold, monospacedDigit`, width 80, `minimumScaleFactor(0.85)`. The second readout is at opacity 0.7. With two rings, offset the stack `y: -5`.
- Tint by the worst window: under 85 `accent`, 85 and up `warning`, 95 and up `critical`. The tint applies to the rings, glyph and readouts.
- Dynamic Type: the Mac dial is fixed. On iOS, scale the 108 with `@ScaledMetric` (cap at 200) and keep the ratios.

### Details column
- `VStack(alignment: .leading, spacing: 8)`, `.padding(.top, 8)` (was 2).
- Identity: `VStack(spacing: 4)`
  - Name: `20pt semibold`, tracking −0.25, `primary`, line box 24. The chevron (`chevron.right.circle.fill`, 20pt, `tertiary`) is trailing, centered on the name line.
  - Plan: `13pt semibold`, `primary`, line box 16. Show the account label (" · Work") only when a service has more than one account, or the label is not a default (the Mac `accountLabel` rules).
- Reset lines: `VStack(spacing: 0)`, `13pt regular monospacedDigit`, `resetAccent`, line box 16. Keep the **iOS strings** ("5h resets 3:40 PM", "7d resets Tue 10:07 PM").
- Status (only *Limit reached*, *Reconnect to update*, *Couldn't update · Saved reading*, *Loading allowance…*, *No reading yet*): `13pt`, `secondary`; use `warning` when it's an error.
- Drop `OverviewDetailType`'s compact 22/15 line boxes; use the natural 24/16.

### Codex token heatmap (`MobileTokenHistoryView`)
- `.padding(.top, 8)` below the summary, `.padding(.horizontal, -5)` so it lines up with the ring's outer edge (`MacAccountDial.strokeOutset`). Pass `availableWidth + 10`.
- **No "Token activity" title and no month labels** (also being removed on the Mac). The grid ends the card: bottom padding **16** below the grid.
- Cell gap 1, radius 1, 42 weeks (unchanged).

### Reset notice (`CodexResetNoticeBanner`, Mac styling)
- Padding: horizontal 16, vertical 12. `HStack(alignment: .top, spacing: 8)`.
- Title: `15pt semibold`, `primary`. Link row: "Read more on Codex Resets" plus `arrow.up.right`, `15pt`, `accent`, spacing 6. Lines 6 apart.
- Background: `RoundedRectangle(24)` filled with `.regularMaterial`, plus `accent.opacity(0.22)`, plus a 1pt `strokeBorder` of `primary.opacity(0.16)`.
- Dismiss: `xmark.circle.fill`, 16pt, `secondaryLabel` at 0.75. **Keep a 44×44 hit target**, with the glyph top-trailing.

### No accounts (proposal, 3a)
iOS currently shows onboarding here. The design proposes the Mac `MacAccountPlaceholderRow` instead:
- Same surface and padding as a card. The dial is all `tertiary`, tracks only, with readouts "— 5h" / "— 7d".
- Details: the name, then "Not connected" (13 semibold). Two placeholder bars (max width 136 and 172), each 8pt tall with radius 4 in `overviewTrack`, sitting in a 16pt frame. Then a prominent small **Connect** button with 4 above it.
- Codex adds the empty heatmap (`overviewTrack` cells, opacity 0.6, no month labels), 8 below the summary, 16 bottom padding.
- Footer: "Connect a service to see your usage."
- **Confirm with design before shipping this case.**

### Freshness footer
Unchanged copy. `footnote`, `secondary`, centered, lines 4 apart, 8 above it.

## Interactions
- Tapping a card opens `ServiceAccountSheet`, unchanged. The press tint is described above.
- Refresh: unchanged; the glyph swaps for a spinner.
- Notice dismiss: unchanged (`dismissedResetID`).
- Scroll fades update live as you scroll.
- Reduce Transparency: unchanged. The wash is removed; the card fill is a flat tint, so it needs no change.

## Tokens used
- `accent` #BF5AF2 / #AF52DE · `resetAccent` #D77EF7 / #7A24A6 · `primary` #FFFFFF / #0B060F
- `secondary` rgba(235,235,245,.62) / rgba(60,60,67,.62) · `tertiary` .32 alpha, same bases
- `warning` #FF9F0A / #FF9500 · `critical` #FF453A / #FF3B30
- Card fill accent 6% · top line accent 10% · press accent 5% · notice tint accent 22% · track white 10% / black 10%
- Spacing: 4, 5, 8, 9, 12, 16, 20, 21 · Radius: 24 (cards, notice), 4 (placeholder bars), 1 (cells)

## Verify
- 1–4 accounts on iPhone 393pt wide, dark and light (3b–3e, 2a/2b).
- With 3+ accounts the list scrolls behind the fixed screen, and the fade appears only at hidden edges.
- Accessibility text sizes still stack the dial above the details.
- Update `BaseScreenReviewTests` / `TokenHistoryReviewTests` snapshots as needed.

## Files
- `iPhone Overview Refined.dc.html`: the design (turns 3 and 2)
- `support.js`, `_ds/…`: needed to open the HTML locally
