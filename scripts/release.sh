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
APPCAST="$(dirname "$0")/../appcast.xml"

echo "▶ Building DMG for ${TAG}…"
rm -rf /tmp/AIQuota-dmg-staging
mkdir /tmp/AIQuota-dmg-staging
cp -R /Applications/AIQuota.app /tmp/AIQuota-dmg-staging/
ln -s /Applications /tmp/AIQuota-dmg-staging/Applications
hdiutil create "$DMG" -volname "AIQuota" -srcfolder /tmp/AIQuota-dmg-staging -ov -format UDZO

echo "▶ Signing DMG with Sparkle Ed25519 key…"
SIGNATURE=$("${SPARKLE}/sign_update" "$DMG" 2>/dev/null | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')
LENGTH=$(wc -c < "$DMG" | tr -d ' ')
echo "  Signature: ${SIGNATURE}"
echo "  Length:    ${LENGTH}"

echo "▶ Generating appcast.xml…"
BUILD=$(git -C "$(dirname "$0")/.." rev-list --count HEAD)
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/AIQuota.dmg"

cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>AIQuota</title>
        <link>https://github.com/${REPO}</link>
        <description>AIQuota release feed</description>
        <item>
            <title>Version ${VERSION}</title>
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

echo "▶ Creating/updating GitHub release ${TAG}…"
if gh release view "$TAG" -R "$REPO" &>/dev/null; then
    gh release upload "$TAG" "$DMG" "$APPCAST" --clobber -R "$REPO"
else
    gh release create "$TAG" "$DMG" "$APPCAST" \
        --title "AIQuota ${VERSION}" \
        --notes "See commits for changes." \
        -R "$REPO"
fi

echo "✓ Done. Release ${TAG} is live."
