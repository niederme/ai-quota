# Homepage FAQ Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recompose the homepage FAQ into a single full-width panel with an integrated header and clearer separation from the hero.

**Architecture:** Keep the existing static-site structure and FAQ copy, but change the section markup from a split two-column layout to a single shell that contains its own heading block plus accordion rows. Update the site CSS so spacing, width, and mobile behavior support the new composition without extra JavaScript.

**Tech Stack:** Static HTML, CSS, existing shell smoke script, live preview in BrowserSync

---

### Task 1: Add a structural smoke check for the new FAQ layout

**Files:**
- Modify: `scripts/check-site-pages.sh`

- [ ] **Step 1: Write the failing test**

Add assertions for the new integrated FAQ structure:
- homepage contains `faq-panel`
- homepage contains `faq-panel-header`
- homepage no longer contains `faq-layout`

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/check-site-pages.sh`
Expected: FAIL because the homepage still uses the old split layout classes.

### Task 2: Recompose the FAQ section markup and styling

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/site.css`

- [ ] **Step 1: Write minimal implementation**

Update the FAQ section markup to:
- use one full-width shell
- move the kicker, heading, and intro inside the shell header
- keep the existing FAQ item copy and accordion behavior

Update CSS to:
- increase top spacing above the section
- remove the split grid layout
- style the integrated header row and divider
- keep mobile behavior clean

- [ ] **Step 2: Run smoke test to verify it passes**

Run: `./scripts/check-site-pages.sh`
Expected: PASS

### Task 3: Verify in the browser

**Files:**
- Inspect only: `http://localhost:8127/`

- [ ] **Step 1: Refresh the live preview**

Use the active live-reload server to confirm the section appears as a full-width block under the hero.

- [ ] **Step 2: Capture evidence**

Take a current screenshot or DOM check showing:
- one integrated FAQ panel
- larger vertical gap below the hero
- no left/right split composition
