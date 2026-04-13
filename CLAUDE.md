# AIQuota — Claude Code Notes

## Building

`.xcodeproj` is not committed. After cloning, run:

```bash
xcodegen generate
open AIQuota.xcodeproj
```

Build and run the `AIQuota` scheme targeting **My Mac**.

---

## Releasing

The full release script is at `scripts/release.sh`. It handles zipping, signing, appcast generation, and GitHub release creation.

### Steps

1. **Version bump** — update `MARKETING_VERSION` in `project.yml` (not `project.pbxproj` — that file is generated):
   ```bash
   # Edit project.yml manually, then regenerate:
   xcodegen generate
   ```
   Commit this: `chore: bump MARKETING_VERSION to X.Y.NEW`

2. **Build bump** — increment `CURRENT_PROJECT_VERSION` before every Sparkle release:
   ```bash
   ./scripts/bump-build.sh
   ```

3. **Archive in Xcode** — `Product → Archive → Distribute App → Direct Distribution → Export`
   Export the notarized `.app` to `~/Desktop/AIQuota.app`

4. **Run the release script** (from repo root):
   ```bash
   ./scripts/release.sh X.Y.NEW
   ```
   The script will open a text editor to edit release notes, then zip, sign, update appcast, create GitHub release, and push.

5. **Verify the website release page is in sync with GitHub**:
   ```bash
   ./scripts/check-site-pages.sh
   ```
   If the release page drifted, update `docs/releases/index.html` before pushing.

6. **Commit & push** the updated `appcast.xml` and any site changes:
   ```bash
   git add appcast.xml docs/releases/index.html && git commit -m "chore: update release metadata for vX.Y.NEW" && git push
   ```

> **Important:** `appcast.xml` must also be uploaded as a release asset on the GitHub release — Sparkle fetches it from `releases/latest/download/appcast.xml`. The `release.sh` script does this automatically. If doing a manual release, run:
> ```bash
> gh release upload vX.Y.NEW appcast.xml --clobber -R niederme/ai-quota
> ```

### Notes

- `sign_update` is auto-detected from Xcode DerivedData — no manual setup needed after first build
- The appcast `<sparkle:version>` is the `CFBundleVersion` from the exported `.app` (not the marketing version), so `CURRENT_PROJECT_VERSION` must increase on every release
- ZIP format is required (not DMG) — Sparkle sandboxed apps get "installer launch" errors with DMGs
- GitHub release and appcast always use the tag `vX.Y.Z` format
- **Before running `release.sh`**, draft user-facing release notes and get approval — the script opens an editor immediately and raw commit messages are not acceptable release notes
- **Release notes must be shared in a code block** for approval before running the script
- **Release notes ordering** — weight bullets by user impact: features affecting the most users first, one-time experiences (onboarding polish) last

---

## Worktrees

When starting any session in a git worktree, immediately open the Xcode project from that worktree's path:

```bash
open /path/to/worktree/AIQuota.xcodeproj
```

This ensures Xcode is pointing at the right copy of the project, not the main checkout.

---

## Code Conventions

- Branded purple: `Color(red: 0.62, green: 0.22, blue: 0.93)` — use `.foregroundColor(...)`, not `.foregroundStyle(.accent)` or `.foregroundStyle(.accentColor)` (both fail to compile)
- Never use `git stash` — always create a branch/worktree for WIP so nothing gets lost between releases
- PR descriptions: no `🤖 Generated with Claude Code` footer

---

## Auth & Platform Quirks

- **Keychain survives uninstall** — never use Keychain for fresh-install sentinels; use `UserDefaults.standard` (AppZapper and manual reinstalls wipe it)
- **WKWebView default store survives uninstall** — clear `WKWebsiteDataStore.default()` explicitly on fresh install alongside any Keychain wipe
- **`async let _ = expr`** — implicit await happens at scope end, *after* surrounding synchronous code; use `withTaskGroup` when all tasks must complete before proceeding
- **`URLSession.data(for:)` not `dataTask`** — callback-based `dataTask` bypasses Swift cooperative Task cancellation; always use the async API or spinners will hang when the enclosing Task is cancelled
