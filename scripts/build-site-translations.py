#!/usr/bin/env python3
"""Build the translated copies of the aiquota.app pages.

The English pages in docs/ are the source. Each language has a catalog in
scripts/site-translations/<language>.json that maps an English string, exactly
as it appears in the HTML (inline tags included, whitespace collapsed), to its
translation. This script writes docs/<language>/... for every page, with links
pointing at the same language, the language picker set, and the head tags
(lang, canonical, og:url, og:locale) updated. It also writes docs/sitemap.xml.

English that has no translation yet stays English on the translated page and
is listed when the script runs, so new copy never breaks the site.

    scripts/build-site-translations.py            # write the pages
    scripts/build-site-translations.py --check    # fail if docs/ is out of date
    scripts/build-site-translations.py --missing  # list untranslated strings
"""

from __future__ import annotations

import argparse
import html
import json
import posixpath
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "docs"
CATALOGS = ROOT / "scripts" / "site-translations"
SITE_URL = "https://aiquota.app"

# URL path -> source file. Every page exists in every language.
PAGES = {
    "/": "index.html",
    "/releases/": "releases/index.html",
    "/faq/": "faq/index.html",
    "/privacy/": "privacy/index.html",
    "/terms/": "terms/index.html",
    "/accessibility/": "accessibility/index.html",
}


@dataclass(frozen=True)
class Language:
    slug: str  # URL folder and data-lang value
    code: str  # BCP 47, for lang and hreflang
    og_locale: str
    name: str  # in its own language


ENGLISH = Language("en", "en", "en_US", "English")
LANGUAGES = [
    Language("de", "de", "de_DE", "Deutsch"),
    Language("fr", "fr", "fr_FR", "Français"),
    Language("es", "es", "es_ES", "Español"),
    Language("pt-br", "pt-BR", "pt_BR", "Português (Brasil)"),
    Language("ja", "ja", "ja_JP", "日本語"),
    Language("ko", "ko", "ko_KR", "한국어"),
]

MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]
VERSION = re.compile(r"(?<=\bVersion )\d+(?:\.\d+)+\b")
DATE = re.compile(r"\b(" + "|".join(MONTHS) + r") (\d{1,2}), (\d{4})\b")


def format_date(language: Language, month: int, day: int, year: int) -> str:
    """Dates are written out like the English 'November 20, 2026'."""
    names = {
        "de": ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"],
        "fr": ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"],
        "es": ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
        "pt-br": ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"],
    }
    if language.slug == "de":
        return f"{day}. {names['de'][month - 1]} {year}"
    if language.slug == "fr":
        return f"{'1er' if day == 1 else day} {names['fr'][month - 1]} {year}"
    if language.slug in ("es", "pt-br"):
        return f"{day} de {names[language.slug][month - 1]} de {year}"
    if language.slug == "ja":
        return f"{year}年{month}月{day}日"
    if language.slug == "ko":
        return f"{year}년 {month}월 {day}일"
    return f"{MONTHS[month - 1]} {day}, {year}"


# --------------------------------------------------------------------------
# A small HTML tokenizer that keeps exact source offsets, so a translated page
# is the English file with only its copy, links and a few head tags changed.

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
RAW = {"script", "style"}
INLINE = {"a", "abbr", "b", "br", "code", "em", "i", "img", "kbd", "mark", "q", "s", "small", "span", "strong", "sub", "sup", "svg", "time", "u", "wbr"}
OPAQUE = {"script", "style", "svg", "template"}
TOKEN = re.compile(
    r"<!--.*?-->|<![a-zA-Z][^>]*>|</([a-zA-Z][\w:-]*)\s*>|<([a-zA-Z][\w:-]*)((?:[^>\"']|\"[^\"]*\"|'[^']*')*)>",
    re.S,
)
ATTR = re.compile(r"""\s+([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+)))?""")
LETTER = re.compile(r"[^\W\d_]")
COPY = re.compile(r"[^\W_]")


@dataclass
class Text:
    start: int
    end: int


@dataclass
class Element:
    tag: str
    start: int  # start of the start tag
    tag_end: int  # end of the start tag
    attrs: dict[str, str]
    end: int = -1  # end of the end tag
    children: list = field(default_factory=list)


@dataclass
class Comment:
    start: int
    end: int


def parse_attrs(attr_text: str) -> dict[str, str]:
    attrs = {}
    for m in ATTR.finditer(attr_text):
        value = next((g for g in m.groups()[1:] if g is not None), "")
        attrs[m.group(1).lower()] = value
    return attrs


