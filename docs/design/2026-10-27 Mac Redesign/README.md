# Handoff: Mac sheet, rows without cards

## Overview
Rework of the AIQuota Mac menu-bar sheet (`MacSheet`, `MacAccountRow` in niederme/ai-quota). Goals:
- Remove the default card treatment from account rows and tighten vertical rhythm.
- Define hover, pressed, focus, loading and scroll behaviour.
- Add a no-accounts state that is the real layout in a placeholder state, with Connect buttons.
- Give the footer real button hit areas.

Row **contents** (dial, name, plan, reset captions, heatmap, warning lines) are unchanged from main@3d5aff4.

## About the design files
`Mac Sheet Rhythm.dc.html` is an HTML design reference, not production code. Recreate it in the existing SwiftUI codebase using its current views, materials and controls. Open the file in a browser to inspect it (keep `support.js` and `_ds/` beside it). The Tweaks panel offers: theme (dark/light), loading (all rows), max height, pin hover, show notice.

## Fidelity
High fidelity. Spacing, radii, colours and states are final. Glass, blur and the spinner are HTML approximations of system materials and controls; use the native equivalents.

## Sheet

**Width**
- 1 account: 420pt.
- 2 or more accounts: 480pt.
- No-accounts placeholder: 480pt, because it shows 2 placeholder rows.

**Unchanged**
- Corner radius 18.
- Sheet material and header as shipped: header padding 16 / 16 / 12, *AIQuota* at 26/31 semibold, refresh button.

**Body**
- Padding: 8 top, 16 left and right, 16 bottom. The 16 bottom is the gap before the footer.
- **0 spacing between rows.** Rows touch. Separation comes from row padding only.
- Notice banner (`aq-notice--mac`), if shown: first item, 16 below it before the first row. Its styling is unchanged.

**Height cap:** 88% of the screen height (the mock uses 720pt; see Scrolling).

## Account row (`MacAccountRow`)
- **Rest:** no background, no border, no shadow. Remove the `.regularMaterial` fill and the `card-edge-mac` 1px edge.
- **Padding:** 21 top and bottom (16 + 5), 16 left and right.
- **Corner radius:** 24 (`radius-mac-card`). Only visible on hover and press.
- **Inner layout:** unchanged. Dial frame and details 20 apart, details stack 8 apart, heatmap 8 below the top block on Codex.
- **Hover and keyboard focus (same look):**
  - Background `glass`: dark rgba(255,255,255,0.07), light rgba(255,255,255,0.62).
  - Inner top highlight, 1px: `glass-highlight`, dark rgba(255,255,255,0.10), light #FFFFFF.
  - No edge stroke.
  - Fade 0.12s ease-out.
- **Pressed:** glass plus a `hover-mac` tint on top. `hover-mac` is dark rgba(255,255,255,0.07), light rgba(11,6,15,0.07).
- **One at a time:** only the row under the pointer, or the focused row, shows a fill. No lingering fills.
- **Reduce Motion:** no fade.
- **Click:** whole row is the target and opens the service (behaviour as shipped).

## States shown in the file

**Account counts**
- 3b–3e: 1 to 4 accounts.
- 3f: 4 accounts, scrolled to the middle.
- 3g: 4 accounts, scrolled to the end.

**Row interaction**
- 3h: rest.
- 3i: hover and focus.
- 3j: pressed.

**Row status (3k)**
- Normal: under 85%, accent.
- Warning: 85% or more, whole dial `--warning`.
- Critical: 95% or more, whole dial `--critical`, with the line *Couldn’t update · Saved reading* in warning colour.
- Updating: meta line *Updating…* in secondary.
- Signed out: dial off (tracks only, dashes for values), meta line *Signed out · Sign in from Settings* in secondary.
- *Updating…* and the signed-out line are placeholder copy written for this mock; confirm them against the app’s strings (the shipped list has *Loading allowance…* and *Not connected*).

