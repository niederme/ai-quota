# Mac sheet material prototype

A mock of the tinted purple glass surface for the Mac menu-bar sheet. It
renders the same sheet in dark and light appearance over a white and a black
desktop, with window clutter behind it so the translucency has something to
show. The layout inside the sheet is a stand-in; only the surface and the
legibility of text on it are under review.

Open `index.html` in a browser. `render.png` is a saved capture of all four
combinations.

Round 1 shipped in [PR #114](https://github.com/niederme/ai-quota/pull/114)
with a tint of about 90% over the regular material. On a real build that read
as a nearly solid panel, so round 2 replaced it.

## Round 2

`prototypes/sheet-material-round-2/` compares tints of 90%, 72%, 60% and 48%
over white and black desktops, with large text behind the sheet so the
translucency is easy to judge. Option B shipped in
[PR #116](https://github.com/niederme/ai-quota/pull/116):

- On macOS 26 the sheet uses the ultra-thin material under the tint; Sequoia
  keeps its stabilised surface.
- The tint is 60% in dark and 72% in light. At 48% captions fell below 4.5:1
  over a white desktop.
- A specular rim runs along the window edge, brightest at the top-leading corner.
- Reset captions are near-white (#ead2ff) in dark and deep plum (#5c1688) in
  light, because purple captions dropped to about 3.6:1 once the desktop showed
  through. Purple stays on the rings.

The prototype's blur only approximates the system material. The shipping values
live in `sheetTint`, `sheetRim` and `gaugeAccentInk` in
`AIQuota/Views/AdaptiveColors.swift`, used by `popoverSurface` in
`AIQuota/Views/PopoverView.swift`; read them there rather than here.
