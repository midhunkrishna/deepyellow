#!/usr/bin/env python3
"""Check every internal link, anchor and image in README.md, docs/*.md and web/**/*.html. Standard library only.

Usage: python3 scripts/check-site-links.py

Exit status 1 only for broken links, broken anchors, external resource requests in the site, or docs that have not been
rendered. Screenshots and generated assets that do not exist yet (docs/screens/app-*.png, web/images/app-*.webp,
web/images/icon.png, web/favicon.png) are reported separately as pending and do not fail the check.
"""
from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
SCREENS = "app-map app-map-safety app-map-files app-things app-spectrum app-field app-rings app-browse app-reclaim app-worklists app-review app-plan app-ledger app-palette app-welcome app-preview-video app-preview-image app-sql-map app-sql-groups app-sql-table".split()
PENDING = {ROOT / "web" / "images" / "icon.png", ROOT / "web" / "favicon.png"}
PENDING |= {ROOT / "docs" / "screens" / (n + ".png") for n in SCREENS}
PENDING |= {ROOT / "web" / "images" / (n + ".webp") for n in SCREENS}


def slugify(text: str) -> str:
    """Makes a heading id the way the docs builder does."""
    text = re.sub(r"<[^>]+>", "", text).lower()
    return re.sub(r"[^\w\- ]", "", text).strip().replace(" ", "-")


class Collector(HTMLParser):
    """Collects ids, link targets and resource requests from an HTML file."""

    def __init__(self) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self.links: list[tuple[str, str]] = []
        self.resources: list[str] = []

    def handle_starttag(self, tag: str, attrs: list) -> None:
        a = dict(attrs)
        if a.get("id"):
            self.ids.add(a["id"])
        if tag == "a" and a.get("href"):
            self.links.append(("a", a["href"]))
        elif tag in ("img", "script", "source") and a.get("src"):
            self.links.append((tag, a["src"]))
            self.resources.append(a["src"])
        elif tag == "link" and a.get("href"):
            self.links.append(("link", a["href"]))
            self.resources.append(a["href"])


def md_links(text: str) -> list[tuple[str, str]]:
    """Extracts link and image targets from markdown, ignoring code."""
    text = re.sub(r"^```.*?^```", "", text, flags=re.S | re.M)
    text = re.sub(r"`[^`]*`", "", text)
    return [("img" if m.group(1) else "a", m.group(2)) for m in re.finditer(r"(!?)\[[^\]]*\]\(([^)\s]+)", text)]


def md_anchors(path: Path) -> set[str]:
    """Heading ids of a markdown file."""
    text = re.sub(r"^```.*?^```", "", path.read_text(encoding="utf-8"), flags=re.S | re.M)
    return {slugify(re.sub(r"[`*]", "", m.group(1))) for m in re.finditer(r"^#{1,6}\s+(.+)$", text, re.M)}


def html_anchors(path: Path) -> set[str]:
    """Element ids of an HTML file."""
    c = Collector()
    c.feed(path.read_text(encoding="utf-8"))
    return c.ids


def check(source: Path, kind: str, target: str, errors: list, pending: set, cache: dict) -> None:
    """Resolves one internal target and records an error or a pending asset."""
    if re.match(r"^[a-z][a-z0-9+.-]*:", target):
        return
    path_part, _, frag = unquote(target).partition("#")
    resolved = source if not path_part else (source.parent / path_part).resolve()
    if resolved.is_dir():
        resolved = resolved / "index.html"
    if not resolved.exists():
        if resolved in PENDING:
            pending.add(resolved)
        else:
            errors.append("%s: broken %s link to %s" % (source.relative_to(ROOT), kind, target))
        return
    if frag:
        if resolved not in cache:
            cache[resolved] = md_anchors(resolved) if resolved.suffix == ".md" else html_anchors(resolved) if resolved.suffix == ".html" else None
        if cache[resolved] is not None and frag not in cache[resolved]:
            errors.append("%s: missing anchor #%s in %s" % (source.relative_to(ROOT), frag, resolved.relative_to(ROOT)))


def main() -> int:
    """Runs every check and prints a report."""
    errors: list[str] = []
    pending: set[Path] = set()
    cache: dict = {}
    md_files = [ROOT / "README.md"] + sorted((ROOT / "docs").glob("*.md"))
    for f in md_files:
        if f.name == "DESIGN.md":
            continue
        for kind, target in md_links(f.read_text(encoding="utf-8")):
            check(f, kind, target, errors, pending, cache)
    html_files = sorted((ROOT / "web").rglob("*.html"))
    for f in html_files:
        c = Collector()
        c.feed(f.read_text(encoding="utf-8"))
        for kind, target in c.links:
            check(f, kind, target, errors, pending, cache)
        for res in c.resources:
            if re.match(r"^(https?:)?//", res):
                errors.append("%s: external resource request %s" % (f.relative_to(ROOT), res))
    index = (ROOT / "docs" / "README.md").read_text(encoding="utf-8")
    for md in sorted((ROOT / "docs").glob("*.md")):
        if md.name in ("DESIGN.md", "README.md"):
            continue
        if md.name not in index:
            errors.append("docs/README.md does not link %s" % md.name)
        built = ROOT / "web" / "docs" / (md.stem + ".html")
        if not built.exists():
            errors.append("%s has not been rendered: run scripts/build-site-docs.py" % md.name)
        elif built.stat().st_mtime < md.stat().st_mtime:
            errors.append("%s is older than %s: run scripts/build-site-docs.py" % (built.relative_to(ROOT), md.name))
    used = {p.stem for p in pending}
    unused = [n for n in SCREENS if not any(n in f.read_text(encoding="utf-8") for f in md_files + html_files)]
    print("checked %d markdown and %d html files" % (len(md_files), len(html_files)))
    if unused:
        errors.append("screenshots never referenced: " + ", ".join(unused))
    if pending:
        print("\nPENDING (not yet generated, regenerate with the screenshot script):")
        for p in sorted(pending):
            print("  " + str(p.relative_to(ROOT)))
    if errors:
        print("\nERRORS:")
        for e in errors:
            print("  " + e)
        return 1
    print("\nok: every internal link and anchor resolves (%d pending assets listed above)" % len(pending))
    return 0


if __name__ == "__main__":
    sys.exit(main())