**Loading (3l):** refreshing over stale data.
- The row keeps the last reading. Its content (top block and heatmap) drops to 40% opacity, 0.2s ease-out.
- A spinner is centred on the row: 24pt in the mock, use `ProgressView()` at regular size.
- The row stays interactive and hover still applies.
- The row is marked busy for accessibility.

**No accounts (4a):** the real layout in a placeholder state. Two rows, Codex then Claude, identical in size and padding to connected rows.
- **Dial:** `off` state. Both tracks drawn, no fills, service glyph shown. Values read *— 5h* and *— 7d* in tertiary.
- **Name:** service name in the normal name style.
- **Plan line:** *Not connected*, in the plan style.
- **Reset captions:** two placeholder bars in their place. 136 and 172 wide, 8 tall, radius 4, `track-mac` fill (dark rgba(255,255,255,0.10), light rgba(0,0,0,0.10)), each centred in a 16pt line.
- **Connect button**, below the bars:
  - Native small prominent button.
  - Mock size: 22 tall, 10 horizontal padding, radius 6, 13pt medium, accent fill.
  - SwiftUI: `.buttonStyle(.borderedProminent)` with `.controlSize(.small)`.
- **Codex row only:** the heatmap, with every cell empty (heat-0) at 60% opacity.
- **Hover:** same as connected rows. The whole row starts the connect flow.
- **Footer:** freshness text empty.

## Scrolling
- Header and footer are fixed. Only the body scrolls once content exceeds the height cap.
- **Edge fade:** 24pt fade on the list at whichever edge has hidden content.
  - Top fade only when scrolled down.
  - Bottom fade only when more content is below.
  - No fade when the content fits.
- **Scroller:** native overlay scroller, shown while scrolling and hidden when idle. The mock draws a 6pt thumb inset 3pt from the right and 4pt top and bottom, fading out 0.3s after about 0.9s idle.

## Footer
- Padding: 8 top, 8 left and right, 10 bottom.
- *Settings* (left) and *Quit* (right) are buttons:
  - 32pt minimum height, 10pt horizontal padding, radius 8.
  - Label 13/16 medium, primary.
  - Hover: `hover-mac` fill. Pressed: `hover-mac` fill at 70% opacity.
  - SwiftUI: plain buttons with a 32pt content shape and a hover fill.
- **Freshness** (*10s ago*): centred, tertiary, not interactive.

## State
For each account:
- `status`: normal, warning, critical, updating, signedOut, or notConnected.
- `isLoading` (stale data plus spinner).
- `lastReading`.

For the sheet:
- `hoveredRowID` (one at most), plus focus.
- Scroll offset, used for the edge fades.
- Show the placeholder rows when no accounts are connected.

## Tokens used
- **Colours:** `glass`, `glass-highlight`, `hover-mac`, `track-mac`, `primary`, `secondary`, `tertiary`, `accent`, `warning`, `critical`, `reset-accent`.
  - Dark: accent #BF5AF2, warning #FF9F0A, critical #FF453A.
  - Light: accent #AF52DE, warning #FF9500, critical #FF3B30.
- **Spacing:** 4, 8, 16, 20, plus 21 (16 + 5) for row padding.
- **Radii:**
  - Row 24 (`radius-mac-card`).
  - Footer buttons 8 (`radius-row`).
  - Connect button 6.
  - Placeholder bars 4.
  - Sheet 18.
- Full token values are in `_ds/…/tokens/tokens.css`. Component CSS is in `_ds/…/_ds_bundle.css` (`.aq-macsheet`, `.aq-macrow`). In this design, inline styles override the bundle values.

## Assets
Service glyphs (OpenAI, Claude) are the existing template images in the app. No new assets.

## Files
- `Mac Sheet Rhythm.dc.html`: all states. Open in a browser.
- `support.js`: runtime for the HTML file.
- `_ds/`: design-system CSS and tokens the file loads.
