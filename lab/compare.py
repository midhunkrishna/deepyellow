"""Compare two DeepYellow disk snapshots and report where an app's files grew.

Snapshots are CSV from `DeepYellow --cli sql <root> "SELECT path, is_dir, size,
logical, file_count, modified, safety FROM nodes" --csv`. Every path written to
the JSON and Markdown reports is scrubbed of account-specific details; only the
optional raw JSON keeps real paths.
"""

import argparse
import csv
import json
import re
import sys
from collections import defaultdict

HEADER = ["path", "is_dir", "size", "logical", "file_count", "modified", "safety"]
EXPLAIN_FRACTION = 0.8
DEFAULT_MIN_BYTES = 1048576
VAR_FOLDERS = ("/private/var/folders/", "/var/folders/")
# A folder inside one of these is usually named after an account (e.g. Spotify's PersistentCache/Users/<name>-user).
ACCOUNT_PARENTS = {"users", "accounts"}

UUID_RE = re.compile(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+")
HEX_RE = re.compile(r"[0-9A-Fa-f]{16,}")
DIGITS_RE = re.compile(r"[0-9]{6,}")
SLACK_PART_RE = re.compile(r"[TUWEBC][A-Z0-9]{8,12}")
TOKEN_RE = re.compile(r"[A-Za-z0-9_\-]{20,}")
SPLIT_RE = re.compile(r"([\-_.])")


# ---------------------------------------------------------------- loading

def parse_snapshot(lines):
    """Parse snapshot CSV lines into {path: (size, files, safety)} for folders only."""
    reader = csv.reader(lines)
    head = next(reader, None)
    if head is None or [h.strip() for h in head] != HEADER:
        raise ValueError("snapshot header must be " + ",".join(HEADER))
    nodes = {}
    for row in reader:
        if len(row) < 6 or row[1].strip().lower() not in ("1", "true"):
            continue
        try:
            size, files = int(row[2]), int(row[4])
        except ValueError:
            continue
        path = row[0] if row[0] == "/" else row[0].rstrip("/")
        nodes[path] = (size, files, row[6].strip() if len(row) > 6 else "")
    return nodes


def load_snapshot(path):
    """Read a snapshot CSV file from disk."""
    with open(path, newline="", encoding="utf-8") as handle:
        return parse_snapshot(handle)


# ------------------------------------------------------------------- tree

def parent_of(path):
    """Return the parent folder path, or None for the filesystem root."""
    if path == "/":
        return None
    return path.rsplit("/", 1)[0] or "/"


def build_children(paths):
    """Map each path to its direct children among `paths`; return (children, roots)."""
    known = set(paths)
    children = defaultdict(list)
    roots = []
    for path in paths:
        parent = parent_of(path)
        if parent is not None and parent in known:
            children[parent].append(path)
        else:
            roots.append(path)
    return children, roots


def find_growth_roots(roots, children, delta, min_bytes, sign):
    """Return folders where growth (sign=1) or shrinkage (sign=-1) concentrates."""
    found = []
    stack = list(roots)
    while stack:
        path = stack.pop()
        change = delta[path] * sign
        if change < min_bytes:
            continue
        big = [c for c in children.get(path, ()) if delta[c] * sign >= min_bytes]
        explained = sum(delta[c] * sign for c in big)
        if big and explained >= EXPLAIN_FRACTION * change:
            stack.extend(big)
        else:
            found.append(path)
    return found


def find_new_folders(after, before, children, roots):
    """Return the top folder of every subtree that exists after but not before."""
    found = []
    stack = list(roots)
    while stack:
        path = stack.pop()
        if path not in after:
            continue
        if path not in before:
            found.append(path)
        else:
            stack.extend(children.get(path, ()))
    return found


def noise_paths(first, second):
    """Return paths that changed size or appeared/vanished between two idle snapshots."""
    return {p for p in set(first) | set(second)
            if first.get(p, (None,))[0] != second.get(p, (None,))[0]}


# --------------------------------------------------------------- scrubbing

def _mask_slack_parts(component):
    """Replace Slack-style ID parts of a component, splitting on `-`, `_` and `.`."""
    parts = SPLIT_RE.split(component)
    for i in range(0, len(parts), 2):
        part = parts[i]
        if SLACK_PART_RE.fullmatch(part) and any(ch.isdigit() for ch in part):
            parts[i] = "*"
    return "".join(parts)


def _mask_token(match):
    """Replacement for a long run that is masked only if it mixes letters and digits."""
    text = match.group(0)
    if any(c.isdigit() for c in text) and any(c.isalpha() for c in text):
        return "*"
    return text


def scrub_component(component):
    """Mask account-specific pieces inside a single path component."""
    if component in ("", "~", "*"):
        return component
    for pattern in (EMAIL_RE, UUID_RE):
        component = pattern.sub("*", component)
    component = TOKEN_RE.sub(_mask_token, component)
    for pattern in (HEX_RE, DIGITS_RE):
        component = pattern.sub("*", component)
    return _mask_slack_parts(component)


def scrub_path(path, home, redact):
    """Scrub a path: home becomes `~`, redact strings and ID-like parts become `*`."""
    home = home.rstrip("/")
    if home and (path == home or path.startswith(home + "/")):
        path = "~" + path[len(home):]
    for text in redact:
        if text:
            path = re.sub(re.escape(text), "*", path, flags=re.IGNORECASE)
    parts = path.split("/")
    for prefix in VAR_FOLDERS:
        if path.startswith(prefix):
            start = len(prefix.split("/")) - 1  # index just after the prefix
            for i in range(start, min(start + 2, len(parts))):
                parts[i] = "*"
            break
    for i in range(1, len(parts)):
        if parts[i - 1].lower() in ACCOUNT_PARENTS and parts[i]:
            parts[i] = "*"
    return "/".join(scrub_component(p) for p in parts)


# ---------------------------------------------------------------- analysis

def make_row(path, nodes_before, nodes_after, is_new, tokens, noise, new_total=False):
    """Build one unscrubbed report row for a folder path."""
    size_b, files_b, _ = nodes_before.get(path, (0, 0, ""))
    size_a, files_a, safety_a = nodes_after.get(path, (0, 0, ""))
    lowered = path.lower()
    return {
        "pattern": path,
        "bytesAdded": size_a - size_b,
        "filesAdded": files_a - files_b,
        "sizeAfter": size_a,
        "isNew": is_new,
        "attributed": any(t.lower() in lowered for t in tokens),
        "noise": path in noise,
        "safety": safety_a or nodes_before.get(path, (0, 0, ""))[2],
    }


def merge_rows(rows, scrub):
    """Scrub each row's pattern and merge rows with equal patterns by summing."""
    merged = {}
    for row in sorted(rows, key=lambda r: abs(r["bytesAdded"]), reverse=True):
        key = scrub(row["pattern"])
        into = merged.get(key)
        if into is None:
            merged[key] = dict(row, pattern=key)
            continue
        into["bytesAdded"] += row["bytesAdded"]
        into["filesAdded"] += row["filesAdded"]
        into["sizeAfter"] += row["sizeAfter"]
        for flag in ("isNew", "attributed", "noise"):
            into[flag] = into[flag] or row[flag]
        into["safety"] = into["safety"] or row["safety"]
    return list(merged.values())


def analyze(before, after, home="", app_tokens=(), noise=None, redact=(),
            min_bytes=DEFAULT_MIN_BYTES, raw=False):
    """Compare two snapshots and return {totals, growth, newFolders, shrank}.

    Paths are scrubbed unless `raw` is true. `noise` is an optional pair of
    snapshots taken with the app idle.
    """
    paths = set(before) | set(after)
    delta = {p: after.get(p, (0,))[0] - before.get(p, (0,))[0] for p in paths}
    children, roots = build_children(paths)
    noisy = noise_paths(*noise) if noise else set()
    new_top = find_new_folders(after, before, children, roots)
    new_set = set(new_top)

    def rows(selected, force_new=False):
        """Rows for the selected paths, flagging those under new folders."""
        return [make_row(p, before, after, force_new or p in new_set or p not in before,
                         app_tokens, noisy) for p in selected]

    groups = {
        "growth": rows(find_growth_roots(roots, children, delta, min_bytes, 1)),
        "newFolders": rows(new_top, True),
        "shrank": rows(find_growth_roots(roots, children, delta, min_bytes, -1)),
    }
    if raw:
        def scrub(path):
            """Keep the real path."""
            return path
    else:
        def scrub(path):
            """Scrub the path for publication."""
            return scrub_path(path, home, list(redact))
    result = {}
    for name, items in groups.items():
        merged = merge_rows(items, scrub)
        merged.sort(key=lambda r: r["bytesAdded"], reverse=(name != "shrank"))
        result[name] = merged
    growth = result["growth"]
    result["totals"] = {
        "bytesAdded": sum(r["bytesAdded"] for r in growth),
        "filesAdded": sum(r["filesAdded"] for r in growth),
        "attributedBytesAdded": sum(r["bytesAdded"] for r in growth if r["attributed"]),
    }
    return {k: result[k] for k in ("totals", "growth", "newFolders", "shrank")}


# ------------------------------------------------------------------ output

def format_size(num):
    """Format a byte count with decimal units, e.g. `12.3 MB`."""
    value = float(num)
    for unit in ("B", "KB", "MB", "GB"):
        if abs(value) < 1000 or unit == "GB":
            return f"{int(value)} B" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1000
    return f"{value:.1f} TB"


def _md_table(title, rows):
    """Render one row group as a Markdown table."""
    lines = [f"## {title}", ""]
    if not rows:
        return lines + ["None.", ""]
    lines += ["| Pattern | Added | Files | Size after | New | App | Noise | Safety |",
              "|---|---:|---:|---:|---|---|---|---|"]
    for r in rows:
        pattern = r["pattern"].replace("|", "\\|")
        lines.append(
            f"| `{pattern}` | {format_size(r['bytesAdded'])} | {r['filesAdded']} | "
            f"{format_size(r['sizeAfter'])} | {'yes' if r['isNew'] else ''} | "
            f"{'yes' if r['attributed'] else ''} | {'yes' if r['noise'] else ''} | "
            f"{r['safety']} |")
    return lines + [""]


def render_markdown(result):
    """Render the full result as Markdown."""
    t = result["totals"]
    lines = ["# Snapshot comparison", "",
             f"- Bytes added: {format_size(t['bytesAdded'])}",
             f"- Files added: {t['filesAdded']}",
             f"- Attributed to the app: {format_size(t['attributedBytesAdded'])}", ""]
    lines += _md_table("Growth", result["growth"])
    lines += _md_table("New folders", result["newFolders"])
    lines += _md_table("Shrank", result["shrank"])
    return "\n".join(lines)


def write_json(result, path):
    """Write a result dict as JSON."""
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2)
        handle.write("\n")


