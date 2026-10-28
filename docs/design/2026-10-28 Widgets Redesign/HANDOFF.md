# iOS widgets, next iteration: dev handoff

This document is the spec and is meant to stand on its own. Every size, colour, string and state needed to build is written out below.

Visual reference: the PNGs in `screenshots/` and the flattened pages in `rendered/` (open in any browser). The source canvas is private to John and isn't needed to build. If a picture and this document ever disagree, this document wins.

All sizes are points at iPhone 6.3" widget sizes: small 158×158, medium 338×158, large 338×354, Lock circular 72×72, Lock rectangular 160×72. Readings in examples are sample data.

Current code this replaces: `iOS/Widget/CodexWidget.swift`, `iOS/Shared/HomeQuotaView.swift`, `iOS/Shared/CompactQuotaView.swift`, `iOS/Shared/LockScreenResetPresentation.swift` (main@eedcef4).

## 1. What changes and why

The app now supports any number of accounts per service, Enterprise budgets and in-card history. The widgets still assume one Codex slot and one Claude slot, draw their own off-system dial and show no history. This iteration:

- Replaces six widget kinds with two: **Account** (one account in depth) and **Accounts** (several at a glance).
- Uses the app's dial everywhere, with token colours only.
- Adds history (the token heatmap and weekly splits) from medium size up.
- Makes the circular dial the brand: no bar charts anywhere.

## 2. Lineup

| Kind | Lock circular | Lock rectangular | Home small | Home medium | Home large |
|---|---|---|---|---|---|
| Account | Dial + curved line | Dial + 3 text lines | Dial + name + reset | Dial + details + heatmap | Dial + details + heatmap + splits |
| Accounts | Not offered | 2 dials | 2 rows | 4 dials | 4 dials, 2×2 |

- Lock inline is not offered.
- Account can follow a chosen account or **Closest to a limit**: the account whose worst window is highest.
- Accounts takes an ordered list, defaulting to worst first. Caps: 2 on Lock rectangular, 2 on Home small, 4 on medium and large.

### Migration (verify on device)

- Reuse kind strings where the family matches, so placed widgets survive.
- `CodexLockScreen` and `ServiceDetails` become Account.
- `AIQuotaHomeSingle` becomes Account.
- `AIQuotaHomeBoth` becomes Accounts.
- `BothLockScreen` and `CompactLockScreen` become Accounts rectangular, with their two accounts prefilled.

## 3. Configuration (AppIntent)

- **Account**: `show` is either Chosen account or Closest to a limit, plus one `WidgetAccount` (any service).
- **Accounts**: an ordered `[WidgetAccount]` (any service, mixed), plus `order` (Closest to a limit or As listed).
- Keep the existing collision hints in the picker (provider identity, then short ID).
- The edit sheet is the system AppIntent sheet. Parameter titles: Show, Account, Accounts, Order.

## 4. The dial

Same component as the app overview (OverviewView dial). Geometry is in % of dial size so it scales.

| Part | Two windows | One window |
|---|---|---|
| Outer ring | radius 45%, stroke 6.5% (ring 8 at 124) | radius 44%, stroke 9.7% (ring-single 12 at 124) |
| Inner ring | radius 37%, stroke 6.5%, opacity 0.7 | none |
| Arc | 270°, open at the bottom, butt caps, track `track` | same |

- **Compact multi-account dials** (Accounts widgets, ≤60pt): pull the single ring in to radius 42.5% so it reads the same size as a two-ring neighbour. Keep the heavier single stroke.
- **Colour**: the worst window picks one colour for the whole dial (rings, logo and numbers): `accent` under 85%, `warning` from 85%, `critical` from 95%.
- **Inside the dial**, when readings are shown:
  - Logo at 14.5% of the dial.
  - About 3% gap from logo to readings.
  - Readings at 12.1% of the dial, medium weight, tabular digits.
  - Both readings the same size, stacked with no gap; the 7d line at 0.7 opacity.
