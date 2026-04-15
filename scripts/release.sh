#!/bin/bash
# release.sh — build ZIP, sign for Sparkle, generate appcast, push to GitHub
#
# Usage:
#   ./scripts/release.sh <marketing_version>
#   e.g. ./scripts/release.sh 1.5
#
# Pre-release checklist (do these BEFORE running this script):
#   1. Ask Claude: "prepare release notes for X.X" — get user-facing summary
#   2. Update README.md — features, requirements, roadmap
#   3. Bump MARKETING_VERSION in project.yml
#   4. Run ./scripts/bump-build.sh so CFBundleVersion increases for Sparkle
#   5. Archive: Product → Archive in Xcode
#   6. Export the notarized .app to ~/Desktop/AIQuota.app
#      (Distribute App → Direct Distribution → Export)
#   7. Commit & push all changes to main
#   Then run this script and paste the release notes into the editor when it opens.
#
# Post-release checklist (do these AFTER this script succeeds):
#   1. Make sure docs/releases/index.html reflects the latest GitHub releases
#   2. Run ./scripts/check-site-pages.sh to verify the site, including release-page sync
#   3. Commit & push the appcast/site updates to main so the website deploy workflow publishes them
#
# Prerequisites:
#   - Sparkle tools in PATH or at $SPARKLE_TOOLS (default: /tmp/sparkle-tools/bin)
#   - App exported from Xcode to ~/Desktop/AIQuota.app
#   - gh CLI authenticated
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"

VERSION="${1:?Usage: release.sh <version>}"
TAG="v${VERSION}"

# Auto-detect sign_update: prefer $SPARKLE_TOOLS, then DerivedData, then PATH
if [ -n "${SPARKLE_TOOLS:-}" ]; then
    SPARKLE="$SPARKLE_TOOLS"
else
    DERIVED=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/Sparkle/bin/sign_update" 2>/dev/null | grep -v old_dsa | head -1)
    if [ -n "$DERIVED" ]; then
        SPARKLE="$(dirname "$DERIVED")"
    elif command -v sign_update &>/dev/null; then
        SPARKLE="$(dirname "$(command -v sign_update)")"
    else
        echo "✗ sign_update not found. Set SPARKLE_TOOLS or build the project in Xcode first."
        exit 1
    fi
fi
echo "▶ Using Sparkle tools: ${SPARKLE}"
REPO="niederme/ai-quota"
ZIP="/tmp/AIQuota.zip"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="${REPO_ROOT}/appcast.xml"

# ── Locate exported .app on Desktop ──────────────────────────────────────────
APP_SRC="$HOME/Desktop/AIQuota.app"
if [ ! -d "$APP_SRC" ]; then
    echo "✗ ~/Desktop/AIQuota.app not found. Export from Xcode first:"
    echo "  Product → Archive → Distribute App → Direct Distribution → Export"
    exit 1
fi
echo "▶ Using app: ${APP_SRC}"

# ── Draft release notes from git commits since last tag ──────────────────────
LAST_TAG=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo "")
NOTES_FILE=$(mktemp /tmp/release-notes.XXXXXX.md)

{
  echo "## What's New in ${VERSION}"
  echo ""
  if [ -n "$LAST_TAG" ]; then
    git -C "$REPO_ROOT" log "${LAST_TAG}..HEAD" --pretty=format:"- %s" --no-merges
  else
    git -C "$REPO_ROOT" log --pretty=format:"- %s" --no-merges | head -20
  fi
  echo ""
} > "$NOTES_FILE"

# Release notes style guide:
#   - Write for users, not developers — benefits, not implementation details
#   - 3-5 bullet points max, bold lead phrase, plain-English description
#   - Bad:  "fix: rolling window drift no longer triggers spurious notifications"
#   - Good: "**Quieter notifications** — fixed a bug where alerts fired on every refresh"
echo "▶ Opening release notes for editing (close editor to continue)…"
if [ -n "${EDITOR:-}" ]; then
    "$EDITOR" "$NOTES_FILE"
else
    open -W -a TextEdit "$NOTES_FILE"
fi

RELEASE_NOTES=$(cat "$NOTES_FILE")
rm "$NOTES_FILE"

# ── Attach screenshot if present on Desktop ───────────────────────────────────
if [ -z "$SCREENSHOT_SRC" ] || [ ! -f "$SCREENSHOT_SRC" ]; then
    echo ""
    read -r -p "No screenshot at ~/Desktop/AIQuota-${VERSION}.png. Add one now and press Enter, or type 's' to skip: " SCREENSHOT_REPLY
    if [[ "$SCREENSHOT_REPLY" == "s" || "$SCREENSHOT_REPLY" == "S" ]]; then
        SCREENSHOT_SRC=""
    else
        SCREENSHOT_SRC=$(find "$HOME/Desktop" -maxdepth 1 -iname "AIQuota-${VERSION}.png" -o -iname "AIQuota ${VERSION}.png" 2>/dev/null | head -1)
        SCREENSHOT_SRC="${SCREENSHOT_SRC:-}"
        SCREENSHOT_FILENAME=$(basename "${SCREENSHOT_SRC:-AIQuota-${VERSION}.png}")
        SCREENSHOT_UPLOAD_NAME="${SCREENSHOT_FILENAME// /.}"
        SCREENSHOT_URL="https://github.com/${REPO}/releases/download/${TAG}/${SCREENSHOT_UPLOAD_NAME}"
    fi
    if [ -z "$SCREENSHOT_SRC" ] || [ ! -f "$SCREENSHOT_SRC" ]; then
        echo "✗ Still not found — skipping screenshot."
        SCREENSHOT_SRC=""
    fi
fi

