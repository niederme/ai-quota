# AIQuota iOS widgets: handoff package

Start with HANDOFF.md. It is the spec and stands on its own.

- HANDOFF.md: layout, sizes, tokens, states, copy rules, implementation notes, open questions.
- design-source/: the design canvas's source files (one .dc.html per board, plus canvas.json). Reference only: they need the claude.ai Design runtime to render (use screenshots/ or rendered/ instead), and they are not production code.
  - Dial.dc.html: the dial component. Its script holds the exact ring geometry, colour-by-state logic and curved-text layout used on every board.
  - Next-Lock.dc.html, Next-Home.dc.html, Next-States.dc.html, Next-Config.dc.html: the next iteration.
  - Main.dc.html, Audit-Findings.dc.html: the audit of what ships today.
- tokens/: the AIQuota App Design System tokens as last synced (Oct 24, main@3d5aff4). Out of date in places: see HANDOFF.md, open question 1.
- assets/: the Codex and Claude service glyphs as used in the mockups (same as the app's template images).
- screenshots/: the five final boards as PNG, at 1x (1pt = 1px) and @2x:
  - 01-lineup, 02-lock-screen, 03-home-screen, 04-states, 05-configuration.
  - Rendered with Inter standing in for SF Pro, so text widths are close but not exact. Measure from HANDOFF.md, not from pixels.
- rendered/: the same five boards as plain, self-contained HTML. Open in any browser, no runtime needed.
