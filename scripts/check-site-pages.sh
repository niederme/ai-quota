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

check_release_page_matches_github() {
  python3 - "$BASE_URL/releases/" <<'PY'
from datetime import datetime, timezone
import json
import sys
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

page_url = sys.argv[1]
page_html = urlopen(page_url).read().decode("utf-8")
api_request = Request(
    "https://api.github.com/repos/niederme/ai-quota/releases?per_page=4",
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "aiquota-site-check",
    },
)
releases = json.load(urlopen(api_request))
stable_releases = [
    release
    for release in releases
    if not release.get("draft") and not release.get("prerelease")
]

if len(stable_releases) < 4:
    raise SystemExit("Expected at least 4 stable GitHub releases to validate site sync")

def formatted_date(published: datetime) -> str:
    return f"{published.strftime('%B')} {published.day}, {published.year}"

def release_dates(published_at: str) -> set[str]:
    published_utc = datetime.strptime(
        published_at, "%Y-%m-%dT%H:%M:%SZ"
    ).replace(tzinfo=timezone.utc)
    published_local = published_utc.astimezone(ZoneInfo("America/New_York"))
    return {formatted_date(published_utc), formatted_date(published_local)}

missing = []
for index, release in enumerate(stable_releases[:4]):
    version = release["tag_name"].removeprefix("v")
    tag_url = f"https://github.com/niederme/ai-quota/releases/tag/{release['tag_name']}"

    if index == 0:
        required_tokens = [
            f"AIQuota {version}",
            f"Download {version}",
            tag_url,
        ]
    else:
        required_tokens = [
            f"Version {version}",
            tag_url,
        ]

    for token in required_tokens:
        if token not in page_html:
            missing.append(token)

    valid_dates = release_dates(release["published_at"])
    if not any(date in page_html for date in valid_dates):
        missing.append(" or ".join(sorted(valid_dates)))

if missing:
    formatted = "\n".join(f"- {token}" for token in missing)
    raise SystemExit(
        "Release page is out of sync with GitHub releases. Missing:\n" + formatted
    )
PY
}

check_contains "/" "Know your limits<br />before they break<br />your flow."
check_contains "/" "AIQuota shows how much of your Codex and Claude allowance is left, with reset times"
check_contains "/" "and alerts, in your menu bar, on your Home Screen and on your Lock Screen."
check_contains "/" "<title>Claude Code &amp; Codex Usage Tracker for macOS | AIQuota</title>"
check_contains "/" "Track Claude Code and OpenAI Codex usage, quota windows, reset times, and alerts"
check_contains "/" "\"@id\": \"https://aiquota.app/#software\""
check_contains "/" "\"@type\": \"SoftwareApplication\""
check_contains "/" "\"@id\": \"https://nieder.me/#person\""
check_contains "/" "\"operatingSystem\": \"macOS 15 or later\""
check_contains "/" "\"downloadUrl\": \"https://github.com/niederme/ai-quota/releases/latest/download/AIQuota.zip\""
check_contains "/" "Reset timers, plan details, and warning states"
check_contains "/releases/" "<h1>Releases</h1>"
check_contains "/privacy/" "<h1 class=\"policy-title\">Privacy Policy</h1>"
check_contains "/faq/" "<h1 class=\"page-title\">Questions?</h1>"
check_contains "/faq/" "<link rel=\"canonical\" href=\"https://aiquota.app/faq/\" />"
check_contains "/terms/" "<h1 class=\"policy-title\">Terms of Service</h1>"
check_contains "/accessibility/" "<h1 class=\"policy-title\">Accessibility</h1>"
check_release_page_matches_github

check_status "/site.css"
check_status "/site.js"
check_status "/llms.txt"
check_status "/robots.txt"
check_status "/sitemap.xml"
check_status "/assets/aiquota-demo-inline.mp4"
check_status "/assets/aiquota-video-poster.png"
check_status "/assets/ios-lockscreen.webp"
check_status "/assets/ios-overview-dark.webp"
check_status "/assets/mac-popover-2.webp"

video_size="$(wc -c < "$SITE_DIR/assets/aiquota-demo-inline.mp4" | tr -d '[:space:]')"
if (( video_size > 1048576 )); then
  echo "Expected optimized demo video to stay under 1 MiB, got ${video_size} bytes"
  exit 1
fi

check_contains "/robots.txt" "Sitemap: https://aiquota.app/sitemap.xml"
check_contains "/llms.txt" "# AIQuota"
check_contains "/llms.txt" "AIQuota is a native macOS menu bar app for monitoring OpenAI Codex and Claude Code usage quotas."
check_contains "/llms.txt" "[Latest Download](https://github.com/niederme/ai-quota/releases/latest/download/AIQuota.zip)"
check_contains "/sitemap.xml" "<loc>https://aiquota.app/</loc>"
check_contains "/sitemap.xml" "<loc>https://aiquota.app/releases/</loc>"
check_contains "/sitemap.xml" "<loc>https://aiquota.app/faq/</loc>"
check_contains "/sitemap.xml" "<loc>https://aiquota.app/privacy/</loc>"
check_contains "/sitemap.xml" "<loc>https://aiquota.app/terms/</loc>"
check_contains "/sitemap.xml" "<loc>https://aiquota.app/accessibility/</loc>"