if [ -f "${SCREENSHOT_SRC:-}" ]; then
    echo "▶ Screenshot found — preparing for upload…"
    SCREENSHOT_UPLOAD_PATH="/tmp/${SCREENSHOT_UPLOAD_NAME}"
    cp "$SCREENSHOT_SRC" "$SCREENSHOT_UPLOAD_PATH"
    SCREENSHOT_SRC="$SCREENSHOT_UPLOAD_PATH"
    RELEASE_NOTES="${RELEASE_NOTES}

![Screenshot](${SCREENSHOT_URL})"
fi

# ── Build ZIP ─────────────────────────────────────────────────────────────────
# ZIP is required for sandboxed Sparkle apps — DMG triggers "installer launch" errors.
echo "▶ Building ZIP for ${TAG}…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_SRC" "$ZIP"

# ── Sign ZIP ──────────────────────────────────────────────────────────────────
echo "▶ Signing ZIP with Sparkle Ed25519 key…"
SIGNATURE=$("${SPARKLE}/sign_update" "$ZIP" 2>/dev/null | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')
LENGTH=$(wc -c < "$ZIP" | tr -d ' ')
echo "  Signature: ${SIGNATURE}"
echo "  Length:    ${LENGTH}"

# ── Generate appcast.xml ──────────────────────────────────────────────────────
echo "▶ Generating appcast.xml…"
BUILD=$(defaults read "${APP_SRC}/Contents/Info" CFBundleVersion 2>/dev/null || echo "")
if [ -z "$BUILD" ]; then
    echo "✗ Could not read CFBundleVersion from ${APP_SRC}."
    exit 1
fi

CURRENT_APPCAST_BUILD=$(grep -o '<sparkle:version>[^<]*</sparkle:version>' "$APPCAST" 2>/dev/null | head -1 | sed 's#<sparkle:version>##;s#</sparkle:version>##')
if [[ -n "$CURRENT_APPCAST_BUILD" && "$BUILD" =~ ^[0-9]+$ && "$CURRENT_APPCAST_BUILD" =~ ^[0-9]+$ ]]; then
    if [ "$BUILD" -le "$CURRENT_APPCAST_BUILD" ]; then
        echo "✗ Exported app build ${BUILD} is not newer than current appcast build ${CURRENT_APPCAST_BUILD}."
        echo "  Run ./scripts/bump-build.sh, archive again, and export a fresh ~/Desktop/AIQuota.app before releasing."
        exit 1
    fi
fi
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/AIQuota.zip"
SCREENSHOT_SRC=$(find "$HOME/Desktop" -maxdepth 1 -iname "AIQuota-${VERSION}.png" -o -iname "AIQuota ${VERSION}.png" 2>/dev/null | head -1)
SCREENSHOT_SRC="${SCREENSHOT_SRC:-}"
SCREENSHOT_FILENAME=$(basename "${SCREENSHOT_SRC:-AIQuota-${VERSION}.png}")
SCREENSHOT_UPLOAD_NAME="${SCREENSHOT_FILENAME// /.}"
SCREENSHOT_URL="https://github.com/${REPO}/releases/download/${TAG}/${SCREENSHOT_UPLOAD_NAME}"

# Convert markdown notes to styled HTML for Sparkle's in-app WebView
NOTES_HTML=$(echo "$RELEASE_NOTES" | sed \
  's|## \(.*\)|<h2>\1</h2>|g' \
  | sed 's|^- \(.*\)|<li>\1</li>|g' \
  | sed 's|\*\*\([^*]*\)\*\*|<strong>\1</strong>|g' \
  | tr '\n' ' ' \
  | sed 's|<li>|<ul><li>|' \
  | sed 's|</li> <h2>|</li></ul><h2>|g' \
  | sed 's|</li> *$|</li></ul>|')

cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>AIQuota</title>
        <link>https://github.com/${REPO}</link>
        <description>AIQuota release feed</description>
        <item>
            <title>Version ${VERSION}</title>
            <description><![CDATA[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    font-family: -apple-system, sans-serif;
    font-size: 13px;
    color: #e0e0e0;
    background: #1e1e1e;
    margin: 16px 20px;
    line-height: 1.5;
  }
  h2 {
    font-size: 15px;
    font-weight: 600;
    color: #ffffff;
    margin: 0 0 10px 0;
  }
  ul {
    margin: 4px 0 0 0;
    padding-left: 18px;
  }
  li {
    margin-bottom: 5px;
    color: #cccccc;
  }
  li strong {
    color: #ffffff;
  }
</style>
</head>
<body>
${NOTES_HTML}
</body>
</html>
]]></description>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${SIGNATURE}"
                length="${LENGTH}"
                type="application/zip"/>
        </item>
    </channel>
</rss>
EOF

# ── Push to GitHub ────────────────────────────────────────────────────────────
echo "▶ Creating/updating GitHub release ${TAG}…"
EXTRA_ASSETS=()
[ -n "${SCREENSHOT_SRC:-}" ] && [ -f "${SCREENSHOT_SRC:-}" ] && EXTRA_ASSETS+=("$SCREENSHOT_SRC")

if gh release view "$TAG" -R "$REPO" &>/dev/null; then
    gh release edit "$TAG" --notes "$RELEASE_NOTES" -R "$REPO"
    gh release upload "$TAG" "$ZIP" "$APPCAST" "${EXTRA_ASSETS[@]}" --clobber -R "$REPO"
else
    gh release create "$TAG" "$ZIP" "$APPCAST" "${EXTRA_ASSETS[@]}" \
        --title "AIQuota ${VERSION}" \
        --notes "$RELEASE_NOTES" \
        -R "$REPO"
fi

echo "✓ Done. Release ${TAG} is live."