- **Window keys**: `5h`, `7d`, `31d`. "Monthly" is retired, and "31d" matches the current Mac app.

## 5. Lock Screen (vibrant, no background)

No backing plate, as with Weather. `containerBackground` is clear, and hierarchy comes from opacity only: primary 1.0, secondary 0.6.

### Circular (Account): chosen design, "one line on top"

- The shipping rings and logo, plus one line of text curved along the inside of the ring, above the logo, centred on top dead centre.
- **Text**:
  - Regular weight, 11.5% of the dial (about 7.6pt at 66), 8% tracking.
  - Upright, tops toward the ring.
  - Baseline radius 28% on one-ring dials and 25% inside the inner ring on two-ring dials.
  - The text sits centred between the ring's inner edge and the logo.
- **Content**:
  - One window: `66% · 31d Nov 1`.
  - Two windows: the worst reading only, e.g. `88% 7d`. No reset: with both on one line the type shrinks to about 6pt, below legibility. The rectangular widget carries the reset.
- **Fit**: the line may sweep at most 160°. If it is longer, scale the type down to fit rather than wrapping round the dial.
- **Implementation**: iOS has no curved-text API for Lock Screen widgets. Lay out glyphs along the arc yourself:
  - Preferred: `TextRenderer` (iOS 18), which keeps SF metrics and kerning.
  - Fallback: Core Text glyph runs drawn in a `Canvas`.
  - Prototype in vibrant mode on device first.

### Rectangular (Account), 160×72

- Dial 60pt on the left, 4pt gap, then a three-line text stack:
  - 14pt, 17pt line height, medium weight.
  - Nudged up 5pt to centre on the dial's optical centre: the open arc makes the dial's visual weight sit high.
- **Line 1**: full name, service first (`Codex Personal`), semibold, truncated with an ellipsis at about 94pt.
- **Lines 2 and 3**: one of three variants.
  - Readings: `62% 5h`, then `41% 7d` at 0.6.
  - Next reset: worst window, then its reset (`88% 7d`, `Wed 2:00 PM`).
  - One metric: `66% 31d`, then `Sun 12:00 AM`.

### Rectangular (Accounts), 160×72

- Two equal columns.
- Each column: a 56pt dial with the compact stroke, logo only, no numbers.
- Under each dial, the label at 11pt medium, truncating.

## 6. Home Screen (full colour)

### Background

All layers live inside the removable `containerBackground`, so tinted and clear Home Screens can drop them:

- Base `#1E1223` (the Mac WidgetSurface).
- Accent radial glow from top-trailing at 14% (110%×80%, fading to clear at 70%).
- White sheen at 5%, fading out over the top 45%.
- 1pt top highlight at 10% white, plus a 1pt rim at 6% white.

### Shared text styles (no one-offs)

| Role | Style |
|---|---|
| Name under a dial | 11pt semibold, `primary`, single line, ellipsis (`Codex Personal Workspace` becomes `Codex Personal Worksp…`) |
| Reset or spend under a dial | 10pt, `reset-accent` |
| Service name in details | 17pt semibold |
| Plan line | 12pt semibold (`Max plan · Personal`) |
| Reset lines and spend in details | 12pt, 15pt line height, `reset-accent`, stacked with no gap |
| Secondary text | opaque `#9A98A2`. Do not use `.secondary`: on the plum ground it tints purple. |

### Spacing

- Padding is 12pt on small widgets and 16pt on medium and large.
- Section gaps are 16 or 24pt.
- In details:
  - Name to plan: 4pt.
  - Groups: 8pt on medium, 12pt on large.

### Widget specs

**Account small**
- Dial 100pt with both readings.
- Name tucks up 6pt into the arc opening, then the reset line.
- The group is centred vertically with 2pt gaps.
- Budget variant: dial `66%` / `31d`, then `Spent $660 of $1,000` in reset-accent.

**Accounts small**
- Two rows, 12pt apart, vertically centred.
- Each row: 56pt compact dial (logo only), 8pt gap, then the name (up to 2 lines, 11pt semibold) and the reset (10pt).
- A 3-row variant (40pt dials) was explored and not recommended.

