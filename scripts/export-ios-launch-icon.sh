#!/bin/bash
set -euo pipefail

# Keep launch and onboarding images aligned with the authoritative Icon Composer app icon.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
xcode_developer="${DEVELOPER_DIR:-$(xcode-select -p)}"
icon_tool="$xcode_developer/../Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ ! -x "$icon_tool" ]]; then
    echo "Icon Composer is required. Set DEVELOPER_DIR to an Xcode installation containing it." >&2
    exit 1
fi

python3 "$repo_root/scripts/generate-ios-splash.py"

# Onboarding uses a 132-point image at 2x.
"$icon_tool" "$repo_root/AIQuota/AppIcon.icon" --export-image \
    --output-file "$repo_root/iOS/App/Assets.xcassets/onboarding-icon.imageset/icon.png" \
    --platform iOS --rendition Default --width 132 --height 132 --scale 2 --design-generation 27
"$icon_tool" "$repo_root/AIQuota/AppIcon.icon" --export-image \
    --output-file "$repo_root/iOS/App/Assets.xcassets/onboarding-icon.imageset/icon-dark.png" \
    --platform iOS --rendition Dark --width 132 --height 132 --scale 2 --design-generation 27
