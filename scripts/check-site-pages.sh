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
check_contains "/" "faq-panel"
check_contains "/" "faq-panel-header"
check_contains "/" "Questions?"
check_contains "/" "The quick answers on tracking, sign-in, privacy, widgets, and getting set up on"
check_contains "/" "your Mac."
check_contains "/" "Need help?"
check_contains "/" "want to report a bug."
check_contains "/" "mailto:help@aiquota.app"
check_contains "/site.css" ".hero-demo-media"
check_contains "/site.css" ".faq-panel"
check_contains "/site.css" ".faq-panel-header"
check_contains "/site.css" "font-size: clamp(1.03rem, 1.15vw, 1.12rem);"
check_contains "/site.css" "font-size: 0.94rem;"
check_contains "/site.css" "font-size: clamp(1.16rem, 1.34vw, 1.24rem);"
check_contains "/site.css" "padding-bottom: 12px;"
check_contains "/site.css" "border-radius: inherit;"
check_contains "/site.css" "object-position: center top;"
check_contains "/site.css" "@media (max-width: 1080px)"
check_contains "/site.css" "width: min(100%, clamp(560px, 72vw, 680px));"
check_contains "/site.css" "margin-inline: auto;"
check_contains "/site.css" "justify-self: center;"

if curl -fsS "$BASE_URL/" | grep -q "faq-layout"; then
  echo "Expected old split FAQ layout class to be removed from homepage"
  exit 1
fi

if curl -fsS "$BASE_URL/" | grep -q "Need help? Email"; then
  echo "Expected footer help line to be removed from homepage"
  exit 1
fi

if curl -fsS "$BASE_URL/site.css" | grep -q "width: fit-content;"; then
  echo "Expected FAQ kicker pill styling to be removed"
  exit 1
fi

if curl -fsS "$BASE_URL/site.css" | grep -q "padding: 8px 12px;"; then
  echo "Expected FAQ kicker padding pill styling to be removed"
  exit 1
fi

python3 - "$SITE_DIR/site.css" <<'PY'
from pathlib import Path
import sys

css = Path(sys.argv[1]).read_text()

for selector in (".visual-card", ".visual-frame", ".hero-demo-media"):
    start = css.find(f"{selector} {{")
    if start == -1:
        raise SystemExit(f"Missing selector block: {selector}")
    end = css.find("}", start)
    block = css[start:end]
    if "isolation: isolate;" not in block:
        raise SystemExit(f"Missing isolation in {selector}")
    if "-webkit-mask-image: -webkit-radial-gradient(white, black);" not in block:
        raise SystemExit(f"Missing webkit mask in {selector}")
    if "mask-image: radial-gradient(white, black);" not in block:
        raise SystemExit(f"Missing mask-image in {selector}")
PY

python3 - "$BASE_URL/" <<'PY'
from html.parser import HTMLParser
from urllib.request import urlopen
import sys

url = sys.argv[1]
html = urlopen(url).read().decode("utf-8")

class TextCollector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_script = False
        self.in_style = False
        self.text = []

    def handle_starttag(self, tag, attrs):
        if tag == "script":
            self.in_script = True
        elif tag == "style":
            self.in_style = True

    def handle_endtag(self, tag):
        if tag == "script":
            self.in_script = False
        elif tag == "style":
            self.in_style = False

    def handle_data(self, data):
        if not self.in_script and not self.in_style:
            text = data.strip()
            if text:
                self.text.append(text)

parser = TextCollector()
parser.feed(html)

violations = [text for text in parser.text if '"' in text or "'" in text]
if violations:
    raise SystemExit(
        "Visible homepage copy contains straight quotes/apostrophes: "
        + " | ".join(violations)
    )
PY

echo "Site smoke check passed."
