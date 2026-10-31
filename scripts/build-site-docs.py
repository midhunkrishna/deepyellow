#!/usr/bin/env python3
"""Render docs/*.md into web/docs/*.html with the site's chrome. Standard library only.

Usage: python3 scripts/build-site-docs.py

docs/README.md becomes web/docs/index.html. Links to other pages ending in .md become .html, and
screenshots under docs/screens/<name>.png are served from web/images/<name>.webp.
"""
from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
OUT = ROOT / "web" / "docs"
DOWNLOAD = "https://github.com/midhunkrishna/deepyellow/releases/latest/download/DeepYellow.dmg"
REPO = "https://github.com/midhunkrishna/deepyellow"

# Page order for the sidebar and the previous/next links: (file stem, sidebar title, group).
PAGES = [
    ("README", "Overview", "Start"),
    ("getting-started", "Getting started", "Start"),
    ("install", "Install", "Start"),
    ("faq", "FAQ", "Start"),
    ("views", "Views", "Using it"),
    ("query-language", "Query language", "Using it"),
    ("safety-and-accounting", "Safety and accounting", "Using it"),
    ("reclaim-rules", "Reclaim rules", "Using it"),
    ("cli", "Command line", "Using it"),
    ("building-from-source", "Building from source", "Project"),
    ("architecture", "Architecture", "Project"),
    ("uninstall", "Uninstall", "Project"),
]


def out_name(stem: str) -> str:
    """Returns the HTML file name for a markdown file stem."""
    return "index.html" if stem == "README" else stem + ".html"


def slugify(text: str) -> str:
    """Makes a heading id the way GitHub does: lowercase, punctuation removed, spaces to hyphens."""
    text = re.sub(r"<[^>]+>", "", text).lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.strip().replace(" ", "-")


def rewrite_target(target: str) -> str:
    """Maps a markdown link or image target to its place in the built site."""
    if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
        return target
    path, _, frag = target.partition("#")
    suffix = "#" + frag if frag else ""
    m = re.match(r"^screens/([\w-]+)\.png$", path)
    if m:
        return "../images/" + m.group(1) + ".webp" + suffix
    if path.endswith(".md"):
        return out_name(Path(path).stem) + suffix
    return target


def inline(text: str) -> str:
    """Renders inline markdown: code spans, images, links, bold and the allowed kbd tags."""
    spans: list[str] = []

    def stash(m: re.Match) -> str:
        spans.append("<code>" + html.escape(m.group(1), quote=False) + "</code>")
        return "\x00%d\x00" % (len(spans) - 1)

    text = re.sub(r"`([^`]+)`", stash, text)
    text = re.sub(r"</?kbd>", lambda m: "\x01" + m.group(0)[1:-1] + "\x02", text)
    text = re.sub(r"&(?!#?\w+;)", "&amp;", text).replace("<", "&lt;").replace(">", "&gt;")
    text = text.replace("\x01", "<").replace("\x02", ">")

    def image(m: re.Match) -> str:
        return '<img src="%s" alt="%s" loading="lazy" width="1600" height="1000">' % (
            html.escape(rewrite_target(m.group(2)), quote=True), html.escape(m.group(1), quote=True))

    text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", image, text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                  lambda m: '<a href="%s">%s</a>' % (html.escape(rewrite_target(m.group(2)), quote=True), m.group(1)), text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: spans[int(m.group(1))], text)


def split_row(line: str) -> list[str]:
    """Splits a markdown table row into its cells."""
    line = line.strip().strip("|")
    return [c.strip() for c in re.split(r"(?<!\\)\|", line)]


def render_table(lines: list[str]) -> str:
    """Renders a markdown table whose second line is the separator."""
    head = split_row(lines[0])
    rows = [split_row(l) for l in lines[2:]]
    out = ["<table>", "<thead><tr>" + "".join("<th>%s</th>" % inline(c) for c in head) + "</tr></thead>", "<tbody>"]
    for r in rows:
        out.append("<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>")
    out.append("</tbody></table>")
    return "\n".join(out)


