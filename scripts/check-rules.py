#!/usr/bin/env python3
"""Check the reclaim rule files in rules/*.json against contributor policy. Standard library only.

Usage: python3 scripts/check-rules.py [rules_dir]

Prints one line per problem as `file: rule-id: problem` and exits 1 when there are any.
The app's own loader and its Swift tests (RuleFilesTests loads the real files) stay the
authority on whether a pattern compiles; the pattern check here mirrors it for early feedback.
"""
from __future__ import annotations

import datetime
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = ROOT / "rules"

TIERS = ("safe", "rebuild", "review", "never")
METHODS = ("relaunch-test", "vendor-doc", "location", "research")
STRONG_METHODS = ("relaunch-test", "vendor-doc")
TOP_KEYS = {"$schema", "version", "section", "rules"}
RULE_KEYS = {"id", "title", "pattern", "tier", "whatItIs", "consequence", "sideCondition",
             "cleanupCommand", "ownerBundleIDs", "source", "evidence"}
EVIDENCE_KEYS = {"method", "appVersion", "macOSVersion", "measuredOn", "observed"}
MEASURED_FIELDS = ("appVersion", "macOSVersion", "measuredOn", "observed")

FILE_RE = re.compile(r"^\d{2}-[a-z0-9-]+\.json$")
ID_RE = re.compile(r"^[a-z0-9]+(\.[a-z0-9-]+)*$")
BUNDLE_RE = re.compile(r"^[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+)+$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
HOME_RE = re.compile(r"/(?:Users|home)/(?!\*)[^/\s\"']+")
EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
LONG_NUMBER_RE = re.compile(r"[0-9a-fA-F]{12,}|\d{9,}")

# Rebuild rules that still rest on research evidence. This set may only shrink: when a rule
# gains a relaunch test or vendor document, delete its id here. A listed rule that no longer
# exists, or is no longer rebuild with research evidence, is reported so the set gets pruned.
LEGACY_UNVERIFIED = {
    "caches.spotify", "caches.xcode", "caches.chrome", "caches.firefox",
    "xcode.deriveddata", "cocoapods.cache", "mail.downloads", "chromium.caches",
}


def blank(value) -> bool:
    """True when the value is not a string or holds only whitespace."""
    return not isinstance(value, str) or not value.strip()


def check_file_shell(name: str, doc) -> list:
    """Check file name, top-level keys, version and section; return problem texts."""
    problems = []
    if not FILE_RE.match(name):
        problems.append("file name must look like 10-name.json")
    if not isinstance(doc, dict):
        return problems + ["top level must be an object"]
    for key in sorted(set(doc) - TOP_KEYS):
        problems.append(f"unknown top-level key '{key}'")
    if doc.get("version") != 1:
        problems.append("version must be 1")
    section = doc.get("section")
    if not isinstance(section, dict):
        problems.append("section must be an object with title and intro")
    else:
        for key in ("title", "intro"):
            if blank(section.get(key)):
                problems.append(f"section.{key} is missing or empty")
        for key in sorted(set(section) - {"title", "intro"}):
            problems.append(f"unknown section key '{key}'")
    if not isinstance(doc.get("rules"), list):
        problems.append("rules must be a list")
    return problems


def check_fields(rule: dict) -> list:
    """Check required strings, nullable strings, owner bundle IDs and unknown keys."""
    problems = [f"unknown key '{k}'" for k in sorted(set(rule) - RULE_KEYS)]
    for key in ("id", "title", "pattern", "tier", "whatItIs", "consequence"):
        if blank(rule.get(key)):
            problems.append(f"{key} is missing or empty")
    for key in ("sideCondition", "cleanupCommand", "source"):
        if key not in rule:
            problems.append(f"{key} is missing (use null for none)")
        elif rule[key] is not None and blank(rule[key]):
            problems.append(f"{key} must be a non-empty string or null")
    owners = rule.get("ownerBundleIDs")
    if not isinstance(owners, list):
        problems.append("ownerBundleIDs must be a list")
    else:
        for owner in owners:
            if not isinstance(owner, str) or not BUNDLE_RE.match(owner):
                problems.append(f"ownerBundleIDs entry '{owner}' is not a reverse-DNS name")
    return problems


def check_id_format(rule: dict) -> list:
    """Check the id is lowercase and dotted."""
    rid = rule.get("id")
    if isinstance(rid, str) and rid.strip() and not ID_RE.match(rid):
        return ["id must be lowercase letters, digits and hyphens, joined by dots"]
    return []


def check_tier_and_evidence(rule: dict) -> list:
    """Check the tier and method enums, the relaunch-test fields and that measuredOn is a real date, not in the future."""
    problems = []
    tier = rule.get("tier")
    if isinstance(tier, str) and tier.strip() and tier not in TIERS:
        problems.append(f"unknown tier '{tier}'")
    ev = rule.get("evidence")
    if not isinstance(ev, dict):
        return problems + ["evidence is missing"]
    problems += [f"unknown evidence key '{k}'" for k in sorted(set(ev) - EVIDENCE_KEYS)]
    method = ev.get("method")
    if blank(method):
        return problems + ["evidence.method is missing or empty"]
    if method not in METHODS:
        return problems + [f"unknown evidence.method '{method}'"]
    if method == "relaunch-test":
        problems += [f"evidence.{f} is missing or empty" for f in MEASURED_FIELDS if blank(ev.get(f))]
    measured = ev.get("measuredOn")
    if isinstance(measured, str) and measured.strip() and not valid_date(measured):
        problems.append(f"evidence.measuredOn '{measured}' is not a real YYYY-MM-DD date")
    elif isinstance(measured, str) and valid_date(measured) and datetime.date.fromisoformat(measured) > datetime.date.today():
        problems.append(f"evidence.measuredOn '{measured}' is in the future; use the date the measurement was made")
    return problems


def valid_date(text: str) -> bool:
    """True when the text is a real calendar date written YYYY-MM-DD."""
    if not DATE_RE.match(text):
        return False
    try:
        datetime.date.fromisoformat(text)
    except ValueError:
        return False
    return True


def check_tier_vs_evidence(rule: dict) -> list:
    """Check safe and rebuild rules rest on a relaunch test or vendor document and name a source."""
    if rule.get("tier") not in ("safe", "rebuild"):
        return []
    ev = rule.get("evidence")
    method = ev.get("method") if isinstance(ev, dict) else None
    if method in legacy_methods(rule):
        return []
    problems = []
    if method == "location":
        problems.append(f"{rule['tier']} rules cannot use location evidence")
    elif method is not None and method not in STRONG_METHODS:
        problems.append(f"{rule['tier']} rules need evidence.method relaunch-test or vendor-doc, not {method}")
    if rule.get("source") is None or blank(rule.get("source")):
        problems.append(f"{rule['tier']} rules need a source")
    return problems


def legacy_methods(rule: dict) -> tuple:
    """Return ("research",) for a rebuild rule listed in LEGACY_UNVERIFIED, else an empty tuple."""
    if rule.get("id") in LEGACY_UNVERIFIED and rule.get("tier") == "rebuild":
        return ("research",)
    return ()


def check_legacy_set(rules_by_id: dict) -> list:
    """Report LEGACY_UNVERIFIED ids that no longer exist or are no longer rebuild with research evidence."""
    problems = []
    for rid in sorted(LEGACY_UNVERIFIED):
        rule = rules_by_id.get(rid)
        if rule is None:
            problems.append((rid, "is in LEGACY_UNVERIFIED but no rule has this id; remove it from the set"))
            continue
        ev = rule.get("evidence") if isinstance(rule.get("evidence"), dict) else {}
        if rule.get("tier") != "rebuild" or ev.get("method") != "research":
            problems.append((rid, "is in LEGACY_UNVERIFIED but is no longer rebuild with research evidence; remove it from the set"))
    return problems


def check_pattern(rule: dict) -> list:
    """Check each ` || ` part has a valid anchor, a segment and a last segment other than `**`."""
    pattern = rule.get("pattern")
    if blank(pattern):
        return []
    problems = []
    for part in pattern.split(" || "):
        path = part.split(" if-sibling:")[0]
        segments = [s for s in path.split("/") if s]
        if path.startswith("**/") or path.startswith("~"):
            segments = segments[1:]
        elif not path.startswith("/"):
            problems.append(f"pattern part must start with ~, / or **/: '{part}'")
            continue
        if not segments:
            problems.append(f"pattern part has no path segment: '{part}'")
        elif segments[-1] == "**":
            problems.append(f"pattern part must not end with **: '{part}'")
    return problems


def strings_of(rule: dict) -> list:
    """Return (field, text) for every string in the rule except ownerBundleIDs."""
    found = []
    for key, value in rule.items():
        if key == "ownerBundleIDs":
            continue
        if isinstance(value, str):
            found.append((key, value))
        elif isinstance(value, dict):
            found += [(f"{key}.{k}", v) for k, v in value.items() if isinstance(v, str)]
    return found


def check_privacy(rule: dict) -> list:
    """Check no string holds a real user name, email address or account number."""
    problems = []
    for field, text in strings_of(rule):
        if HOME_RE.search(text):
            problems.append(f"{field} has a real user name in a path; replace account-specific parts with *")
        if EMAIL_RE.search(text):
            problems.append(f"{field} has an email address; replace account-specific parts with *")
        if LONG_NUMBER_RE.search(text):
            problems.append(f"{field} has a long number or hex run that looks like an account ID; replace account-specific parts with *")
    return problems


def check_copy(rule: dict) -> list:
    """Check whatItIs and consequence end with a full stop and the title does not."""
    problems = []
    for key in ("whatItIs", "consequence"):
        text = rule.get(key)
        if isinstance(text, str) and text.strip() and not text.rstrip().endswith("."):
            problems.append(f"{key} must end with a full stop")
    title = rule.get("title")
    if isinstance(title, str) and title.rstrip().endswith("."):
        problems.append("title must not end with a full stop")
    return problems


RULE_CHECKS = (check_fields, check_id_format, check_tier_and_evidence, check_tier_vs_evidence,
               check_pattern, check_privacy, check_copy)


def check_rule(rule) -> list:
    """Run every per-rule check on one rule and return the problem texts."""
    if not isinstance(rule, dict):
        return ["rule must be an object"]
    return [p for check in RULE_CHECKS for p in check(rule)]


def check_directory(directory: Path) -> tuple:
    """Check every *.json file in the folder; return (problem lines, rule count, file count)."""
    lines = []
    seen = {}
    rules_by_id = {}
    count = 0
    files = sorted(directory.glob("*.json"))
    for path in files:
        name = path.name
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError) as err:
            lines.append(f"{name}: -: not valid JSON ({err})")
            continue
        lines += [f"{name}: -: {p}" for p in check_file_shell(name, doc)]
        rules = doc.get("rules") if isinstance(doc, dict) and isinstance(doc.get("rules"), list) else []
        for rule in rules:
            count += 1
            rid = rule.get("id") if isinstance(rule, dict) else None
            label = rid if isinstance(rid, str) and rid else "-"
            lines += [f"{name}: {label}: {p}" for p in check_rule(rule)]
            if isinstance(rid, str) and rid:
                if rid in seen:
                    lines.append(f"{name}: {rid}: duplicate id, also in {seen[rid]}")
                seen.setdefault(rid, name)
                rules_by_id.setdefault(rid, rule)
    if directory.resolve() == RULES_DIR.resolve():
        lines += [f"check-rules.py: {rid}: {p}" for rid, p in check_legacy_set(rules_by_id)]
    return lines, count, len(files)


def main(argv: list) -> int:
    """Check the rules folder, print each problem or a one-line summary, and return the exit code."""
    directory = Path(argv[0]) if argv else RULES_DIR
    lines, count, files = check_directory(directory)
    if lines:
        print("\n".join(lines))
        return 1
    print(f"{count} rules in {files} files: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
