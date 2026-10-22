# Mac sheet material prototype

A mock of the tinted purple glass surface for the Mac menu-bar sheet. It
renders the same sheet in dark and light appearance over a white and a black
desktop, with window clutter behind it so the translucency has something to
show. The layout inside the sheet is a stand-in; only the surface and the
legibility of text on it are under review.

Open `index.html` in a browser. `render.png` is a saved capture of all four
combinations.

The shipping material lives in `popoverSurface` in
`AIQuota/Views/PopoverView.swift`, with its adaptive colours in
`AIQuota/Views/AdaptiveColors.swift`. It first shipped in
[PR #114](https://github.com/niederme/ai-quota/pull/114). Tint strength is still
being tuned, so read the current values from the Swift source rather than this
prototype.
