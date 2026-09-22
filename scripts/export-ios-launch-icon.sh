#!/bin/bash
set -euo pipefail

# Render the native launch-screen artwork from the same layered source as the app icon.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
xcode_developer="${DEVELOPER_DIR:-$(xcode-select -p)}"
icon_tool="$xcode_developer/../Applications/Icon Composer.app/Contents/Executables/ictool"
output_dir="$repo_root/iOS/App/Assets.xcassets/LaunchIcon.imageset"

if [[ ! -x "$icon_tool" ]]; then
    echo "Icon Composer is required. Set DEVELOPER_DIR to an Xcode installation containing it." >&2
    exit 1
fi

mkdir -p "$output_dir"
for appearance in light dark; do
    rendition=Default
    if [[ "$appearance" == dark ]]; then rendition=Dark; fi
    for scale in 1 2 3; do
        "$icon_tool" "$repo_root/AIQuota/AppIcon.icon" --export-image \
            --output-file "$output_dir/$appearance@${scale}x.png" \
            --platform iOS --rendition "$rendition" \
            --width 112 --height 112 --scale "$scale" --design-generation 27
    done
done
