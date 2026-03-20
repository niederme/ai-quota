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

1. **Version bump** — update `MARKETING_VERSION` in `AIQuota.xcodeproj/project.pbxproj` (both Debug and Release entries):
   ```bash
   sed -i '' 's/MARKETING_VERSION = X.Y.Z/MARKETING_VERSION = X.Y.NEW/g' AIQuota.xcodeproj/project.pbxproj
   ```
   Commit this: `chore: bump MARKETING_VERSION to X.Y.NEW`

2. **Archive in Xcode** — `Product → Archive → Distribute App → Direct Distribution → Export`
   Export the notarized `.app` to `~/Desktop/AIQuota.app`

3. **Run the release script** (from repo root):
   ```bash
   ./scripts/release.sh X.Y.NEW
   ```
   The script will open a text editor to edit release notes, then zip, sign, update appcast, create GitHub release, and push.

4. **Commit & push** the updated `appcast.xml`:
   ```bash
   git add appcast.xml && git commit -m "chore: update appcast for vX.Y.NEW" && git push
   ```

> **Important:** `appcast.xml` must also be uploaded as a release asset on the GitHub release — Sparkle fetches it from `releases/latest/download/appcast.xml`. The `release.sh` script does this automatically. If doing a manual release, run:
> ```bash
> gh release upload vX.Y.NEW appcast.xml --clobber -R niederme/ai-quota
> ```

### Notes

- `sign_update` is auto-detected from Xcode DerivedData — no manual setup needed after first build
- The appcast `<sparkle:version>` is the `CFBundleVersion` from the exported `.app` (not the marketing version)
- ZIP format is required (not DMG) — Sparkle sandboxed apps get "installer launch" errors with DMGs
- GitHub release and appcast always use the tag `vX.Y.Z` format