LIST_RE = re.compile(r"^(\s*)([-*]|\d+\.)\s+(.*)$")


def render_list(lines: list[str]) -> str:
    """Renders a (possibly nested) list. Item bodies are rendered as blocks, so they may hold code or sublists."""
    base = len(LIST_RE.match(lines[0]).group(1))
    ordered = LIST_RE.match(lines[0]).group(2)[0].isdigit()
    items: list[list[str]] = []
    for line in lines:
        m = LIST_RE.match(line)
        if m and len(m.group(1)) == base:
            items.append([m.group(3)])
        elif items:
            items[-1].append(line)
    tag = "ol" if ordered else "ul"
    out = ["<%s>" % tag]
    for item in items:
        body = [item[0]] + [re.sub(r"^ {0,%d}" % (base + 3), "", l) for l in item[1:]]
        rendered = render_blocks(body)
        rendered = re.sub(r"^<p>(.*)</p>$", r"\1", rendered, flags=re.S) if rendered.count("<p>") == 1 and rendered.startswith("<p>") and rendered.endswith("</p>") else rendered
        out.append("<li>%s</li>" % rendered)
    out.append("</%s>" % tag)
    return "\n".join(out)


def render_blocks(lines: list[str]) -> str:
    """Renders a list of markdown lines into HTML blocks."""
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
        elif stripped.startswith("```"):
            i += 1
            code = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            i += 1
            out.append("<pre><code>%s</code></pre>" % html.escape("\n".join(code), quote=False))
        elif re.match(r"^#{1,4}\s", line):
            level = len(line) - len(line.lstrip("#"))
            title = line[level:].strip()
            slug = slugify(re.sub(r"[`*]", "", title))
            anchor = ' <a class="anchor" href="#%s" aria-label="Link to this section">#</a>' % slug if level in (2, 3) else ""
            out.append('<h%d id="%s">%s%s</h%d>' % (level, slug, inline(title), anchor, level))
            i += 1
        elif re.match(r"^-{3,}$", stripped):
            out.append("<hr>")
            i += 1
        elif stripped.startswith("|") and i + 1 < len(lines) and re.match(r"^\|?\s*:?-{2,}", lines[i + 1].strip()):
            block = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                block.append(lines[i])
                i += 1
            out.append(render_table(block))
        elif stripped.startswith(">"):
            block = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                block.append(lines[i].strip()[1:].lstrip())
                i += 1
            out.append("<blockquote>%s</blockquote>" % render_blocks(block))
        elif LIST_RE.match(line):
            block = []
            while i < len(lines):
                cur = lines[i]
                if LIST_RE.match(cur) or cur.startswith("   ") or cur.startswith("\t"):
                    block.append(cur)
                    i += 1
                elif not cur.strip() and i + 1 < len(lines) and (LIST_RE.match(lines[i + 1]) or lines[i + 1].startswith("   ")):
                    block.append(cur)
                    i += 1
                else:
                    break
            out.append(render_list(block))
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r"^(#{1,4}\s|```|\||>|-{3,}$)", lines[i].strip()) and not LIST_RE.match(lines[i]):
                para.append(lines[i].strip())
                i += 1
            out.append("<p>%s</p>" % inline(" ".join(para)))
    return "\n".join(out)


def sidebar(current: str) -> str:
    """Builds the grouped page list with the current page marked."""
    out = []
    group = None
    for stem, title, grp in PAGES:
        if grp != group:
            if group is not None:
                out.append("</ul>")
            out.append("<h4>%s</h4><ul>" % grp)
            group = grp
        cur = ' aria-current="page"' if stem == current else ""
        out.append('<li><a href="%s"%s>%s</a></li>' % (out_name(stem), cur, html.escape(title)))
    out.append("</ul>")
    return "\n".join(out)


def pager(current: str) -> str:
    """Builds previous and next links for a page."""
    stems = [p[0] for p in PAGES]
    i = stems.index(current)
    titles = {p[0]: p[1] for p in PAGES}
    prev_link = '<a href="%s">&larr; %s</a>' % (out_name(stems[i - 1]), titles[stems[i - 1]]) if i > 0 else "<span></span>"
    next_link = '<a href="%s">%s &rarr;</a>' % (out_name(stems[i + 1]), titles[stems[i + 1]]) if i + 1 < len(stems) else "<span></span>"
    return '<nav class="pager" aria-label="Pages">%s%s</nav>' % (prev_link, next_link)


