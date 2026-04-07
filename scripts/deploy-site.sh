#!/usr/bin/env bash
set -euo pipefail

# Deploy the static marketing site from docs/ over SSH + rsync.
# Defaults are set for aiquota.app and can be overridden via env vars:
#   DEPLOY_HOST
#   DEPLOY_USER
#   DEPLOY_PATH
# Optional env vars:
#   DEPLOY_PORT
#   DRY_RUN
#   SITE_URL
#   DEPLOY_IDENTITY_FILE

DEPLOY_HOST="${DEPLOY_HOST:-ssh.suckahs.org}"
DEPLOY_USER="${DEPLOY_USER:-suckahs}"
DEPLOY_PATH="${DEPLOY_PATH:-/home2/suckahs/public_html/aiquota}"

DEPLOY_PORT="${DEPLOY_PORT:-22}"
DRY_RUN="${DRY_RUN:-0}"
SITE_URL="${SITE_URL:-https://aiquota.app}"
DEPLOY_IDENTITY_FILE="${DEPLOY_IDENTITY_FILE:-}"

RSYNC_ARGS=(
  -avz
  --delete
  --exclude .DS_Store
  --exclude .git/
)

if [[ "$DRY_RUN" == "1" ]]; then
  RSYNC_ARGS+=(--dry-run)
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aiquota-site-deploy.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp docs/index.html "$STAGING_DIR/"
cp docs/site.css "$STAGING_DIR/"
cp docs/site.js "$STAGING_DIR/"
cp -R docs/assets "$STAGING_DIR/"

PUBLIC_DIRS=(
  accessibility
  privacy
  releases
  terms
)

for dir in "${PUBLIC_DIRS[@]}"; do
  if [[ -d "docs/$dir" ]]; then
    cp -R "docs/$dir" "$STAGING_DIR/"
  fi
done

css_cache_bust="$(shasum -a 256 "$STAGING_DIR/site.css" | awk '{print substr($1, 1, 12)}')"
js_cache_bust="$(shasum -a 256 "$STAGING_DIR/site.js" | awk '{print substr($1, 1, 12)}')"

find "$STAGING_DIR" -name '*.html' -print0 | xargs -0 perl -0pi -e \
  "s#href=\"((?:\\.\\./)*/?site\\.css)(?:\\?v=[^\"]+)?\"#href=\"\$1?v=${css_cache_bust}\"#g;
   s#src=\"((?:\\.\\./)*/?site\\.js)(?:\\?v=[^\"]+)?\"#src=\"\$1?v=${js_cache_bust}\"#g"

echo "Deploying ${SITE_URL} with cache-busted assets: site.css?v=${css_cache_bust}, site.js?v=${js_cache_bust}"

REMOTE="${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH%/}/"
SSH_CMD=(
  ssh
  -p "$DEPLOY_PORT"
  -o IdentityAgent=none
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=publickey
)

if [[ -n "$DEPLOY_IDENTITY_FILE" ]]; then
  SSH_CMD+=(-i "$DEPLOY_IDENTITY_FILE")
elif [[ -f "${HOME}/.ssh/aiquota_deploy_nopass" ]]; then
  SSH_CMD+=(-i "${HOME}/.ssh/aiquota_deploy_nopass")
elif [[ -f "${HOME}/.ssh/aiquota_deploy" ]]; then
  SSH_CMD+=(-i "${HOME}/.ssh/aiquota_deploy")
fi

printf -v RSYNC_SSH_CMD '%q ' "${SSH_CMD[@]}"
RSYNC_SSH_CMD="${RSYNC_SSH_CMD% }"

"${SSH_CMD[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" "mkdir -p '${DEPLOY_PATH%/}'"

rsync "${RSYNC_ARGS[@]}" -e "$RSYNC_SSH_CMD" \
  "${STAGING_DIR}/" \
  "$REMOTE"

echo "Deploy complete -> $REMOTE"
