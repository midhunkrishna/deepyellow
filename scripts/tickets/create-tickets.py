#!/usr/bin/env python3
"""Turn scripts/tickets/apps.json into GitHub issues with the `gh` CLI. Standard library only.

Usage: python3 scripts/tickets/create-tickets.py [--dry-run] [--category N] [--umbrella]
                                                  [--sleep SECONDS] [--check-existing]

Creates one umbrella issue, one issue per category (a sub-issue of the umbrella) and one issue
per app (a sub-issue of its category). Apps marked "covered" are skipped. Issues whose title
already exists are skipped and their number is reused as the parent, so a rerun is safe.
--dry-run prints every issue and calls nothing that writes.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
APPS_FILE = HERE / "apps.json"
REPO = "midhunkrishna/deepyellow"
BLOB = f"https://github.com/{REPO}/blob/master/"

UMBRELLA_TITLE = "Start here: add a reclaim rule for an app"
UMBRELLA_LABELS = ["help wanted", "app-rule"]
PENDING = "(number is added when the ticket is created)"

# One-line colours and descriptions for the labels this script makes sure exist.
BASE_LABELS = {
    "app-rule": "Write the reclaim rules for one app",
    "no-lab-needed": "Can be done from research, without a VM",
    "needs-lab": "Needs a measurement in the lab VM",
}


def link(path: str) -> str:
    """Return a GitHub link to a file in the repo."""
    return BLOB + path


def load_data() -> dict:
    """Read apps.json."""
    return json.loads(APPS_FILE.read_text())


def gh(args: list[str]) -> str:
    """Run `gh` with an argument list and return its stdout; exit with its error on failure."""
    result = subprocess.run(["gh", *args, "-R", REPO], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"gh {' '.join(args[:2])} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def fetch_existing() -> dict[str, int]:
    """Return a map of every existing issue title to its number."""
    out = gh(["issue", "list", "--state", "all", "--limit", "1000", "--json", "number,title"])
    return {i["title"]: i["number"] for i in json.loads(out)}


def category_label(cat: dict) -> str:
    """Return the label name for a category."""
    return f"category: {cat['slug']}"


def ensure_labels(data: dict) -> None:
    """Create or update the labels the tickets use."""
    for name, desc in BASE_LABELS.items():
        gh(["label", "create", name, "--description", desc, "--force"])
    for cat in data["categories"]:
        gh(["label", "create", category_label(cat), "--description", cat["name"], "--force"])


def app_title(app: dict) -> str:
    """Return the issue title for an app."""
    return f"App rule: {app['name']}"


def category_title(cat: dict) -> str:
    """Return the issue title for a category."""
    return f"App rules: {cat['name']}"


def rules_file(app: dict) -> str:
    """Return the rules file an app's rules belong in."""
    if app.get("packageManager"):
        return "rules/40-package-managers.json"
    return "rules/90-apps.json"


def what_we_know(app: dict) -> str:
    """Return the 'What we know' lines for an app."""
    lines = []
    if app.get("cask"):
        lines.append(f"- Homebrew cask: `{app['cask']}`")
    if app.get("k"):
        lines.append(f"- About {app['k']} thousand Homebrew installs in a year")
    if app.get("mas"):
        lines.append(f"- Mac App Store top free chart rank: {app['mas']}")
    if app.get("partial"):
        lines.append(f"- Already partly covered: {app['partial']}")
    if not lines:
        lines.append("- Nothing recorded yet.")
    return "\n".join(lines)


