#!/bin/bash
# bump-build.sh — increment CURRENT_PROJECT_VERSION in project.yml and regenerate
set -e

PROJECT="$(dirname "$0")/../project.yml"

# Read current build number
CURRENT=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT" | sed 's/.*CURRENT_PROJECT_VERSION: *"\([0-9]*\)".*/\1/')
NEXT=$((CURRENT + 1))

# Update project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT\"/CURRENT_PROJECT_VERSION: \"$NEXT\"/" "$PROJECT"

echo "Build number: $CURRENT → $NEXT"

# Regenerate Xcode project
xcodegen generate --spec "$PROJECT"

echo "Done. Archive in Xcode to produce build $NEXT."
