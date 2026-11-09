#!/usr/bin/env python3
"""Tests for scripts/gen-rules-doc.py, run against fixture rule files in a temp folder."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("gen", Path(__file__).with_name("gen-rules-doc.py"))
gen = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gen)


def rule(rid, tier="rebuild", **extra):
    """Build a fixture rule."""
    base = {"id": rid, "title": f"T {rid}", "pattern": f"~/x/{rid}", "tier": tier, "whatItIs": "It.",
            "consequence": "Cost.", "sideCondition": None, "cleanupCommand": None,
            "ownerBundleIDs": [], "source": None, "evidence": {"method": "vendor-doc"}}
    base.update(extra)
    return base


class GenTests(unittest.TestCase):
    """Checks entry format, evidence lines, ordering, summary and --check."""

    def setUp(self):
        """Create a temp rules folder with two files written out of order."""
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.out = self.dir / "out.md"
        (self.dir / "rules").mkdir()
        self.write("20-b.json", "Second", [rule("b.one", "never", sideCondition="Wait.",
                                                  cleanupCommand="do it", ownerBundleIDs=["com.a", "com.b"],
                                                  source="Src")])
        self.write("10-a.json", "First", [
            rule("a.measured", source="Measured: removed and relaunched Slack 4.53 on macOS 15.7",
                 evidence={"method": "relaunch-test", "appVersion": "4.53.280", "macOSVersion": "15.7.7",
                           "measuredOn": "2026-11-08", "observed": "Saw it."}),
            rule("a.research", "review", evidence={"method": "research"}),
            rule("a.loc", "never", evidence={"method": "location", "observed": "Listed."}),
        ])

    def tearDown(self):
        """Remove the temp folder."""
        self.tmp.cleanup()

    def write(self, name, title, rules):
        """Write one fixture rule file."""
        doc = {"version": 1, "section": {"title": title, "intro": f"{title} intro."}, "rules": rules}
        (self.dir / "rules" / name).write_text(json.dumps(doc))

    def text(self):
        """Render the fixture folder."""
        return gen.render(gen.load_sections(self.dir / "rules"))

    def test_file_order_and_sections(self):
        """Sections follow file-name order with title and intro."""
        t = self.text()
        self.assertLess(t.index("## First\n\nFirst intro."), t.index("## Second\n\nSecond intro."))

    def test_entry_format(self):
        """A full entry has every line in order, with owners joined."""
        t = self.text()
        e = t[t.index("### T b.one"):]
        self.assertIn("**Tier: never** · `b.one`", e)
        order = ["**Pattern:**", "**What it is:**", "**If you remove it:**", "**Condition:** Wait.",
                 "**Official command:** `do it`", "**Owning app:** `com.a`, `com.b`", "**Source:** Src"]
        pos = [e.index(o) for o in order]
        self.assertEqual(pos, sorted(pos))

    def test_evidence_lines(self):
        """Measured, Evidence unverified and Observed lines appear for the right methods."""
        t = self.text()
        self.assertIn("- **Measured:** Saw it. (Slack 4.53.280, macOS 15.7.7, 2026-11-08)", t)
        self.assertEqual(t.count("- **Evidence:** unverified"), 1)
        self.assertIn("- **Observed:** Listed.", t)
        self.assertNotIn("Measured:** Listed", t)

    def test_measured_without_app_name(self):
        """The app name is omitted when the source does not name one."""
        r = rule("x", evidence={"method": "relaunch-test", "appVersion": "1", "macOSVersion": "2",
                                "measuredOn": "3", "observed": "O."})
        self.assertIn("(1, macOS 2, 3)", gen.entry(r))

    def test_summary(self):
        """The summary gives the total and the count per tier."""
        self.assertIn("4 rules in total: 0 safe, 1 rebuild, 1 review, 2 never.", self.text())

    def test_check_mode(self):
        """--check passes on a fresh page, fails after a change, and never writes."""
        args = ["--rules", str(self.dir / "rules"), "--output", str(self.out)]
        self.assertEqual(gen.main(["--check"] + args), 1)
        self.assertFalse(self.out.exists())
        self.assertEqual(gen.main(args), 0)
        self.assertEqual(gen.main(["--check"] + args), 0)
        self.out.write_text("changed")
        self.assertEqual(gen.main(["--check"] + args), 1)
        self.assertEqual(self.out.read_text(), "changed")


if __name__ == "__main__":
    unittest.main()