def app_body(app: dict, number: int | None = None) -> str:
    """Build the issue body for an app. `number` is unused until the issue exists."""
    skills = ".claude/skills/{}/SKILL.md"
    return f"""## Goal

Write the reclaim rules for the folders {app['name']} fills, in [{rules_file(app)}]({link(rules_file(app))}).

## What we know

{what_we_know(app)}

## Path 1: no VM, start here

1. Open the repo in Claude Code or another agent.
2. Ask it to use the `research-app` skill for {app['name']}.
3. Paste the report as a comment on this issue.
4. Use the `write-rule` skill to turn it into a rule.

Research alone gives a `review`-tier rule, unless a vendor document supports a stronger tier.

## Path 2: lab

Follow [docs/lab-guide.md]({link('docs/lab-guide.md')}), measure the app with the `measure-app` skill, then use `write-rule`. You need this path for a `safe` or `rebuild` rule.

## Skills in this repo

- `research-app`: finds what the app stores and what the vendor says about it ([SKILL.md]({link(skills.format('research-app'))}))
- `measure-app`: runs the app in the lab VM and records what removing a folder does ([SKILL.md]({link(skills.format('measure-app'))}))
- `write-rule`: writes the rule entry and runs the checks ([SKILL.md]({link(skills.format('write-rule'))}))

Using an agent is encouraged. Tick "agent-assisted" in the PR.

## Checks and PR

- Run `make check-rules`.
- One app per PR.
- Put "Closes #<this issue number>" in the PR description.

## Safety

- Never delete files on your own Mac to test a rule.
- No real file names, screenshots or account-specific paths. Replace them with `*`.

## Claim

Comment "I'll take this". The ticket is free again after 14 days without a PR.
"""


def order_note(cat: dict) -> str:
    """Describe how the apps in a category are ordered."""
    if cat["order"] == "counted":
        return "This category is in counted Homebrew install order, highest first."
    return ("This category is in an estimated order that draws on both lists, "
            "because Homebrew does not carry many of these apps.")


def sources_note(src: dict) -> str:
    """Describe where the app list comes from, and what it does not measure."""
    return (f"The list comes from two sources: Homebrew cask installs over {src['homebrewWindow']} "
            f"([analytics]({src['homebrew']})) and the {src['macAppStore']} on {src['macAppStoreDate']}. "
            "These count installs, not use. Homebrew leans toward developers.")


def category_body(cat: dict, src: dict, numbers: dict[str, int | None]) -> str:
    """Build a category body; `numbers` maps app name to its issue number when known."""
    rows = []
    for i, app in enumerate(cat["apps"], 1):
        if app.get("covered"):
            rows.append(f"{i}. {app['name']}: already covered")
        elif numbers.get(app["name"]):
            rows.append(f"{i}. {app['name']} #{numbers[app['name']]}")
        else:
            rows.append(f"{i}. {app['name']} {PENDING}")
    return f"""A reclaim rule is a JSON entry in `rules/*.json` that says what a folder holds, what removing it does, and how safe that is. This ticket lists the apps in this category; each one has its own ticket.

{sources_note(src)}

{order_note(cat)}

## Apps

{chr(10).join(rows)}

## How to claim one

Open the app's ticket and comment "I'll take this". The ticket is free again after 14 days without a PR. See [CONTRIBUTING.md]({link('CONTRIBUTING.md')}).
"""


def umbrella_body(cats: list[dict], numbers: dict[str, int | None]) -> str:
    """Build the umbrella body listing the categories, with links when numbers are known."""
    rows = []
    for i, cat in enumerate(cats, 1):
        n = numbers.get(cat["slug"])
        rows.append(f"{i}. {cat['name']} " + (f"#{n}" if n else PENDING))
    return f"""DeepYellow gives advice about folders through reclaim rules. A rule is a JSON entry in `rules/*.json` that says what a folder holds, what removing it does, and how safe that is. We want a rule for each of the most installed Mac apps, and you can write one without a VM.

## Pick a category

{chr(10).join(rows)}

## Two ways to do it

- Path 1, no VM: use an agent and the `research-app` skill to find what the app stores, then `write-rule`. This gives a `review`-tier rule unless a vendor document supports more.
- Path 2, lab: measure the app in a VM following [docs/lab-guide.md]({link('docs/lab-guide.md')}). This is needed for a `safe` or `rebuild` rule.

Rules are described in [rules/README.md]({link('rules/README.md')}) and [CONTRIBUTING.md]({link('CONTRIBUTING.md')}). Never delete files on your own Mac to test a rule.
"""


def create_issue(title: str, body: str, labels: list[str], parent: int | None) -> int:
    """Create one issue (optionally a sub-issue) and return its number."""
    args = ["issue", "create", "--title", title, "--body", body]
    for label in labels:
        args += ["--label", label]
    if parent:
        args += ["--parent", str(parent)]
    out = gh(args)
    return int(re.search(r"/issues/(\d+)\s*$", out).group(1))


def edit_body(number: int, body: str) -> None:
    """Replace the body of an existing issue."""
    gh(["issue", "edit", str(number), "--body", body])


