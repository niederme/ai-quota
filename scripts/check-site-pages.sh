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
check_contains "/" "Menu bar gauges for Codex and Claude Code across 5-hour and 7-day windows"
check_contains "/" "Desktop widgets for background visibility"
check_contains "/" "Reset timers, plan details, and warning states"
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
expect(
    ".hero h1",
    r"font-size\s*:\s*clamp\(\s*46px\s*,\s*6\.8vw\s*,\s*72px\s*\)",
    "hero headline clamp",
)

media_1080 = re.search(
    r"@media\s*\((?:max-width:\s*1080px|width\s*<=\s*1080px)\)\s*\{(.*?)\}\s*@media",
    css,
    re.S,
)
if not media_1080:
    raise SystemExit("Missing 1080px media query")

media_1080_css = media_1080.group(1)

def expect_in_css(source: str, pattern: str, message: str) -> None:
    if not re.search(pattern, source, re.S):
        raise SystemExit(f"Missing {message}")

expect_in_css(media_1080_css, r"\.hero-grid\s*\{[^}]*gap\s*:\s*30px", "mid-range hero gap")
expect_in_css(
    media_1080_css,
    r"\.hero-visual\s*\{[^}]*width\s*:\s*min\(\s*100%\s*,\s*clamp\(\s*520px\s*,\s*68vw\s*,\s*620px\s*\)\s*\)",
    "mid-range hero visual width clamp",
)
expect_in_css(
    media_1080_css,
    r"\.hero-visual\s*\{[^}]*justify-self\s*:\s*center",
    "mid-range hero visual centering",
)
expect_in_css(
    media_1080_css,
    r"\.hero-visual\s*\{[^}]*margin-inline\s*:\s*auto",
    "mid-range hero visual margin centering",
)
expect_in_css(
    media_1080_css,
    r"\.hero-copy\s*\{[^}]*max-width\s*:\s*640px",
    "mid-range hero copy max width",
)
expect_in_css(
    media_1080_css,
    r"\.hero-copy\s*\{[^}]*margin-inline\s*:\s*auto",
    "mid-range hero copy centering",
)

media_720 = re.search(
    r"@media\s*\((?:max-width:\s*720px|width\s*<=\s*720px)\)\s*\{(.*)\}\s*$",
    css,
    re.S,
)
if not media_720:
    raise SystemExit("Missing 720px media query")

media_720_css = media_720.group(1)
expect_in_css(
    media_720_css,
    r"\.hero-visual\s*\{[^}]*width\s*:\s*100%",
    "mobile hero visual full width",
)
expect_in_css(
    media_720_css,
    r"\.hero-visual\s*\{[^}]*max-width\s*:\s*none",
    "mobile hero visual max-width reset",
)
PY

echo "Site smoke check passed."