**Account medium**
- Dial 124pt, then 16pt to the details: name, plan, reset lines.
- Then the heatmap at full width of the details column:
  - 27 weeks, 4pt cells, 2pt gaps, 1pt radius.
  - No labels.

**Accounts medium**
- Four equal columns, 14pt column gap, 16pt padding.
- 60pt compact dials, logo only.
- Name and reset under each, 4pt below the dial.

**Account large**
- Dial row: dial 124pt, 16pt gap, then details in groups 12pt apart.
- Then the heatmap and the weekly split(s). Sections are 24pt apart, or 16pt when there are two splits.
- **Heatmap**:
  - 36 weeks, 6.5pt cells, 2pt gaps, 1pt radius.
  - Same ramp and rules as `MobileTokenHistoryView`: no-record dim, zero grey, quartiles on `heat-1` to `heat-4`.
  - No month labels.
- **Weekly split**:
  - 12pt semibold title.
  - 8pt bar with 2pt gaps, using the top three heat steps.
  - Legend at 10pt with 6pt colour swatches.
- **By service**:
  - Claude shows "This week by product" (one split).
  - Codex shows "This week by app" and "This week by model" (two splits), with the dial at 112pt to fit.
- No header and no timestamp.

**Accounts large**
- 2×2 grid of 116pt dials with both readings.
- Name and reset under each.
- Centred, no header.

## 7. States

| State | Dial | Line under the name |
|---|---|---|
| Normal | accent | next reset |
| Warning, worst window ≥85% | whole dial `warning` | next reset |
| Limit reached, ≥95% or at the limit | whole dial `critical` | `Limit reached` |
| Saved reading (stale) | rings and numbers `secondary`, clock badge bottom-trailing | `Older reading · 2 hours ago` |
| Reconnect | alert glyph, no readings | `Reconnect to update` |
| Not connected | dashed tracks, N/A | `Not connected` |
| Window not reported | that ring dashed, `N/A 7d` | next reset of the other window |
| Demo | `Demo` in place of the logo | `Sample usage` |

- **Freshness**: no timestamp when the reading is fresh. Stale readings switch to the saved state.
- **Tinted and clear modes**:
  - The dial group is `widgetAccentable`; text stays primary.
  - Colour can't carry state there, so at ≥85% add a small warning glyph before the name.
- **Light**: light `warning` is 2.1:1 on glass, so the dial numbers need a darker warning ink before light ships.

## 8. Reset copy

- Today: time only (`3:40 PM`).
- Within 7 days: weekday and time (`Wed 2:00 PM`).
- Further out: date (`Nov 1`).
- In tight spots (curved lines, small columns), use the compact forms `Tue 10P` and `3:40P`.
- Note: the current Mac app writes `Resets Wed at 4:21 AM`. iOS and Mac wording should be reconciled.

## 9. Accessibility

- Keep the current VoiceOver summaries: full spoken date and time, freshness, and reconnect.
- Curved text is decorative for VoiceOver. Expose the same string as the element's label.
- Each Accounts dial is its own element, labelled "{Service} {account}, {reading}, {reset}".
- Respect Dynamic Type up to the widget's fixed frame. Truncate names before shrinking numbers.

## 10. Open questions

1. **Design system is out of date.** The App Design System artifact is from Oct 24 (main@3d5aff4). The current app shows `31d`, purple spend lines, full-width heatmaps and new reset wording. Sync it before building.
2. **Background removability.** The Mac marks it non-removable. This spec keeps it removable on iPhone so tinted and clear modes work.
3. **Two-window curved line.** Resolved: worst reading only (`88% 7d`). Revisit only if a device test shows the reset fits at a legible size.
4. **Short widget label per account.** Long names truncate hard on Lock Screen and Accounts widgets.
5. **History source.** Does the widget read history from the app group cache, or fetch it itself?
6. **Kind-string migration.** Confirm on device that placed widgets survive.