def first_paragraph(md: str) -> str:
    """Returns the first plain paragraph, for the page description."""
    for block in md.split("\n\n"):
        b = block.strip()
        if b and not b.startswith(("#", "|", "```", "-", "!")):
            return re.sub(r"[`*]|\[([^\]]+)\]\([^)]*\)", lambda m: m.group(1) or "", " ".join(b.split()))[:180]
    return ""


PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} | DeepYellow docs</title>
<meta name="description" content="{description}">
<meta name="theme-color" content="#0E0D0B">
<link rel="icon" href="../favicon.png">
<link rel="apple-touch-icon" href="../images/icon.png">
<link rel="stylesheet" href="../style.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header class="nav"><div class="wrap">
  <a class="brand" href="../index.html"><span class="mark" aria-hidden="true"><i></i><i></i><i></i><i></i></span>DeepYellow</a>
  <nav class="nav-links" aria-label="Main">
    <a href="../features.html">Features</a>
    <a href="index.html" aria-current="page">Docs</a>
    <a href="../index.html#blocked">If macOS blocks it</a>
    <a href="{repo}">GitHub</a>
    <a class="btn" href="{download}">Download</a>
  </nav>
</div></header>
<div class="trust"><ul aria-label="What DeepYellow does not do">
  <li>No network code</li><li>No telemetry</li><li>Trash only, never permanent</li><li>CLI is read-only</li><li>Read-only mode for real scans</li><li>Open source, MIT</li>
</ul></div>
<div class="wrap docs">
  <nav class="docnav" aria-label="Documentation">
{sidebar}
  </nav>
  <main id="main" class="prose">
{body}
{pager}
  </main>
</div>
<footer class="foot"><div class="wrap">
  <p>DeepYellow is a native macOS disk analyzer, MIT licence. <a href="../index.html">Home</a> &middot; <a href="{repo}">Source</a> &middot; <a href="{repo}/releases">Releases</a> &middot; <a href="{repo}/edit/master/docs/{source}">Edit this page</a></p>
</div></footer>
<div class="ledger" role="complementary" aria-label="Page ledger"><div class="wrap">
  <span class="lab">LEDGER</span>
  <span class="track" aria-hidden="true"><i class="read"></i><i class="gold"></i></span>
  <span class="txt"><b data-pct>0%</b> read<span class="long"> &middot; every byte accounted for</span> &middot; free, MIT</span>
  <a class="btn primary" href="{download}">Download</a>
</div></div>
<script src="../site.js" defer></script>
</body>
</html>
"""


def build_page(stem: str) -> Path:
    """Renders one markdown file and writes its HTML page."""
    source = DOCS / (stem + ".md")
    md = source.read_text(encoding="utf-8")
    body = render_blocks(md.split("\n"))
    title_match = re.search(r"^#\s+(.+)$", md, re.M)
    title = re.sub(r"[`*]", "", title_match.group(1)) if title_match else stem
    page = PAGE.format(title=html.escape(title), description=html.escape(first_paragraph(md), quote=True), repo=REPO,
                       download=DOWNLOAD, sidebar=sidebar(stem), body=body, pager=pager(stem), source=source.name)
    target = OUT / out_name(stem)
    target.write_text(page, encoding="utf-8")
    return target


def main() -> int:
    """Builds every page and reports docs that are not listed in PAGES."""
    OUT.mkdir(parents=True, exist_ok=True)
    listed = {p[0] for p in PAGES}
    extra = sorted(p.stem for p in DOCS.glob("*.md") if p.stem not in listed and p.stem != "DESIGN")
    if extra:
        print("error: docs not listed in PAGES: " + ", ".join(extra), file=sys.stderr)
        return 1
    for stem, _, _ in PAGES:
        print("wrote", build_page(stem).relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
