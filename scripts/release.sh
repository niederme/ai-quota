#!/bin/bash
# release.sh — build DMG, sign for Sparkle, generate appcast, push to GitHub
#
# Usage:
#   ./scripts/release.sh <marketing_version>
#   e.g. ./scripts/release.sh 1.1
#
# Prerequisites:
#   - Sparkle tools in PATH or at $SPARKLE_TOOLS (default: /tmp/sparkle-tools/bin)
#   - App built and exported to /Applications/AIQuota.app
#   - gh CLI authenticated
set -euo pipefail

VERSION="${1:?Usage: release.sh <version>}"
TAG="v${VERSION}"
SPARKLE="${SPARKLE_TOOLS:-/tmp/sparkle-tools/bin}"
REPO="niederme/ai-quota"
DMG="/tmp/AIQuota.dmg"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="${REPO_ROOT}/appcast.xml"

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

echo "▶ Opening release notes for editing (close editor to continue)…"
"${EDITOR:-open -W -a TextEdit}" "$NOTES_FILE"

RELEASE_NOTES=$(cat "$NOTES_FILE")
rm "$NOTES_FILE"

# ── Build DMG ─────────────────────────────────────────────────────────────────
echo "▶ Building DMG for ${TAG}…"
rm -rf /tmp/AIQuota-dmg-staging
mkdir /tmp/AIQuota-dmg-staging
cp -R /Applications/AIQuota.app /tmp/AIQuota-dmg-staging/
ln -s /Applications /tmp/AIQuota-dmg-staging/Applications
hdiutil create "$DMG" -volname "AIQuota" -srcfolder /tmp/AIQuota-dmg-staging -ov -format UDZO

# ── Sign DMG ──────────────────────────────────────────────────────────────────
echo "▶ Signing DMG with Sparkle Ed25519 key…"
SIGNATURE=$("${SPARKLE}/sign_update" "$DMG" 2>/dev/null | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')
LENGTH=$(wc -c < "$DMG" | tr -d ' ')
echo "  Signature: ${SIGNATURE}"
echo "  Length:    ${LENGTH}"

# ── Generate appcast.xml ──────────────────────────────────────────────────────
echo "▶ Generating appcast.xml…"
BUILD=$(git -C "$REPO_ROOT" rev-list --count HEAD)
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/AIQuota.dmg"

# Convert markdown notes to simple HTML for Sparkle's in-app display
NOTES_HTML=$(echo "$RELEASE_NOTES" | sed \
  's|## \(.*\)|<h2>\1</h2>|g' \
  | sed 's|^- \(.*\)|<li>\1</li>|g' \
  | sed '/^<li>/{ x; s/.*//; x; }' \
  | tr '\n' ' ')

cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>AIQuota</title>
        <link>https://github.com/${REPO}</link>
        <description>AIQuota release feed</description>
        <item>
            <title>Version ${VERSION}</title>
            <description><![CDATA[${NOTES_HTML}]]></description>
            <sparkle:releaseNotesLink>https://github.com/${REPO}/releases/tag/${TAG}</sparkle:releaseNotesLink>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${SIGNATURE}"
                length="${LENGTH}"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF

# ── Push to GitHub ────────────────────────────────────────────────────────────
echo "▶ Creating/updating GitHub release ${TAG}…"
if gh release view "$TAG" -R "$REPO" &>/dev/null; then
    gh release edit "$TAG" --notes "$RELEASE_NOTES" -R "$REPO"
    gh release upload "$TAG" "$DMG" "$APPCAST" --clobber -R "$REPO"
else
    gh release create "$TAG" "$DMG" "$APPCAST" \
        --title "AIQuota ${VERSION}" \
        --notes "$RELEASE_NOTES" \
        -R "$REPO"
fi

echo "✓ Done. Release ${TAG} is live."