def write_outputs(result, json_path, md_path):
    """Write the JSON and Markdown reports."""
    write_json(result, json_path)
    with open(md_path, "w", encoding="utf-8") as handle:
        handle.write(render_markdown(result) + "\n")


# --------------------------------------------------------------------- CLI

def parse_args(argv):
    """Parse command-line arguments."""
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("before")
    p.add_argument("after")
    p.add_argument("--home", required=True)
    p.add_argument("--app-token", action="append", default=[])
    p.add_argument("--noise", nargs=2, metavar=("N0", "N1"))
    p.add_argument("--redact", action="append", default=[])
    p.add_argument("--min-bytes", type=int, default=DEFAULT_MIN_BYTES)
    p.add_argument("--json", required=True)
    p.add_argument("--md", required=True)
    p.add_argument("--raw-json")
    return p.parse_args(argv)


def main(argv=None):
    """Run the comparison from the command line and write the reports."""
    args = parse_args(sys.argv[1:] if argv is None else argv)
    before, after = load_snapshot(args.before), load_snapshot(args.after)
    noise = tuple(load_snapshot(n) for n in args.noise) if args.noise else None
    common = dict(home=args.home, app_tokens=args.app_token, noise=noise,
                  redact=args.redact, min_bytes=args.min_bytes)
    write_outputs(analyze(before, after, **common), args.json, args.md)
    if args.raw_json:
        write_json(analyze(before, after, raw=True, **common), args.raw_json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