grep -Fq 'RewriteCond %{HTTP_HOST} !^aiquota\.app$ [NC,OR]' "$SITE_DIR/.htaccess"
grep -Fq 'RewriteCond %{HTTP:X-Forwarded-Proto} !https [NC]' "$SITE_DIR/.htaccess"
grep -Fq 'Strict-Transport-Security "max-age=31536000; includeSubDomains"' "$SITE_DIR/.htaccess"

# Shared shell: nav with the current page marked, footer help line, theme picker.
for page in "/" "/releases/" "/faq/" "/privacy/" "/terms/" "/accessibility/"; do
  check_contains "$page" "class=\"aq-nav aq-glass\""
  check_contains "$page" "data-theme-picker"
  check_contains "$page" "Need help? Email"
  check_contains "$page" "mailto:help@aiquota.app"
  check_contains "$page" "localStorage.getItem(\"aiquota-theme\")"
done
check_contains "/" "<a class=\"aq-nav__link\" href=\"./\" aria-current=\"page\">Overview</a>"
check_contains "/releases/" "<a class=\"aq-nav__link\" href=\"../releases/\" aria-current=\"page\">Releases</a>"
check_contains "/faq/" "<a class=\"aq-nav__link\" href=\"../faq/\" aria-current=\"page\">FAQ</a>"

# Overview: hero, features bento, devices, FAQ pointer, download band.
check_contains "/" "AIQuota 2.0 · Now on Mac, iPhone and iPad"
check_contains "/" "class=\"bento\""
check_contains "/" "Your allowance, wherever you’re working."
check_contains "/" "One look, on every screen."
check_contains "/" "href=\"./faq/\">Read the FAQ</a>"
check_contains "/" "Get AIQuota 2.0"

# FAQ page: one accordion, first answer open.
check_contains "/faq/" "The quick answers on tracking, sign-in, privacy, widgets, and getting set up on your Mac, iPhone or iPad."
check_contains "/faq/" "<details class=\"faq-item\" name=\"faq\" open>"
check_contains "/faq/" "Do my Mac and iPhone share a connection?"
check_contains "/faq/" "Need help?"
check_contains "/faq/" "want to report a bug."

if curl -fsS "$BASE_URL/" | grep -q "faq-item"; then
  echo "Expected the FAQ to live on /faq/, not the homepage"
  exit 1
fi

python3 - "$SITE_DIR/site.css" <<'PY'
from pathlib import Path
import re
import sys

css = Path(sys.argv[1]).read_text()

def selector_block(selector: str) -> str:
    match = re.search(r"(?:^|[}\s,])" + re.escape(selector) + r"\s*\{([^}]*)\}", css)
    if not match:
        raise SystemExit(f"Missing selector block: {selector}")
    return match.group(1)

def expect(selector: str, pattern: str, message: str) -> None:
    if not re.search(pattern, selector_block(selector)):
        raise SystemExit(f"Missing {message} in {selector}")

def media_block(query: str) -> str:
    match = re.search(r"@media\s*\((?:" + query + r")\)\s*\{(.*?\})\s*\}", css, re.S)
    if not match:
        raise SystemExit(f"Missing media query: {query}")
    return match.group(1)

# Design-system foundation (tokens.css + bundle.css) is merged into site.css.
for token in ("--canvas", "--surface", "--accent-ink", "--brand", "--radius-card", "--font-sans"):
    if not re.search(re.escape(token) + r"\s*:", css):
        raise SystemExit(f"Missing design token {token}")
for selector in (".aq-nav", ".aq-btn", ".aq-card", ".aq-dial", ".aq-notice", ".aq-heat", ".aq-theme", ".aq-wash"):
    selector_block(selector)
if not re.search(r'\[data-theme="?light"?\]', css):
    raise SystemExit("Missing light theme override")

expect(".hero h1", r"font-size\s*:\s*clamp\(\s*40px\s*,\s*4\.9vw\s*,\s*58px\s*\)", "hero headline clamp")
expect(".hero h1", r"text-wrap\s*:\s*initial", "hero headline wrap reset")
expect(".bento", r"grid-auto-flow\s*:\s*dense", "dense bento flow")
expect(".site-nav", r"position\s*:\s*fixed", "fixed nav")

lg = media_block(r"min-width:\s*1000px|width\s*>=\s*1000px")
if not re.search(r"\.bento\s*\{[^}]*repeat\(\s*6\s*,", lg):
    raise SystemExit("Missing six-column bento at 1000px")
md = media_block(r"min-width:\s*680px|width\s*>=\s*680px")
if not re.search(r"\.bento\s*\{[^}]*repeat\(\s*2\s*,", md):
    raise SystemExit("Missing two-column bento at 680px")
narrow = media_block(r"max-width:\s*759px|width\s*<=\s*759px")
if not re.search(r"\.site-nav__menu\s*\{[^}]*display\s*:\s*grid", narrow):
    raise SystemExit("Missing narrow-screen menu button")
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