def parse(source: str, name: str) -> Element:
    root = Element("#root", 0, 0, {})
    stack = [root]
    pos = 0
    while pos < len(source):
        m = TOKEN.search(source, pos)
        if not m:
            stack[-1].children.append(Text(pos, len(source)))
            break
        if m.start() > pos:
            stack[-1].children.append(Text(pos, m.start()))
        if m.group(0).startswith("<!--"):
            stack[-1].children.append(Comment(m.start(), m.end()))
        elif m.group(1):  # end tag
            tag = m.group(1).lower()
            if stack[-1].tag != tag:
                line = source.count("\n", 0, m.start()) + 1
                raise SystemExit(f"{name}:{line}: </{tag}> closes <{stack[-1].tag}>")
            stack[-1].end = m.end()
            stack.pop()
        elif m.group(2):  # start tag
            tag = m.group(2).lower()
            element = Element(tag, m.start(), m.end(), parse_attrs(m.group(3)))
            stack[-1].children.append(element)
            if tag in RAW:
                close = re.compile(rf"</{tag}\s*>", re.I).search(source, m.end())
                element.children.append(Text(m.end(), close.start()))
                element.end = close.end()
                pos = close.end()
                continue
            if tag in VOID or m.group(3).rstrip().endswith("/"):
                element.end = m.end()
            else:
                stack.append(element)
        pos = m.end()
    if len(stack) != 1:
        raise SystemExit(f"{name}: unclosed <{stack[-1].tag}>")
    root.end = len(source)
    return root


def walk(node):
    yield node
    for child in getattr(node, "children", []):
        yield from walk(child)


# --------------------------------------------------------------------------
# Copy: a "segment" is a run of text and inline elements inside a block, such
# as a heading, a paragraph with a link in it, or a button label.


def has_letters(source: str, node, pattern=LETTER) -> bool:
    if isinstance(node, Text):
        return bool(pattern.search(html.unescape(source[node.start:node.end])))
    if isinstance(node, Element):
        if node.tag in OPAQUE or skipped(node):
            return False
        return any(has_letters(source, c, pattern) for c in node.children)
    return False


def has_copy(source: str, node) -> bool:
    """Words, or figures such as "$10.44" that some languages write differently."""
    return has_letters(source, node, COPY)


def skipped(element: Element) -> bool:
    return "data-i18n-skip" in element.attrs or "data-lang-current" in element.attrs


def is_inline(node) -> bool:
    if isinstance(node, (Text, Comment)):
        return True
    return node.tag in INLINE


def segments(source: str, element: Element):
    """Yield (start, end) source ranges to translate inside an element."""
    if element.tag in OPAQUE or skipped(element):
        return
    run = []
    for child in element.children + [None]:
        if child is not None and is_inline(child):
            run.append(child)
            continue
        yield from run_segments(source, run)
        run = []
        if isinstance(child, Element):
            yield from segments(source, child)


def run_segments(source: str, run):
    nodes = [n for n in run if not isinstance(n, Comment)]
    if not any(has_copy(source, n) for n in nodes):
        return

    def trimmable(n):
        # Icons and blank space at either end; punctuation text stays.
        if isinstance(n, Text):
            return not source[n.start:n.end].strip()
        return not has_copy(source, n)

    while trimmable(nodes[0]):
        nodes.pop(0)
    while trimmable(nodes[-1]):
        nodes.pop()
    direct_text = any(isinstance(n, Text) and has_copy(source, n) for n in nodes)
    if not direct_text:
        # Separate pieces, like two labels side by side: translate each one.
        for n in nodes:
            if isinstance(n, Element) and has_copy(source, n):
                yield from segments(source, n)
        return
    start, end = nodes[0].start, nodes[-1].end
    while start < end and source[start].isspace():
        start += 1
    while end > start and source[end - 1].isspace():
        end -= 1
    yield (start, end)


