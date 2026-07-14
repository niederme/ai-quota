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

check_contains "/" "Know your limits before they break your flow."
check_contains "/" "AIQuota gives you clear visibility into Codex and Claude Code usage with Menu Bar"
check_contains "/" "gauges, desktop widgets, reset timers, and warning states."
check_contains "/" "<title>Claude Code &amp; Codex Usage Tracker for macOS | AIQuota</title>"
check_contains "/" "Track Claude Code and OpenAI Codex usage, quota windows, reset times, and alerts"
check_contains "/" "\"@id\": \"https://aiquota.app/#software\""
check_contains "/" "\"@type\": \"SoftwareApplication\""
check_contains "/" "\"@id\": \"https://nieder.me/#person\""
check_contains "/" "\"operatingSystem\": \"macOS 15 or later\""
check_contains "/" "\"downloadUrl\": \"https://github.com/niederme/ai-quota/releases/latest/download/AIQuota.zip\""
check_contains "/" "Single or dual Menu Bar gauges across available 5-hour and 7-day windows"
check_contains "/" "Desktop widgets for background visibility"
check_contains "/" "Reset timers, plan details, and warning states"
check_contains "/releases/" "<h1>Releases</h1>"
check_contains "/privacy/" "<h1 class=\"policy-title\">Privacy Policy</h1>"
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
check_contains "/sitemap.xml" "<loc>https://aiquota.app/privacy/</loc>"
check_contains "/sitemap.xml" "<loc>https://aiquota.app/terms/</loc>"
check_contains "/sitemap.xml" "<loc>https://aiquota.app/accessibility/</loc>"

grep -Fq 'RewriteCond %{HTTP_HOST} !^aiquota\.app$ [NC,OR]' "$SITE_DIR/.htaccess"
grep -Fq 'RewriteCond %{HTTP:X-Forwarded-Proto} !https [NC]' "$SITE_DIR/.htaccess"
grep -Fq 'Strict-Transport-Security "max-age=31536000; includeSubDomains"' "$SITE_DIR/.htaccess"

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

if curl -fsS "$BASE_URL/" | grep -q "faq-layout"; then
  echo "Expected old split FAQ layout class to be removed from homepage"
  exit 1
fi

if curl -fsS "$BASE_URL/" | grep -q "Need help? Email"; then
  echo "Expected footer help line to be removed from homepage"
  exit 1
fi

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

def reject(selector: str, pattern: str, message: str) -> None:
    block = selector_block(selector)
    if re.search(pattern, block):
        raise SystemExit(f"Unexpected {message} in {selector}")

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
    ".faq-panel-header .feature-kicker",
    r"font-size\s*:\s*0?\.94rem",
    "FAQ kicker scale",
)
reject(
    ".faq-panel-header .feature-kicker",
    r"width\s*:\s*fit-content",
    "FAQ kicker pill width",
)
reject(
    ".faq-panel-header .feature-kicker",
    r"padding\s*:\s*8px\s+12px",
    "FAQ kicker pill padding",
)
expect(
    ".faq-item[open] summary",
    r"padding-bottom\s*:\s*12px",
    "FAQ open-state spacing",
)
expect(
    ".faq-item summary",
    r"font-size\s*:\s*clamp\(\s*1\.16rem\s*,\s*1\.34vw\s*,\s*1\.24rem\s*\)",
    "FAQ question font size",
)
expect(
    ".faq-item p",
    r"font-size\s*:\s*clamp\(\s*1\.03rem\s*,\s*1\.15vw\s*,\s*1\.12rem\s*\)",
    "FAQ answer font size",
)
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
