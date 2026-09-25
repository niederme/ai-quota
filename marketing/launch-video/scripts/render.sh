#!/usr/bin/env bash
# Renders the 4K master, then derives web versions and the poster from it.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out
node scripts/make-audio.mjs
npx remotion render src/index.ts Launch16x9 out/aiquota-launch-4k.mp4 --concurrency=50%
ffmpeg -v error -y -i out/aiquota-launch-4k.mp4 -vf scale=1920:1080:flags=lanczos \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart out/aiquota-launch-1080p.mp4
ffmpeg -v error -y -i out/aiquota-launch-4k.mp4 -vf scale=1920:1080:flags=lanczos \
  -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p -an -movflags +faststart out/aiquota-launch-1080p-muted.mp4
npx remotion still src/index.ts Launch16x9 out/aiquota-launch-poster.png --frame=$(node -p "require('./src/beats.json').duration - 1")
ls -lh out/aiquota-launch-*