def collapse(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


class Catalog:
    def __init__(self, language: Language):
        self.language = language
        path = CATALOGS / f"{language.slug}.json"
        self.entries: dict[str, str] = json.loads(path.read_text()) if path.exists() else {}
        self.missing: dict[str, None] = {}
        self.used: set[str] = set()

    def translate(self, english: str) -> str:
        """Translate collapsed English, with dates swapped in afterwards."""
        dates = []

        def hold(m):
            dates.append((MONTHS.index(m.group(1)) + 1, int(m.group(2)), int(m.group(3))))
            return "{date}"

        key = DATE.sub(hold, english)
        versions = VERSION.findall(key)
        key = VERSION.sub("{version}", key)
        if key in self.entries:
            self.used.add(key)
            translated = self.entries[key]
        elif not LETTER.search(key.replace("{date}", "").replace("{version}", "")):
            translated = key  # only figures or a date: optional
        else:
            self.missing[key] = None
            return english
        for version in versions:
            translated = translated.replace("{version}", version, 1)
        for month, day, year in dates:
            translated = translated.replace("{date}", format_date(self.language, month, day, year), 1)
        return translated


# --------------------------------------------------------------------------
# Building one page.

TRANSLATED_ATTRS = {"alt", "title", "aria-label", "placeholder"}
TRANSLATED_META = {"description", "og:title", "og:description", "og:image:alt", "twitter:title", "twitter:description", "twitter:image:alt"}
URL_ATTRS = {"href", "src", "poster"}
JSON_LD_KEYS = {"description", "featureList", "operatingSystem"}
NOTE_MARKER = "<!-- i18n:translation-note -->"
TRANSLATION_NOTE = "This translation is provided for convenience. If it differs from the English version, the English version applies."


def localized_path(language: Language, path: str) -> str:
    return path if language is ENGLISH else f"/{language.slug}{path}"


def relative(target: str, page_dir: str) -> str:
    rel = posixpath.relpath(target, page_dir)
    if target.endswith("/") and not rel.endswith("/"):
        rel = "./" if rel == "." else rel + "/"
    return rel if rel.startswith(("../", "./")) else "./" + rel


def rewrite_url(value: str, page: str, language: Language) -> str:
    """Point a link at the same language; keep assets where they are."""
    if not value or re.match(r"^([a-z][a-z0-9+.-]*:|//|#)", value, re.I):
        return value
    target, sep, rest = re.match(r"^([^?#]*)(([?#].*)?)$", value).group(1, 2, 2)
    absolute = target.startswith("/")
    resolved = posixpath.normpath(posixpath.join(page, target)) if not absolute else posixpath.normpath(target)
    if target.endswith("/") or target in ("", "."):
        resolved = resolved.rstrip("/") + "/"
    if resolved in PAGES:
        resolved = localized_path(language, resolved)
    if absolute:
        return resolved + sep
    return relative(resolved, localized_path(language, page)) + sep


def set_attr(tag_text: str, name: str, value: str) -> str:
    """Replace one attribute's value inside a start tag's source."""
    pattern = re.compile(rf'(\s{re.escape(name)}\s*=\s*)"[^"]*"', re.I)
    replacement = html.escape(value, quote=True) if "&" not in value else value.replace('"', "&quot;")
    new, n = pattern.subn(lambda m: f'{m.group(1)}"{replacement}"', tag_text, count=1)
    if n != 1:
        raise SystemExit(f"Expected one {name} in {tag_text[:80]}")
    return new


def remove_attr(tag_text: str, name: str) -> str:
    return re.sub(rf'\s{re.escape(name)}(\s*=\s*"[^"]*")?(?=[\s/>])', "", tag_text, count=1)


def apply(source: str, edits) -> str:
    out = []
    last = len(source)
    for start, end, replacement in sorted(edits, key=lambda e: e[0], reverse=True):
        if end > last:
            raise SystemExit("Overlapping edits")
        out.append(source[end:last])
        out.append(replacement)
        last = start
    out.append(source[:last])
    return "".join(reversed(out))


def build_page(source: str, path: str, file: str, language: Language, catalog: Catalog) -> str:
    # 1. Copy.
    tree = parse(source, file)
    edits = []
    for start, end in segments(source, tree):
        english = collapse(source[start:end])
        translated = catalog.translate(english)
        if translated != english:
            edits.append((start, end, translated))
    source = apply(source, edits)

    # 2. Attributes, links, head tags, the language picker and notes.
    tree = parse(source, file)
    edits = []
    page_dir = localized_path(language, path)
    canonical = SITE_URL + page_dir
    for node in walk(tree):
        if isinstance(node, Comment) and source[node.start:node.end] == NOTE_MARKER:
            note = catalog.translate(TRANSLATION_NOTE)
            edits.append((node.start, node.end, f'<p class="policy-note">{note}</p>'))
            continue
        if not isinstance(node, Element) or node.tag == "#root":
            continue
        tag_text = source[node.start:node.tag_end]
        original = tag_text
        attrs = node.attrs
        if node.tag == "html":
            tag_text = set_attr(tag_text, "lang", language.code)
        for name in TRANSLATED_ATTRS & attrs.keys():
            if LETTER.search(attrs[name]):
                tag_text = set_attr(tag_text, name, catalog.translate(collapse(attrs[name])))
        if node.tag == "meta":
            key = attrs.get("name") or attrs.get("property")
            if key in TRANSLATED_META:
                tag_text = set_attr(tag_text, "content", catalog.translate(collapse(attrs["content"])))
            elif key in ("og:url", "twitter:url"):
                tag_text = set_attr(tag_text, "content", canonical)
            elif key == "og:locale":
                tag_text = set_attr(tag_text, "content", language.og_locale)
        if node.tag == "link" and attrs.get("rel") == "canonical":
            tag_text = set_attr(tag_text, "href", canonical)
        elif node.tag == "link" and attrs.get("rel") == "alternate":
            pass  # already absolute, the same on every version
        elif "data-lang" in attrs:
            target = next((l for l in [ENGLISH, *LANGUAGES] if l.slug == attrs["data-lang"]), None)
            tag_text = set_attr(tag_text, "href", relative(localized_path(target, path), page_dir))
            tag_text = remove_attr(tag_text, "aria-current")
            if target is language:
                tag_text = tag_text[:-1] + ' aria-current="true">'
        else:
            for name in URL_ATTRS & attrs.keys():
                tag_text = set_attr(tag_text, name, rewrite_url(attrs[name], path, language))
        if tag_text != original:
            edits.append((node.start, node.tag_end, tag_text))
        if "data-lang-current" in attrs:
            edits.append((node.tag_end, node.children[0].end if node.children else node.tag_end, language.name))
        if node.tag == "script" and attrs.get("type") == "application/ld+json":
            body = node.children[0]
            raw = source[body.start:body.end]
            data = json.loads(raw)

            def translate_json(value, key=None):
                if isinstance(value, dict):
                    return {k: translate_json(v, k) for k, v in value.items()}
                if isinstance(value, list):
                    return [translate_json(v, key) for v in value]
                if isinstance(value, str) and key in JSON_LD_KEYS:
                    return html.unescape(catalog.translate(html.escape(value, quote=False)))
                return value

            indent = re.match(r"\n?([ \t]*)", raw).group(1)
            dumped = json.dumps(translate_json(data), ensure_ascii=False, indent=2)
            dumped = "\n".join(indent + line for line in dumped.splitlines())
            edits.append((body.start, body.end, "\n" + dumped + "\n" + indent[:-2]))
    return apply(source, edits)


def sitemap() -> str:
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    ]
    for language in [ENGLISH, *LANGUAGES]:
        for path in PAGES:
            lines.append("  <url>")
            lines.append(f"    <loc>{SITE_URL}{localized_path(language, path)}</loc>")
            for alternate in [ENGLISH, *LANGUAGES]:
                lines.append(
                    f'    <xhtml:link rel="alternate" hreflang="{alternate.code}" href="{SITE_URL}{localized_path(alternate, path)}" />'
                )
            lines.append(f'    <xhtml:link rel="alternate" hreflang="x-default" href="{SITE_URL}{path}" />')
            lines.append("  </url>")
    lines.append("</urlset>")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if the generated files in docs/ are out of date")
    parser.add_argument("--missing", action="store_true", help="print each untranslated string as JSON")
    args = parser.parse_args()

    outputs: dict[Path, str] = {SITE / "sitemap.xml": sitemap()}
    catalogs = {language.slug: Catalog(language) for language in LANGUAGES}
    sources = {path: (SITE / file).read_text() for path, file in PAGES.items()}
    for language in LANGUAGES:
        for path, file in PAGES.items():
            outputs[SITE / language.slug / file] = build_page(sources[path], path, file, language, catalogs[language.slug])

    if args.missing:
        print(json.dumps({slug: list(c.missing) for slug, c in catalogs.items() if c.missing}, ensure_ascii=False, indent=2))
        return 0

    stale = [p for p, text in outputs.items() if not p.exists() or p.read_text() != text]
    if args.check:
        if stale:
            print("Translated pages are out of date. Run scripts/build-site-translations.py:")
            for p in stale:
                print(f"  {p.relative_to(ROOT)}")
            return 1
    else:
        for p in stale:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(outputs[p])
        print(f"Wrote {len(stale)} file(s)." if stale else "Translated pages are up to date.")

    for slug, catalog in catalogs.items():
        if catalog.missing:
            print(f"{slug}: {len(catalog.missing)} string(s) still in English (see --missing)", file=sys.stderr)
        unused = set(catalog.entries) - catalog.used - {TRANSLATION_NOTE}
        if unused:
            print(f"{slug}: {len(unused)} catalog entr{'y' if len(unused) == 1 else 'ies'} no longer on the site", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
