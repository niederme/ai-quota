#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="${ROOT_DIR}/docs"
PORT="${PORT:-8129}"
HOST="${HOST:-127.0.0.1}"
BASE_URL="http://${HOST}:${PORT}"

SERVER_LOG="$(mktemp "${TMPDIR:-/tmp}/aiquota-site-check.XXXXXX.log")"
cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  rm -f "$SERVER_LOG"
}
trap cleanup EXIT

cd "$ROOT_DIR"
python3 -m http.server "$PORT" --bind "$HOST" --directory "$SITE_DIR" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "$BASE_URL/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.3
done

check_contains() {
  local path="$1"
  local expected="$2"
  local body
  body="$(curl -fsS "$BASE_URL$path")"
  if [[ "$body" != *"$expected"* ]]; then
    echo "Expected '$expected' in $path"
    exit 1
  fi
}

check_status() {
  local path="$1"
  curl -fsS "$BASE_URL$path" >/dev/null
}

check_contains "/" "Know your limits before they break your flow."
check_contains "/releases/" "<h1>Releases</h1>"
check_contains "/privacy/" "<h1 class=\"policy-title\">Privacy Policy</h1>"
check_contains "/terms/" "<h1 class=\"policy-title\">Terms of Service</h1>"
check_contains "/accessibility/" "<h1 class=\"policy-title\">Accessibility</h1>"

check_status "/site.css"
check_status "/site.js"
check_status "/assets/aiquota-demo-inline.mp4"
check_status "/assets/aiquota-video-poster.png"

check_contains "/" "hero-demo-media"
python3 - "$SITE_DIR/site.css" <<'PY'
from pathlib import Path
import re
import sys

css = Path(sys.argv[1]).read_text()

def selector_block(selector: str) -> str:
    match = re.search(re.escape(selector) + r"\s*\{([^}]*)\}", css)
    if not match:
        raise SystemExit(f"Missing selector block: {selector}")
    return match.group(1)

def expect(selector: str, pattern: str, message: str) -> None:
    block = selector_block(selector)
    if not re.search(pattern, block):
        raise SystemExit(f"Missing {message} in {selector}")

color = r"(?:white|#fff|#ffffff)\s*,\s*(?:black|#000|#000000)"

for selector in (".visual-card", ".visual-frame", ".hero-demo-media"):
    expect(selector, r"isolation\s*:\s*isolate", "isolation")
    expect(
        selector,
        rf"-webkit-mask-image\s*:\s*-webkit-radial-gradient\(\s*{color}\s*\)",
        "webkit mask",
    )
    expect(
        selector,
        rf"mask-image\s*:\s*radial-gradient\(\s*{color}\s*\)",
        "mask-image",
    )

expect(".hero-demo-media", r"border-radius\s*:\s*inherit", "inherited border radius")
expect(".hero-demo-video", r"object-position\s*:\s*center\s+top", "object-position")
PY

echo "Site smoke check passed."
