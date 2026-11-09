#!/usr/bin/env python3
"""Generate docs/reclaim-rules.md from the rule files in rules/*.json. Standard library only.

Usage: python3 scripts/gen-rules-doc.py [--check]

--check writes nothing and exits 1 with a message when the page would change.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = ROOT / "rules"
OUTPUT = ROOT / "docs" / "reclaim-rules.md"
TIERS = ["safe", "rebuild", "review", "never"]

HEADER = """# Reclaim rules

Every rule DeepYellow uses to advise on a place on disk. The rules are read from the JSON files in [`rules/`](https://github.com/midhunkrishna/deepyellow/tree/master/rules) when the app starts, and this page is generated from the same files, so it lists exactly what the app contains.

A rule says what a place is, how safe it is to remove, what removal costs, any condition to meet first, and an official cleanup command when one exists. **Commands are shown and never run.** Removal always goes through a [Plan](safety-and-accounting.md#the-plan) and the Trash.

## How to read it

| Tier | Meaning |
|---|---|
| **safe** | Regenerates automatically with no user-visible loss |
| **rebuild** | Recoverable at a cost of time, network or a login |
| **review** | May hold personal or unique data, so you must look |
| **never** | Not offered for removal, whatever you select |

- A rule applies to everything inside the matched place. The most specific rule wins, and a `never` ancestor always beats anything beneath it.
- Uncertain means `review`. Rules whose source is "Research notes (unverified)" are never given a tier safer than the evidence supports.
- The **source** records where the claim comes from.
- Rules marked "name heuristic" go only on a folder or file name, so they are hints.

### Pattern grammar

Patterns are case-insensitive. `~/` is your home folder and a leading `/` is an absolute path. `*` matches any run of characters within one path segment, and `**` as a middle segment matches zero or more folders. `**/name` at the start matches `name` anywhere. A segment may list alternatives with `|` and exclusions with `&!`, for example `*.sqlite&!*cache*`. Several full paths may be joined with `||`. A trailing `if-sibling:a|b` applies the rule only when a sibling named `a` or `b` exists next to the match.


"""


def load_sections(directory: Path) -> list:
    """Read every *.json file in the folder, in file-name order, and return the decoded files."""
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted(directory.glob("*.json"))]


def app_name(source: str) -> str:
    """Return the word after "removed and relaunched " in a source string, or "" when absent."""
    match = re.search(r"removed and relaunched (\S+)", source or "")
    return match.group(1) if match else ""


def measured_line(rule: dict) -> str:
    """Build the Measured line for a relaunch-test rule."""
    ev = rule["evidence"]
    name = app_name(rule.get("source") or "")
    app = f"{name} {ev['appVersion']}" if name else ev["appVersion"]
    return f"- **Measured:** {ev['observed']} ({app}, macOS {ev['macOSVersion']}, {ev['measuredOn']})"


def evidence_lines(rule: dict) -> list:
    """Return the evidence lines for a rule: Measured, Observed or Evidence unverified."""
    ev = rule.get("evidence") or {}
    method = ev.get("method")
    if method == "relaunch-test":
        return [measured_line(rule)]
    lines = []
    if ev.get("observed"):
        lines.append(f"- **Observed:** {ev['observed']}")
    if method == "research":
        lines.append("- **Evidence:** unverified")
    return lines


def entry(rule: dict) -> str:
    """Render one rule as a Markdown entry."""
    lines = [
        f"### {rule['title']}",
        "",
        f"**Tier: {rule['tier']}** · `{rule['id']}`",
        "",
        f"- **Pattern:** `{rule['pattern']}`",
        f"- **What it is:** {rule['whatItIs']}",
        f"- **If you remove it:** {rule['consequence']}",
    ]
    if rule.get("sideCondition"):
        lines.append(f"- **Condition:** {rule['sideCondition']}")
    if rule.get("cleanupCommand"):
        lines.append(f"- **Official command:** `{rule['cleanupCommand']}`")
    owners = rule.get("ownerBundleIDs") or []
    if owners:
        lines.append("- **Owning app:** " + ", ".join(f"`{o}`" for o in owners))
    if rule.get("source"):
        lines.append(f"- **Source:** {rule['source']}")
    lines.extend(evidence_lines(rule))
    return "\n".join(lines) + "\n"


def section_text(doc: dict) -> str:
    """Render one rule file as a section: heading, intro and its entries."""
    sec = doc["section"]
    parts = [f"## {sec['title']}\n\n{sec['intro']}\n\n"]
    parts.extend("\n" + entry(r) for r in doc["rules"])
    return "".join(parts)


def summary_text(docs: list) -> str:
    """Render the closing Summary section with the total and the count per tier."""
    rules = [r for d in docs for r in d["rules"]]
    counts = ", ".join(f"{sum(r['tier'] == t for r in rules)} {t}" for t in TIERS)
    return f"\n## Summary\n\n{len(rules)} rules in total: {counts}.\n"


def render(docs: list) -> str:
    """Render the whole page from the decoded rule files."""
    return HEADER + "\n".join(section_text(d) for d in docs) + summary_text(docs)


def main(argv: list) -> int:
    """Write the page, or with --check compare it with the file on disk."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="exit 1 if the page is out of date")
    parser.add_argument("--rules", type=Path, default=RULES_DIR, help="rules folder")
    parser.add_argument("--output", type=Path, default=OUTPUT, help="page to write")
    args = parser.parse_args(argv)
    text = render(load_sections(args.rules))
    current = args.output.read_text(encoding="utf-8") if args.output.exists() else None
    if args.check:
        if current != text:
            print(f"{args.output} is out of date; run python3 scripts/gen-rules-doc.py", file=sys.stderr)
            return 1
        return 0
    args.output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
