# Website development

The marketing site lives in `docs/`. Run commands from the repository root.

## Site Structure

The site is plain HTML, CSS, and JavaScript with no build step.

- Pages: `docs/index.html` (Overview), `docs/releases/index.html`, `docs/faq/index.html`, and the legal pages under `docs/privacy/`, `docs/terms/`, and `docs/accessibility/`. Every page shares the same nav and footer markup.
- `docs/site.css` is layered: the AIQuota design system's `tokens.css` and `bundle.css` verbatim (dark first, `[data-theme="light"]` overrides), then a site layer for page layout. Change colours in the token layer, not in page rules.
- `docs/site.js` handles the System / Light / Dark picker (stored as `aiquota-theme`; a value saved under the 1.x `aiquota-docs-theme` key is carried over), the narrow-screen menu, quota dial animation, sample notice dismissal, and the one-open-at-a-time FAQ.
- The pre-paint script in each page's `<head>` sets `data-theme` before first paint, so keep it in sync across pages.
- "Get the iPhone app" links carry `data-ios-app-link`; point them at the App Store URL once it exists.

### Releases page

The "Latest release" panel must match the newest stable GitHub release (`AIQuota x.y.z`, `Download x.y.z`, the tag URL, and the publish date), and the next three releases appear as `Version x.y.z` cards. `scripts/check-site-pages.sh` fails the deploy when they drift. When a release ships, move the previous latest into the "Previous releases" grid and update the panel.

## Website Preview

The lightweight website for `aiquota.app` lives in `docs/`.

From the repo root:

```bash
make
```

That serves `docs/` on all interfaces, opens the site locally, and prints:

- a `.local` URL for this Mac
- a LAN URL for other devices on the same network

Default preview port is `8123`. If that port is already in use, `make dev` automatically picks the next available port.

Localhost-only preview:

```bash
make dev-local
```

Worktree-friendly preview:

```bash
make dev-thread
```

`make dev-thread` starts from `8124` so the main checkout can keep `8123`.

Project worktrees should live under repo-local `.worktrees/`.

### Live Reload

Use `make dev-live` for the standard live-reload preview. The underlying switch is `LIVE=1`, which is also available for the thread and local-only variants:

```bash
make dev-live
make dev-live-thread
make dev-local LIVE=1
```

Live reload watches:

- `docs/**/*.html`
- `docs/**/*.css`
- `docs/assets/**/*`

Requirements for live reload:

- Node.js with `npx` available
- a Node runtime that supports `node:path`
- recommended local version: Node 24

### Website Deploy

Pushing to `main` triggers the website deploy workflow automatically, and you can also run the same deploy manually with `workflow_dispatch` in GitHub Actions. The workflow:

- minifies `docs/site.css` and `docs/site.js`
- smoke-checks the public site pages before deploy, including release-page sync against GitHub
- stages the `docs/` site with cache-busted asset URLs
- syncs the staged site to the remote host over SSH
- normalizes remote file permissions so shared hosting serves the site correctly

For manual or local deploys, use:

```bash
./scripts/deploy-site.sh
```

Smoke-check the site before deploy:

```bash
./scripts/check-site-pages.sh
```

Default deploy settings in [`scripts/deploy-site.sh`](../scripts/deploy-site.sh):

- `DEPLOY_HOST=ssh.suckahs.org`
- `DEPLOY_USER=suckahs`
- `DEPLOY_PATH=/home2/suckahs/public_html/aiquota`
- `SITE_URL=https://aiquota.app`

Optional overrides:

- `DEPLOY_PORT`
- `DRY_RUN=1`
- `DEPLOY_IDENTITY_FILE`

GitHub Actions expects the repository secret `SSH_PRIVATE_KEY` to contain the deploy key for `suckahs@ssh.suckahs.org`.