class Runner:
    """Creates, or in dry-run only prints, the tickets and counts them."""

    def __init__(self, dry: bool, pause: float, existing: dict[str, int]):
        """Store the mode, the pause between writes and the known issue titles."""
        self.dry = dry
        self.pause = pause
        self.existing = existing
        self.counts = {"umbrella": 0, "category": 0, "app": 0}

    def ticket(self, kind: str, title: str, body: str, labels: list[str], parent: int | None) -> tuple[int | None, bool]:
        """Handle one ticket and return (number or None, whether it was newly created)."""
        self.counts[kind] += 1
        if title in self.existing:
            print(f"[skip] {title} (exists as #{self.existing[title]})")
            return self.existing[title], False
        if self.dry:
            print(f"--- [{kind}] {title}\nlabels: {', '.join(labels)}\nparent: {parent or 'none'}\n{body}")
            return None, True
        number = create_issue(title, body, labels, parent)
        print(f"created #{number} {title}")
        time.sleep(self.pause)
        return number, True

    def update(self, number: int | None, body: str) -> None:
        """Rewrite a body once the child numbers are known; does nothing in dry-run."""
        if self.dry or not number:
            return
        edit_body(number, body)
        time.sleep(self.pause)


def run_category(r: Runner, cat: dict, src: dict, parent: int | None) -> int | None:
    """Create a category ticket and its app tickets; return the category number."""
    labels = ["help wanted", "app-rule", category_label(cat)]
    num, created = r.ticket("category", category_title(cat), category_body(cat, src, {}), labels, parent)
    numbers: dict[str, int | None] = {}
    any_new = created
    for app in cat["apps"]:
        if app.get("covered"):
            continue
        app_labels = ["help wanted", "good first issue", "app-rule", category_label(cat), "no-lab-needed"]
        n, new = r.ticket("app", app_title(app), app_body(app), app_labels, num)
        numbers[app["name"]] = n
        any_new = any_new or new
    if any_new:
        r.update(num, category_body(cat, src, numbers))
    return num


def parse_args() -> argparse.Namespace:
    """Parse the command line."""
    p = argparse.ArgumentParser(description="Create the app-rule tickets from apps.json.")
    p.add_argument("--dry-run", action="store_true", help="print the tickets and write nothing")
    p.add_argument("--category", type=int, help="only this category, 1-based")
    p.add_argument("--umbrella", action="store_true", help="also create the umbrella with --category")
    p.add_argument("--sleep", type=float, default=3, help="seconds between writes (default 3)")
    p.add_argument("--check-existing", action="store_true", help="in dry-run, still look up existing issues")
    return p.parse_args()


def main() -> int:
    """Run the script and print a count line."""
    args = parse_args()
    data = load_data()
    cats = data["categories"]
    if args.category is not None and not 1 <= args.category <= len(cats):
        sys.exit(f"--category must be between 1 and {len(cats)}")
    chosen = cats if args.category is None else [cats[args.category - 1]]
    existing = fetch_existing() if (not args.dry_run or args.check_existing) else {}
    if not args.dry_run:
        ensure_labels(data)
    r = Runner(args.dry_run, args.sleep, existing)
    umbrella = None
    if args.category is None or args.umbrella:
        umbrella, _ = r.ticket("umbrella", UMBRELLA_TITLE, umbrella_body(cats, {}), UMBRELLA_LABELS, None)
        if umbrella is None and UMBRELLA_TITLE in existing:
            umbrella = existing[UMBRELLA_TITLE]
    elif UMBRELLA_TITLE in existing:
        umbrella = existing[UMBRELLA_TITLE]
    cat_numbers = {}
    for cat in chosen:
        cat_numbers[cat["slug"]] = run_category(r, cat, data["sources"], umbrella)
    if not args.dry_run and umbrella:
        if r.counts["umbrella"] and UMBRELLA_TITLE not in existing:
            gh(["issue", "pin", str(umbrella)])
        for cat in cats:
            cat_numbers.setdefault(cat["slug"], existing.get(category_title(cat)))
        r.update(umbrella, umbrella_body(cats, cat_numbers))
    c = r.counts
    print(f"{c['umbrella']} umbrella + {c['category']} category + {c['app']} app tickets"
          + (" (dry run, nothing written)" if args.dry_run else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
